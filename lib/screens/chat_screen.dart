import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat_message.dart';
import '../services/gemini_service.dart';
import '../services/global_audio_service.dart';
import '../services/web_search_service.dart';
import '../services/speech/speech_service.dart';
import '../services/chat_history_service.dart';
import '../theme/gemini_colors.dart';
import '../widgets/gemini_sparkle.dart';
import '../services/jarvis_brain_service.dart';
import '../services/jarvis_tts_service.dart';

class ChatScreen extends StatefulWidget {
  final Function(String songQuery)? onNavigateToMusicDownload;
  final Function(String songQuery)? onNavigateToMusicPlay;
  final VoidCallback? onOpenSidebar;
  final String? activeSessionId;
  final void Function(String sessionId, List<ChatMessage> messages)?
      onSessionChanged;

  const ChatScreen({
    super.key,
    this.onNavigateToMusicDownload,
    this.onNavigateToMusicPlay,
    this.onOpenSidebar,
    this.activeSessionId,
    this.onSessionChanged,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  TextEditingController? _textControllerField;
  TextEditingController? _editingControllerField;
  ScrollController? _scrollControllerField;

  TextEditingController get _textController =>
      _textControllerField ??= TextEditingController();
  TextEditingController get _editingController =>
      _editingControllerField ??= TextEditingController();
  ScrollController get _scrollController =>
      _scrollControllerField ??= ScrollController();

  final GeminiService _geminiService = GeminiService();

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  List<Map<String, String>>?
      _activeSearchingSources; // Google AI Modu: Arama anında gösterilen kaynaklar
  String _selectedMode = 'general'; // 'general' or 'projects'

  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      var host = uri.host;
      if (host.startsWith('www.')) host = host.substring(4);
      return host.isNotEmpty ? host : 'web';
    } catch (_) {
      return 'web';
    }
  }

  Widget _buildFavicon(String domain, double size) {
    if (domain.isEmpty || domain == 'web') {
      return Icon(Icons.language, size: size, color: GeminiColors.geminiBlue);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image.network(
        'https://www.google.com/s2/favicons?domain=$domain&sz=32',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          Icons.public_rounded,
          size: size,
          color: GeminiColors.geminiBlue,
        ),
      ),
    );
  }

  // Aktif oturum ID'si (geçmişten yükleme veya yeni oluşturma)
  String? _currentSessionId;

  // Seçili Gemini Modeli
  String _selectedModel = 'gemini-2.5-flash';
  String _selectedModelLabel = 'Gemini 2.5 Flash';

  // Düzenleme Modu Durumu (Fotoğraftaki Birebir Tam Ekran Düzenleme Sekmesi)
  bool _isEditingPrompt = false;
  ChatMessage? _editingMessage;

  // Sesli Yazma Servisi (Web'de yerel Web Speech API, mobilde yerel recognizer)
  AppSpeechService? _speechServiceField;
  AppSpeechService get _speechService =>
      _speechServiceField ??= AppSpeechService();
  bool _isSpeechInitialized = false;
  bool _isListening = false;

  // Seçilen Görsel Durumu (Multimodal Vision)
  Uint8List? _selectedImageBytes;
  String? _selectedImageMimeType;
  final ImagePicker _imagePicker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        final mimeType = pickedFile.mimeType ?? 'image/jpeg';
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImageMimeType = mimeType;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotoğraf seçilemedi: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _clearSelectedImage() {
    setState(() {
      _selectedImageBytes = null;
      _selectedImageMimeType = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _textControllerField ??= TextEditingController();
    _editingControllerField ??= TextEditingController();
    _scrollControllerField ??= ScrollController();
    ChatHistoryService.instance.init();
    // Eğer başlangıçta bir oturum ID'si verilmişse yükle
    if (widget.activeSessionId != null) {
      _loadSession(widget.activeSessionId!);
    }
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Dışarıdan farklı bir oturum ID'si gelirse mesajları güncelle
    if (widget.activeSessionId != oldWidget.activeSessionId) {
      if (widget.activeSessionId == null) {
        // Yeni sohbet: temizle
        setState(() {
          _messages.clear();
          _currentSessionId = null;
        });
      } else {
        _loadSession(widget.activeSessionId!);
      }
    }
  }

  void _loadSession(String sessionId) {
    final session = ChatHistoryService.instance.getSession(sessionId);
    if (session != null) {
      setState(() {
        _messages.clear();
        _messages.addAll(session.messages);
        _currentSessionId = sessionId;
      });
    }
  }

  /// Mevcut sohbeti history'ye kaydeder
  Future<void> _saveCurrentSession() async {
    if (_messages.isEmpty) return;
    final sessionId =
        _currentSessionId ?? DateTime.now().millisecondsSinceEpoch.toString();
    _currentSessionId = sessionId;

    // Başlık: ilk kullanıcı mesajının ilk 40 karakteri
    final firstUserMsg = _messages.firstWhere(
      (m) => m.isUser,
      orElse: () => _messages.first,
    );
    final title = firstUserMsg.content.length > 40
        ? '${firstUserMsg.content.substring(0, 40)}...'
        : firstUserMsg.content;

    final session = ChatSession(
      id: sessionId,
      title: title.isEmpty ? 'Yeni Sohbet' : title,
      createdAt: _messages.first.timestamp,
      messages: List.from(_messages),
    );
    await ChatHistoryService.instance.saveSession(session);
    widget.onSessionChanged?.call(sessionId, List.from(_messages));
  }

  @override
  void dispose() {
    _speechServiceField?.stop();
    _textControllerField?.dispose();
    _editingControllerField?.dispose();
    _scrollControllerField?.dispose();
    super.dispose();
  }

  /// Sesli yazmayı başlatır veya durdurur
  Future<void> _toggleSpeechRecognition({bool forEditing = false}) async {
    if (_isListening) {
      await _speechService.stop();
      if (mounted) {
        setState(() => _isListening = false);
      }
      return;
    }

    try {
      if (!_isSpeechInitialized) {
        _isSpeechInitialized = await _speechService.initialize(
          onStatus: (status) {
            if (status == 'done' || status == 'notListening') {
              if (mounted) {
                setState(() => _isListening = false);
              }
            }
          },
          onError: (errorMessage) {
            if (mounted) {
              setState(() => _isListening = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(errorMessage),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
        );
      }

      if (!_isSpeechInitialized) return;

      final targetController =
          forEditing ? _editingController : _textController;
      final initialText = targetController.text.trim();

      if (mounted) {
        setState(() => _isListening = true);
      }

      await _speechService.listen(
        onResult: (words) {
          if (mounted) {
            setState(() {
              if (initialText.isEmpty) {
                targetController.text = words;
              } else {
                targetController.text = '$initialText $words';
              }
              targetController.selection = TextSelection.fromPosition(
                TextPosition(offset: targetController.text.length),
              );
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isListening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ses tanıma başlatılamadı: $e'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _isMusicCommand(String text) {
    final lower = text.toLowerCase();
    return lower.contains('indir') ||
        lower.startsWith('şarkı') ||
        lower.startsWith('müzik') ||
        lower.contains('mp3');
  }

  String _extractSongQuery(String text) {
    String query = text
        .replaceAll(
            RegExp(r'(lütfen|bana|şarkısını|şarkısı|indir|mp3|müziği|aç|çal)',
                caseSensitive: false),
            '')
        .trim();
    return query.isEmpty ? text : query;
  }

  Future<void> _handleSendMessage([String? customPrompt]) async {
    final text = (customPrompt ?? _textController.text).trim();
    final attachedImage = _selectedImageBytes;
    final attachedMime = _selectedImageMimeType;

    if ((text.isEmpty && attachedImage == null) || _isLoading) return;

    if (customPrompt == null) {
      _textController.clear();
      _clearSelectedImage();
    }

    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: text,
      isUser: true,
      timestamp: DateTime.now(),
      imageBytes: attachedImage,
      imageMimeType: attachedMime,
    );

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });
    _scrollToBottom();

    await _sendToGemini(text,
        imageBytes: attachedImage, mimeType: attachedMime);
  }

  /// Mesajı yerinde değiştirir, ardındaki eski yapay zeka cevabını siler ve Gemini'a yeniden istek atar
  Future<void> _handleEditAndResend(
      ChatMessage targetMsg, String newContent) async {
    if (_isLoading) return;

    final trimmedText = newContent.trim();
    if (trimmedText.isEmpty && targetMsg.imageBytes == null) return;

    final editIndex = _messages.indexWhere((m) => m.id == targetMsg.id);

    if (editIndex == -1) {
      await _handleSendMessage(trimmedText);
      return;
    }

    setState(() {
      // 1. Düzenlenen kullanıcı mesajını listede yerinde güncelle
      _messages[editIndex] = _messages[editIndex].copyWith(
        content: trimmedText,
        timestamp: DateTime.now(),
      );

      // 2. Bu mesajdan sonra gelen eski yapay zeka yanıtını ve sonraki mesajları kaldır
      if (editIndex + 1 < _messages.length) {
        _messages.removeRange(editIndex + 1, _messages.length);
      }

      _isLoading = true;
    });
    _scrollToBottom();

    await _sendToGemini(
      trimmedText,
      imageBytes: _messages[editIndex].imageBytes,
      mimeType: _messages[editIndex].imageMimeType,
    );
  }

  String? _checkExplicitSearch(String text) {
    final lower = text.toLowerCase().trim();
    final p = RegExp(
      r'^(?:web(?:de|den)?\s+ara(?:ştır)?|internette(?:n)?\s+ara(?:ştır)?|google(?:\x27?da)?\s+ara)\s*[:,\-]?\s*(.+)$',
      caseSensitive: false,
    );
    final m = p.firstMatch(lower);
    if (m != null) return m.group(1)?.trim();
    return null;
  }

  Future<void> _sendToGemini(
    String promptText, {
    Uint8List? imageBytes,
    String? mimeType,
  }) async {
    final isMusic = _isMusicCommand(promptText);
    bool wasWebSearch = false;
    String? executedSearchQuery;
    List<Map<String, String>>? collectedSources;

    try {
      String promptWithMode = promptText;
      if (_selectedMode == 'projects') {
        promptWithMode =
            '[MOD: YAZILIM PROJE DANIŞMANLIĞI] Kullanıcı şununla ilgili özgün, yapılabilir ve mimarisi detaylandırılmış bir proje fikri istiyor: $promptText';
      }

      // History olarak son eklenen veya güncellenen kullanıcı mesajından önceki konuşmayı veriyoruz
      final historyList = _messages.length > 1
          ? _messages.sublist(0, _messages.length - 1)
          : <ChatMessage>[];

      // 1. ÖN KONTROL: Kullanıcı doğrudan "webde ara: ...", "internetten ara: ..." dedi mi?
      String currentPrompt = promptWithMode;
      final explicitQuery = _checkExplicitSearch(promptText);
      if (explicitQuery != null && explicitQuery.isNotEmpty) {
        wasWebSearch = true;
        executedSearchQuery = explicitQuery;
        final results = await WebSearchService.instance
            .search(explicitQuery, limit: 5, includeDetail: false);
        if (results.isNotEmpty) {
          collectedSources =
              results.map((r) => {'title': r.title, 'url': r.url}).toList();
        }
        if (mounted) {
          setState(() {
            _activeSearchingSources = collectedSources;
          });
        }
        final webContext =
            WebSearchService.instance.formatForPrompt(results, explicitQuery);
        currentPrompt = results.isNotEmpty
            ? '$promptWithMode\n\n$webContext'
            : '$promptWithMode\n\n[WEB_ARAMA_SONUCLARI]\nArama yapıldı ancak sonuç boş döndü. Lütfen kullanıcının sorusunu doğrudan yanıtla.\n[/WEB_ARAMA_SONUCLARI]';
      }

      var response = await _geminiService.sendMessage(
        prompt: currentPrompt,
        history: historyList,
        model: _selectedModel,
        imageBytes: imageBytes,
        mimeType: mimeType,
      );

      // 2. OTOMATİK MOD: Gemini güncel bilgi gerektiğini anlayıp [ACTION:SEARCH:...] üretti mi?
      final searchMatch =
          RegExp(r'\[ACTION:SEARCH:(.+?)\]').firstMatch(response.text);
      if (searchMatch != null) {
        final query = searchMatch.group(1)?.trim() ?? '';
        if (query.isNotEmpty) {
          wasWebSearch = true;
          executedSearchQuery = query;

          // Hızlı ve zengin sonuç (5 kaynak)
          final results = await WebSearchService.instance
              .search(query, limit: 5, includeDetail: false);
          if (results.isNotEmpty) {
            collectedSources =
                results.map((r) => {'title': r.title, 'url': r.url}).toList();
          }

          if (mounted) {
            setState(() {
              _activeSearchingSources = collectedSources;
            });
          }

          final webContext =
              WebSearchService.instance.formatForPrompt(results, query);
          final enrichedPrompt = results.isNotEmpty
              ? '$promptWithMode\n\n$webContext'
              : '$promptWithMode\n\n[WEB_ARAMA_SONUCLARI]\nSorgu: "$query"\nArama yapıldı. Lütfen kullanıcının sorusuna doğrudan ve net bir yanıt ver. Asla [ACTION:SEARCH] üretme!\n[/WEB_ARAMA_SONUCLARI]';

          response = await _geminiService.sendMessage(
            prompt: enrichedPrompt,
            history: historyList,
            model: _selectedModel,
            imageBytes: imageBytes,
            mimeType: mimeType,
          );
        }
      }

      // ACTION etiketlerini parse et
      final rawText = response.text;
      final actionMatch = RegExp(
              r'\[ACTION:(DOWNLOAD|PLAY|STOP|HIDE_PLAYER|SHOW_PLAYER)(?::(.+?))?\]')
          .firstMatch(rawText);
      var cleanContent =
          rawText.replaceAll(RegExp(r'\[ACTION:[^\]]+\]'), '').trim();
      if (cleanContent.isEmpty) {
        if (wasWebSearch) {
          cleanContent =
              'İnternet araması tamamlandı ancak yanıt derlenemedi. Lütfen tekrar deneyin.';
        } else {
          cleanContent =
              rawText.trim().isNotEmpty ? rawText.trim() : 'İşlem tamamlandı.';
        }
      }

      final botMessage = ChatMessage(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        content: cleanContent,
        isUser: false,
        timestamp: DateTime.now(),
        usedModel: response.usedKeyLabel,
        isMusicCommand: isMusic,
        isWebSearch: wasWebSearch,
        searchQuery: executedSearchQuery,
        sources: collectedSources,
      );

      if (mounted) {
        setState(() {
          _messages.add(botMessage);
          _isLoading = false;
          _activeSearchingSources = null;
        });
        _scrollToBottom();
        _saveCurrentSession();

        // Aksiyon tetikle
        if (actionMatch != null) {
          final actionType = actionMatch.group(1);
          final songName = actionMatch.group(2)?.trim() ?? '';
          Future.delayed(const Duration(milliseconds: 200), () {
            if (!mounted) return;
            if (actionType == 'DOWNLOAD' && songName.isNotEmpty) {
              widget.onNavigateToMusicDownload?.call(songName);
            } else if (actionType == 'PLAY' && songName.isNotEmpty) {
              // Tab değişimi YOK — global player ile chat'te kal
              GlobalAudioService.instance.searchAndPlay(songName);
            } else if (actionType == 'STOP') {
              GlobalAudioService.instance.stop();
            } else if (actionType == 'HIDE_PLAYER') {
              GlobalAudioService.instance.hidePlayer();
            } else if (actionType == 'SHOW_PLAYER') {
              GlobalAudioService.instance.showPlayer();
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          debugPrint('Gemini sohbet hatası: $e');
          final userMessage = e is GeminiConfigurationException
              ? e.message
              : 'Yanıt şu an alınamadı. Bağlantınızı kontrol edip tekrar deneyin.';
          _messages.add(
            ChatMessage(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              content: userMessage,
              isUser: false,
              timestamp: DateTime.now(),
              usedModel: 'Hata',
            ),
          );
          _isLoading = false;
          _activeSearchingSources = null;
        });
        _scrollToBottom();
        // Hata olsa bile mevcut mesajları kaydet
        _saveCurrentSession();
      }
    }
  }

  /// Düzenlenen mesajı yerinde günceller ve Gemini'dan taze yanıt alır
  void _submitEditedPrompt() {
    final updatedText = _editingController.text.trim();
    if (updatedText.isEmpty) return;

    final target = _editingMessage;

    setState(() {
      _isEditingPrompt = false;
      _editingMessage = null;
    });

    if (target != null) {
      _handleEditAndResend(target, updatedText);
    } else {
      _handleSendMessage(updatedText);
    }
  }

  void _resetChat() {
    // Mevcut sohbeti kaydet (eğer mesaj varsa)
    if (_messages.isNotEmpty) {
      _saveCurrentSession();
    }
    setState(() {
      _messages.clear();
      _currentSessionId = null;
    });
    // Üst widget'a yeni sohbet başladığını bildir
    widget.onSessionChanged?.call('', []);
  }

  /// Kullanıcı mesajına basılı tuttuğunda açılan menü
  void _showUserMessageOptions(ChatMessage msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1F22),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF33353A), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.8),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Düzenle Seçeneği -> Fotoğraftaki tam ekran düzenleme sekmesini açar!
                ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit_outlined,
                        color: Colors.white, size: 20),
                  ),
                  title: const Text(
                    'Düzenle',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Metni tam ekranda düzenleyip yeniden gönderin',
                    style:
                        TextStyle(color: GeminiColors.textMuted, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _isEditingPrompt = true;
                      _editingMessage = msg;
                      _editingController.text = msg.content;
                      _editingController.selection = TextSelection.fromPosition(
                        TextPosition(offset: msg.content.length),
                      );
                    });
                  },
                ),

                const Divider(color: Color(0xFF2A2B30), height: 12),

                // Kopyala Seçeneği
                ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.copy_outlined,
                        color: GeminiColors.geminiCyan, size: 20),
                  ),
                  title: const Text(
                    'Metni Kopyala',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Panoya kopyalar',
                    style:
                        TextStyle(color: GeminiColors.textMuted, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: msg.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Mesaj panoya kopyalandı!'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Model Seçici Menüsü (Başlığa basıldığında açılır)
  void _showModelPickerMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1B1D),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF2E2E32), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.8),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: const [
                      GeminiSparkleIcon(size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Gemini Modelini Seç',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFF2A2A2E), height: 20),
                _buildModelOption(
                  modelId: 'gemini-2.5-flash',
                  title: 'Gemini 2.5 Flash',
                  subtitle:
                      'Hızlı, akıllı ve güçlü — günlük kullanım için ideal',
                  tag: 'Önerilen',
                  tagColor: GeminiColors.geminiCyan,
                  onTap: () {
                    setState(() {
                      _selectedModel = 'gemini-2.5-flash';
                      _selectedModelLabel = 'Gemini 2.5 Flash';
                    });
                    Navigator.pop(ctx);
                  },
                ),
                const SizedBox(height: 6),
                _buildModelOption(
                  modelId: 'gemini-3.1-flash-lite',
                  title: 'Gemini 3.1 Flash-Lite',
                  subtitle:
                      'Ultra hızlı ve hafif — basit sorular ve anlık yanıtlar',
                  tag: 'Ultra Hızlı',
                  tagColor: Colors.amberAccent,
                  onTap: () {
                    setState(() {
                      _selectedModel = 'gemini-3.1-flash-lite';
                      _selectedModelLabel = 'Gemini 3.1 Flash-Lite';
                    });
                    Navigator.pop(ctx);
                  },
                ),
                const SizedBox(height: 6),
                _buildModelOption(
                  modelId: 'gemini-3.6-flash',
                  title: 'Gemini 3.6 Flash',
                  subtitle:
                      'En gelişmiş ve derin akıl yürütme — karmaşık görevler için',
                  tag: 'Güçlü',
                  tagColor: GeminiColors.geminiPurple,
                  onTap: () {
                    setState(() {
                      _selectedModel = 'gemini-3.6-flash';
                      _selectedModelLabel = 'Gemini 3.6 Flash';
                    });
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModelOption({
    required String modelId,
    required String title,
    required String subtitle,
    required String tag,
    required Color tagColor,
    required VoidCallback onTap,
  }) {
    final isSelected = _selectedModel == modelId;

    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: isSelected ? const Color(0xFF282E3A) : Colors.transparent,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? GeminiColors.geminiBlue.withOpacity(0.25)
              : Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.auto_awesome,
          color: isSelected ? GeminiColors.geminiCyan : Colors.white60,
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: tagColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              tag,
              style: TextStyle(
                  color: tagColor, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: GeminiColors.textMuted, fontSize: 12),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle,
              color: GeminiColors.geminiCyan, size: 20)
          : null,
      onTap: onTap,
    );
  }

  /// Fotoğraftaki Birebir Orijinal Gemini "+" Menüsü (media_1788890062637.jpg)
  void _showGeminiToolsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1F20), // Orijinal koyu antrasit alt zemin
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üst Sürükleme / Çekme Çizgisi (Drag Handle)
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.24),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // 1. ÜST KISIM: Yatay Dairesel Hızlı Eylem Butonları (Fotoğraflar, Kamera, Dosyalar, Drive)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildRoundActionTile(
                      icon: Icons.add_photo_alternate_outlined,
                      label: 'Fotoğrafl...',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.gallery);
                      },
                    ),
                    const SizedBox(width: 14),
                    _buildRoundActionTile(
                      icon: Icons.camera_alt_outlined,
                      label: 'Kamera',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.camera);
                      },
                    ),
                    const SizedBox(width: 14),
                    _buildRoundActionTile(
                      icon: Icons.attach_file,
                      label: 'Dosyalar',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.gallery);
                      },
                    ),
                    const SizedBox(width: 14),
                    _buildRoundActionTile(
                      icon: Icons.add_to_drive_outlined,
                      label: 'Drive',
                      onTap: () {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Drive entegrasyonu: Galeri veya Dosyalar üzerinden seçebilirsiniz.'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),
              const Divider(color: Color(0xFF2C2D30), height: 1),
              const SizedBox(height: 6),

              // 2. ALT KISIM: Dikey Eylemler Listesi
              // Görüntü: "Oluşturun ve düzenleyin"
              _buildSheetActionItem(
                icon: Icons.palette_outlined,
                title: 'Görüntü',
                subtitle: 'Oluşturun ve düzenleyin',
                onTap: () {
                  Navigator.pop(ctx);
                  _textController.text =
                      'Bana modern ve sanatsal bir görüntü çiz/tasarla: ';
                  _textController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _textController.text.length),
                  );
                },
              ),

              // Videolar: "Fikirlerinizi hayata geçirin"
              _buildSheetActionItem(
                icon: Icons.movie_creation_outlined,
                title: 'Videolar',
                subtitle: 'Fikirlerinizi hayata geçirin',
                onTap: () {
                  Navigator.pop(ctx);
                  _textController.text =
                      'Bana çarpıcı bir video senaryosu ve sahne planı yaz: ';
                  _textController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _textController.text.length),
                  );
                },
              ),

              // Müzik: "Ses parçaları oluşturun" -> Müzik İndiriciye geçiş veya müzik istemi
              _buildSheetActionItem(
                icon: Icons.music_note_outlined,
                title: 'Müzik',
                subtitle: 'Ses parçaları oluşturun ve indirin',
                onTap: () {
                  Navigator.pop(ctx);
                  if (widget.onNavigateToMusicDownload != null) {
                    widget.onNavigateToMusicDownload!('');
                  } else {
                    _textController.text =
                        'Bana popüler müzikler öner veya indir: ';
                  }
                },
              ),

              // Canvas: "Kod yazın, metin oluşturun veya slayt hazırlayın."
              _buildSheetActionItem(
                icon: Icons.dashboard_customize_outlined,
                title: 'Canvas',
                subtitle: 'Kod yazın, metin oluşturun veya slayt hazırlayın.',
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _selectedMode =
                        _selectedMode == 'projects' ? 'general' : 'projects';
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_selectedMode == 'projects'
                          ? '🚀 Canvas & Proje Kodlama Modu Açıldı!'
                          : '💬 Genel Sohbet Moduna Geçildi.'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),

              // J.A.R.V.I.S. Siri Tarzı Sesli Asistan
              _buildSheetActionItem(
                icon: Icons.auto_awesome,
                title: 'J.A.R.V.I.S. Asistan',
                subtitle: 'Sesli konuşma, fener, pil ve telefon kontrolü',
                onTap: () {
                  Navigator.pop(ctx);
                  JarvisBrainService.instance.showOverlay();
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  /// Fotoğraftaki yatay yuvarlak buton (media_1788890062637.jpg üst sıra)
  Widget _buildRoundActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
              color:
                  Color(0xFF2B2C2E), // Orijinal fotoğraftaki buton dolgu rengi
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFFE3E3E3), size: 26),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 72,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE3E3E3),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Fotoğraftaki alt dikey menü satırı (Görüntü, Videolar, Müzik, Canvas)
  Widget _buildSheetActionItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
      leading: Icon(icon, color: const Color(0xFFE3E3E3), size: 24),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFF1F3F4),
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: Color(0xFF9AA0A6),
          fontSize: 13,
          fontWeight: FontWeight.normal,
        ),
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMessages = _messages.isNotEmpty;

    return Scaffold(
      backgroundColor: GeminiColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // 1. KATMAN: Mesajlar / İçerik
            Positioned.fill(
              child:
                  hasMessages ? _buildChatList() : _buildGeminiWelcomeScreen(),
            ),

            // 2. KATMAN: ÜST KARARTI / GÖLGE EFEKTİ
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 90,
              child: IgnorePointer(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF000000),
                        Color(0xD9000000),
                        Color(0x73000000),
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.45, 0.75, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // 3. KATMAN: ÜST BAR
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _buildPhotoTopBar(),
            ),

            // 4. KATMAN: ALT KARARTI / GÖLGE EFEKTİ
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 140,
              child: IgnorePointer(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Color(0xFF000000),
                        Color(0xD9000000),
                        Color(0x8C000000),
                        Color(0x33000000),
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.35, 0.65, 0.85, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // 5. & 6. KATMAN: MİNİ MÜZİK PLAYER VE COMPACT PILL BAR (Birlikte tek sütun)
            Positioned(
              left: 0,
              right: 0,
              bottom: 28, // Yazdığımız bar biraz daha yukarı alındı
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildMiniPlayer(),
                  ),
                  _buildExactPhotoPillBar(),
                ],
              ),
            ),

            // 7. KATMAN: FOTOĞRAFTAKİ BİREBİR "DÜZENLEMEYİ KAPAT" TAM EKRAN MODU
            if (_isEditingPrompt)
              Positioned.fill(
                child: _buildExactEditingOverlay(),
              ),
          ],
        ),
      ),
    );
  }

  /// Chat ekranında çalan şarkıyı gösteren mini player bar
  Widget _buildMiniPlayer() {
    return ListenableBuilder(
      listenable: GlobalAudioService.instance,
      builder: (context, _) {
        final svc = GlobalAudioService.instance;
        if (!svc.hasTrack) return const SizedBox.shrink();

        final isPlaying = svc.isPlaying;
        final isLoading = svc.isLoading;

        // EĞER OYNATICI GİZLENMİŞSE:
        // Tamamen gizle (üst bardaki beyaz müzik butonuna basılınca tekrar açılacak)
        if (svc.isHidden || svc.isMinimized) {
          return const SizedBox.shrink();
        }

        // TAM GENİŞLİKTEKİ MİNİ PLAYER KARTI (Yazdığımız barın hemen üstünde)
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1F23),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // TikTok Tarzı Kaydırılabilir Süre İlerleme Barı
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _TikTokStyleScrubBar(svc: svc),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      // Albüm kapağı
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: svc.currentCover != null
                            ? Image.network(
                                svc.currentCover!,
                                width: 42,
                                height: 42,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const _MusicIcon(),
                              )
                            : const _MusicIcon(),
                      ),
                      const SizedBox(width: 12),
                      // Şarkı bilgisi
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              svc.currentTitle ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (svc.currentArtist != null)
                              Text(
                                svc.currentArtist!,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      // Play / Pause butonu
                      GestureDetector(
                        onTap: isLoading ? null : () => svc.pauseOrResume(),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4285F4), Color(0xFF9B72CB)],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4285F4)
                                    .withValues(alpha: 0.4),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: isLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Oynatıcıyı Gizle / Küçült butonu
                      Tooltip(
                        message: 'Oynatıcıyı Gizle (Müzik çalmaya devam eder)',
                        child: GestureDetector(
                          onTap: () => svc.hidePlayer(),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Colors.white70,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Şarkıyı Kapat butonu
                      Tooltip(
                        message: 'Şarkıyı Kapat',
                        child: GestureDetector(
                          onTap: () => svc.stop(),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Fotoğraftaki Birebir Orijinal Gemini Düzenleme Sekmesi (media_1788799295971.jpg)
  Widget _buildExactEditingOverlay() {
    return Container(
      color: const Color(0xFF141517), // Fotoğraftaki saf antrasit-siyah zemin
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst Ortadaki "✕ Düzenlemeyi kapat" Oval Hap Butonu
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                setState(() {
                  _isEditingPrompt = false;
                  _editingMessage = null;
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(
                      0xFFE8EAED), // Fotoğraftaki açık beyaz-gri hap
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.close, color: Colors.black87, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Düzenlemeyi kapat',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Fotoğraftaki Düzenleme Metin Alanı (Geniş, temiz, kenarlıksız beyaz yazı)
          Expanded(
            child: TextField(
              controller: _editingController,
              autofocus: true,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(
                color: Color(0xFFF1F3F4), // Fotoğraftaki net beyaz metin
                fontSize: 18,
                height: 1.45,
                fontWeight: FontWeight.normal,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Mesajınızı düzenleyin...',
                hintStyle: TextStyle(color: Color(0xFF8E918F)),
              ),
            ),
          ),

          // Alt Araç Çubuğu (Sol alt "+" ikonu ve Sağ alt Mavi Gönder Dairesi)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.add,
                      color: _selectedMode == 'projects'
                          ? GeminiColors.geminiPurple
                          : const Color(0xFF8E918F),
                      size: 28,
                    ),
                    tooltip: 'Ekle & Araçlar',
                    onPressed: _showGeminiToolsSheet,
                  ),
                  if (_selectedMode == 'projects')
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _showGeminiToolsSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: GeminiColors.geminiPurple.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: GeminiColors.geminiPurple.withOpacity(0.5),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.lightbulb_outline,
                              size: 13,
                              color: GeminiColors.geminiPurple,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Proje Modu',
                              style: TextStyle(
                                color: GeminiColors.geminiPurple,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: _isListening
                          ? const EdgeInsets.all(4)
                          : EdgeInsets.zero,
                      decoration: _isListening
                          ? BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.25),
                              shape: BoxShape.circle,
                            )
                          : null,
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none_outlined,
                        color: _isListening
                            ? Colors.redAccent
                            : const Color(0xFF8E918F),
                        size: 26,
                      ),
                    ),
                    tooltip: _isListening
                        ? 'Dinlemeyi durdur'
                        : 'Sesle yaz (Türkçe)',
                    onPressed: () => _toggleSpeechRecognition(forEditing: true),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: const Color(
                        0xFF2A5BB5), // Fotoğraftaki canlı mavi gönder butonu
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _submitEditedPrompt,
                      child: Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        child: const Icon(Icons.arrow_upward,
                            color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: Colors.transparent,
      child: Row(
        children: [
          // 1. Sol Menü Butonu (Drawer / Sidebar Açıcı)
          if (widget.onOpenSidebar != null) ...[
            _buildBlackCircularButton(
              icon: Icons.menu,
              tooltip: 'Menü',
              onPressed: widget.onOpenSidebar!,
            ),
            const SizedBox(width: 6),
          ],

          // 2. Model Seçici Dropdown (Dar ekranlarda taşma yapmaz, esnek küçülür)
          Flexible(
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _showModelPickerMenu,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.08), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _selectedModelLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF1F3F4),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        color: Color(0xFFF1F3F4),
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // 3. Sağ Butonlar Grubu (Hiçbir koşulda ekran dışına taşmaz)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Müzik çalıyorsa Üst Barda Oynatıcıyı Gizle / Aç Butonu
              ListenableBuilder(
                listenable: GlobalAudioService.instance,
                builder: (context, _) {
                  final svc = GlobalAudioService.instance;
                  if (!svc.hasTrack) return const SizedBox.shrink();
                  final isHidden = svc.isHidden || svc.isMinimized;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _buildBlackCircularButton(
                      icon: isHidden
                          ? Icons.music_note_rounded
                          : Icons.music_off_rounded,
                      tooltip: isHidden
                          ? 'Müzik Oynatıcısını Aç'
                          : 'Müzik Oynatıcısını Gizle',
                      iconColor: isHidden
                          ? GeminiColors.geminiCyan
                          : const Color(0xFFE3E3E3),
                      onPressed: () {
                        if (isHidden) {
                          svc.showPlayer();
                        } else {
                          svc.hidePlayer();
                        }
                      },
                    ),
                  );
                },
              ),

              // Yeni Sohbet Butonu
              _buildBlackCircularButton(
                icon: Icons.edit_outlined,
                tooltip: 'Yeni Sohbet',
                onPressed: _resetChat,
              ),

              const SizedBox(width: 6),

              // Araçlar / Menü Butonu
              _buildBlackCircularButton(
                icon: Icons.more_horiz,
                tooltip: 'Araçlar / Menü',
                onPressed: _showGeminiToolsSheet,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBlackCircularButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? iconColor,
    double size = 38,
    double iconSize = 20,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 0.8,
        ),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: size, height: size),
        visualDensity: VisualDensity.compact,
        icon: Icon(icon,
            color: iconColor ?? const Color(0xFFE3E3E3), size: iconSize),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildGeminiWelcomeScreen() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ShaderMask(
                shaderCallback: (bounds) =>
                    GeminiColors.welcomeGradient.createShader(bounds),
                child: const Text(
                  'Merhaba, Dostum',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bugün size nasıl yardımcı olabilirim?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF444746),
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(left: 16, right: 16, top: 75, bottom: 160),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isLoading) {
          return _buildGeminiThinking();
        }
        final msg = _messages[index];
        return _buildMessageItem(msg);
      },
    );
  }

  Widget _buildGeminiThinking() {
    final hasSearchingSources =
        _activeSearchingSources != null && _activeSearchingSources!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const GeminiSparkleIcon(size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Gemini',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: GeminiColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 12,
                      height: 12,
                      padding: const EdgeInsets.all(2),
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: GeminiColors.geminiBlue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (hasSearchingSources) ...[
                  // Google AI Tarayıcı Modu: Kaynak Logoları ve İsimleri
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: _activeSearchingSources!.map((src) {
                        final title = src['title'] ?? '';
                        final url = src['url'] ?? '';
                        final domain = _extractDomain(url);
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1F20),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF333538),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildFavicon(domain, 14),
                              const SizedBox(width: 6),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 130),
                                child: Text(
                                  title.isNotEmpty ? title : domain,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFE3E3E3),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ] else ...[
                  const Text(
                    'Yanıt hazırlanıyor...',
                    style: TextStyle(
                      color: GeminiColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(ChatMessage msg) {
    if (msg.isUser) {
      // Kullanıcı mesajı: Gri tonlu şık oval baloncuk + Basılı tutunca menü
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 16, left: 50),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onLongPress: () => _showUserMessageOptions(msg),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF282A2C), // Orijinal Gemini gri tonu
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.06),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (msg.imageBytes != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 220,
                            maxWidth: 260,
                          ),
                          child: Image.memory(
                            msg.imageBytes!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      if (msg.content.isNotEmpty) const SizedBox(height: 10),
                    ],
                    if (msg.content.isNotEmpty)
                      Text(
                        msg.content,
                        style: const TextStyle(
                          color: Color(0xFFF0F0F0),
                          fontSize: 15.5,
                          height: 1.45,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: GeminiSparkleIcon(size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (msg.usedModel != null || msg.isWebSearch)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          if (msg.usedModel != null)
                            Text(
                              msg.usedModel!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: GeminiColors.textMuted,
                              ),
                            ),
                          if (msg.isWebSearch) ...[
                            if (msg.usedModel != null) const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    GeminiColors.geminiBlue.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color:
                                      GeminiColors.geminiBlue.withOpacity(0.4),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.language_rounded,
                                    size: 11,
                                    color: GeminiColors.geminiBlue,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    msg.searchQuery != null &&
                                            msg.searchQuery!.isNotEmpty
                                        ? 'Web: ${msg.searchQuery}'
                                        : 'Web Araması',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: GeminiColors.geminiBlue,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (msg.sources != null && msg.sources!.isNotEmpty)
                    _ExpandableSourcesWidget(
                      sources: msg.sources!,
                      buildFavicon: _buildFavicon,
                      extractDomain: _extractDomain,
                    ),
                  MarkdownBody(
                    data: msg.content,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(
                        color: Color(0xFFE8EAED),
                        fontSize: 16,
                        height: 1.6,
                      ),
                      h1: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.5,
                      ),
                      h2: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.4,
                      ),
                      h3: const TextStyle(
                        color: GeminiColors.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      code: const TextStyle(
                        backgroundColor: Color(0xFF1E1F20),
                        color: GeminiColors.geminiCyan,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      listBullet:
                          const TextStyle(color: GeminiColors.geminiBlue),
                    ),
                  ),
                  if (msg.isMusicCommand &&
                      widget.onNavigateToMusicDownload != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: GeminiColors.geminiBlue.withOpacity(0.4),
                            width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.music_note,
                              color: GeminiColors.geminiCyan, size: 28),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  '320kbps MP3 İndiriciye Aktar',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Şarkıyı hemen arayıp cihazına indirebilirsin',
                                  style: TextStyle(
                                    color: GeminiColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.styleFrom(
                            backgroundColor: GeminiColors.geminiBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ).let(
                            (style) => ElevatedButton.icon(
                              style: style,
                              icon: const Icon(Icons.download, size: 16),
                              label: const Text('İndir'),
                              onPressed: () {
                                final songName = _extractSongQuery(msg.content);
                                widget.onNavigateToMusicDownload!(songName);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy,
                            size: 16, color: GeminiColors.textMuted),
                        tooltip: 'Metni Kopyala',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: msg.content));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Metin panoya kopyalandı!'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                      // Sesli Dinle (Erkek Jarvis Sesi)
                      ValueListenableBuilder<bool>(
                        valueListenable:
                            JarvisTtsService.instance.isSpeakingNotifier,
                        builder: (context, isSpeaking, _) {
                          final isThisMsg = JarvisTtsService.instance
                              .isSpeakingSpecificText(msg.content);
                          return IconButton(
                            icon: Icon(
                              isThisMsg
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_up_outlined,
                              size: 17,
                              color: isThisMsg
                                  ? const Color(0xFF00F2FE)
                                  : GeminiColors.textMuted,
                            ),
                            tooltip: isThisMsg
                                ? 'Seslendirmeyi Durdur'
                                : 'Sesli Dinle (Jarvis Erkek Sesi)',
                            onPressed: () => JarvisTtsService.instance
                                .toggleSpeak(msg.content),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.thumb_up_alt_outlined,
                            size: 16, color: GeminiColors.textMuted),
                        tooltip: 'İyi Yanıt',
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.thumb_down_alt_outlined,
                            size: 16, color: GeminiColors.textMuted),
                        tooltip: 'Kötü Yanıt',
                        onPressed: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildExactPhotoPillBar() {
    final isProjects = _selectedMode == 'projects';
    final hasImage = _selectedImageBytes != null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Seçili Görsel Önizleme Kutucuğu (Silme '✕' butonu ile)
            if (hasImage)
              Container(
                margin: const EdgeInsets.only(left: 20, bottom: 8),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1F20),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.12), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _selectedImageBytes!,
                        width: 68,
                        height: 68,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: InkWell(
                        onTap: _clearSelectedImage,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.black87,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              constraints: const BoxConstraints(
                minHeight: 56,
                maxHeight: 180,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1F20),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 16,
                    spreadRadius: 1,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _showGeminiToolsSheet,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Icon(
                            Icons.add,
                            color: isProjects
                                ? GeminiColors.geminiPurple
                                : const Color(0xFFE3E3E3),
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_selectedMode == 'projects') ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _showGeminiToolsSheet,
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: GeminiColors.geminiPurple.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: GeminiColors.geminiPurple.withOpacity(0.5),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.lightbulb_outline,
                                size: 13,
                                color: GeminiColors.geminiPurple,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Proje',
                                style: TextStyle(
                                  color: GeminiColors.geminiPurple,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ] else
                    const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: TextField(
                        controller: _textController,
                        keyboardType: TextInputType.multiline,
                        minLines: 1,
                        maxLines: 5,
                        style: const TextStyle(
                          color: Color(0xFFE3E3E3),
                          fontSize: 16,
                          height: 1.4,
                          fontWeight: FontWeight.normal,
                        ),
                        decoration: InputDecoration(
                          hintText: _isListening
                              ? "Dinleniyor... Konuşabilirsiniz"
                              : (hasImage
                                  ? "Fotoğraf hakkında soru sor..."
                                  : (isProjects
                                      ? "Proje sor..."
                                      : "Gemini'a sor...")),
                          hintStyle: TextStyle(
                            color: _isListening
                                ? Colors.redAccent.withOpacity(0.9)
                                : const Color(0xFF8E918F),
                            fontSize: 15,
                            fontWeight: _isListening
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: IconButton(
                      icon: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: _isListening
                            ? const EdgeInsets.all(4)
                            : EdgeInsets.zero,
                        decoration: _isListening
                            ? BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.25),
                                shape: BoxShape.circle,
                              )
                            : null,
                        child: Icon(
                          _isListening ? Icons.mic : Icons.mic_none_outlined,
                          color: _isListening
                              ? Colors.redAccent
                              : const Color(0xFFE3E3E3),
                          size: 22,
                        ),
                      ),
                      tooltip: _isListening
                          ? 'Dinlemeyi durdur'
                          : 'Sesle yaz (Türkçe)',
                      onPressed: () =>
                          _toggleSpeechRecognition(forEditing: false),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: const Color(0xFF1F3B73),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _handleSendMessage(),
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          child: (_textController.text.trim().isNotEmpty ||
                                  hasImage)
                              ? const Icon(Icons.arrow_upward,
                                  color: Colors.white, size: 20)
                              : const Icon(Icons.graphic_eq,
                                  color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension LetExtension<T> on T {
  R let<R>(R Function(T it) block) => block(this);
}

/// Mini player için albüm kapağı placeholder
class _MusicIcon extends StatelessWidget {
  const _MusicIcon();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2B30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.music_note_rounded,
          color: Color(0xFF4285F4), size: 22),
    );
  }
}

/// TikTok tarzı sürükleyerek ileri/geri alma çubuğu
class _TikTokStyleScrubBar extends StatefulWidget {
  final GlobalAudioService svc;
  const _TikTokStyleScrubBar({required this.svc});

  @override
  State<_TikTokStyleScrubBar> createState() => _TikTokStyleScrubBarState();
}

class _TikTokStyleScrubBarState extends State<_TikTokStyleScrubBar> {
  double? _dragRatio;
  bool _isDragging = false;

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _handleSeek(double localDx, double maxWidth) {
    if (maxWidth <= 0 || widget.svc.duration.inSeconds <= 0) return;
    final ratio = (localDx / maxWidth).clamp(0.0, 1.0);
    final targetSeconds = (ratio * widget.svc.duration.inSeconds).round();
    widget.svc.seek(Duration(seconds: targetSeconds));
  }

  @override
  Widget build(BuildContext context) {
    final svc = widget.svc;
    final totalSec = svc.duration.inSeconds;
    final currentProgress = (totalSec > 0)
        ? (svc.position.inSeconds / totalSec).clamp(0.0, 1.0)
        : 0.0;
    final displayRatio = _dragRatio ?? currentProgress;
    final currentScrubDuration = Duration(
      seconds: (displayRatio * totalSec).round(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final ratio = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
            setState(() => _dragRatio = ratio);
            _handleSeek(details.localPosition.dx, barWidth);
            Future.delayed(const Duration(milliseconds: 250), () {
              if (mounted) setState(() => _dragRatio = null);
            });
          },
          onHorizontalDragStart: (details) {
            setState(() {
              _isDragging = true;
              _dragRatio =
                  (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
            });
          },
          onHorizontalDragUpdate: (details) {
            setState(() {
              _dragRatio =
                  (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
            });
          },
          onHorizontalDragEnd: (details) {
            if (_dragRatio != null) {
              _handleSeek(_dragRatio! * barWidth, barWidth);
            }
            setState(() {
              _isDragging = false;
              _dragRatio = null;
            });
          },
          child: Container(
            height: _isDragging ? 26 : 14,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Arka plan çizgisi
                Container(
                  height: _isDragging ? 6 : 3.5,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                // Dolu olan ilerleme kısmı (TikTok mavi/mor degrade)
                FractionallySizedBox(
                  widthFactor: displayRatio,
                  child: Container(
                    height: _isDragging ? 6 : 3.5,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4285F4), Color(0xFF9B72CB)],
                      ),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        if (_isDragging)
                          BoxShadow(
                            color:
                                const Color(0xFF4285F4).withValues(alpha: 0.8),
                            blurRadius: 8,
                          ),
                      ],
                    ),
                  ),
                ),
                // TikTok tarzı sürükleme yuvarlağı (Thumb)
                if (_isDragging || displayRatio > 0)
                  Positioned(
                    left:
                        (displayRatio * (barWidth - 8)) - (_isDragging ? 7 : 4),
                    top: _isDragging ? -5 : -2.5,
                    child: Container(
                      width: _isDragging ? 16 : 8.5,
                      height: _isDragging ? 16 : 8.5,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 5,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                // TikTok tarzı kaydırırken üstte beliren canlı süre balonu
                if (_isDragging && totalSec > 0)
                  Positioned(
                    left: ((displayRatio * barWidth) - 48)
                        .clamp(0.0, barWidth - 96),
                    top: -28,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16171A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF4285F4).withValues(alpha: 0.6),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.8),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Text(
                        '${_formatDuration(currentScrubDuration)} / ${_formatDuration(svc.duration)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Kaynaklar yazısına basılınca açılıp kapanabilen (Accordion) kaynak listesi
class _ExpandableSourcesWidget extends StatefulWidget {
  final List<Map<String, String>> sources;
  final Widget Function(String domain, double size) buildFavicon;
  final String Function(String url) extractDomain;

  const _ExpandableSourcesWidget({
    required this.sources,
    required this.buildFavicon,
    required this.extractDomain,
  });

  @override
  State<_ExpandableSourcesWidget> createState() =>
      _ExpandableSourcesWidgetState();
}

class _ExpandableSourcesWidgetState extends State<_ExpandableSourcesWidget> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tıklanabilir ve açılıp kapanabilir "KAYNAKLAR" başlığı
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'KAYNAKLAR',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: GeminiColors.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 15,
                    color: GeminiColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2B30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${widget.sources.length}',
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: GeminiColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: widget.sources.map((src) {
                  final title = src['title'] ?? '';
                  final url = src['url'] ?? '';
                  final domain = widget.extractDomain(url);
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    constraints: const BoxConstraints(maxWidth: 160),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1F20),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF333538),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        widget.buildFavicon(domain, 14),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title.isNotEmpty ? title : domain,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFE3E3E3),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                domain,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  color: GeminiColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
