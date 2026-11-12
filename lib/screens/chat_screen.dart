import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat_message.dart';
import '../services/gemini_service.dart';
import '../services/global_audio_service.dart';
import '../services/image_discovery_service.dart';
import '../services/image_intent.dart';
import '../services/markdown_media.dart';
import '../services/ui_image_enricher.dart';
import '../services/music_catalog_service.dart';
import '../services/web_search_service.dart';
import '../services/speech/speech_service.dart';
import '../services/chat_history_service.dart';
import '../theme/gemini_colors.dart';
import '../theme/chat_ui.dart';
import '../widgets/chat/chat_activity.dart';
import '../widgets/chat/chat_actions.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/gemini_sparkle.dart';
import '../services/jarvis_brain_service.dart';
import '../services/jarvis_tts_service.dart';
import '../widgets/generative_ui/generative_message_view.dart';

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
  final UiImageEnricher _imageEnricher = UiImageEnricher();

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

  /// Yanıttaki UI bloklarını gerçek veriyle doldurur:
  ///
  /// * `album` / `tracklist` / `artist` → katalogdan kapak, süre, parça kapağı
  /// * `card_grid` / `card` / `info_card` / `product_card` / `gallery` → gerçek
  ///   görsel (oyun/dizi karakterleri, kişiler, ürünler…)
  Future<String> _enrichUiBlocks(String content) async {
    final blockRegex = RegExp(
      r'```\s*(?:ui|json:ui|generative_ui)\s*\n([\s\S]*?)```',
      caseSensitive: false,
    );
    final matches = blockRegex.allMatches(content).toList();
    if (matches.isEmpty) return content;

    var result = content;
    // Sondan başa: konumlar bozulmasın.
    for (final match in matches.reversed) {
      Map<String, dynamic>? data;
      try {
        final decoded = jsonDecode(match.group(1) ?? '');
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } catch (_) {
        continue;
      }
      if (data == null) continue;

      final type = (data['type'] ?? '').toString().toLowerCase();
      Map<String, dynamic>? enriched;
      try {
        if (type == 'album' || type == 'tracklist' || type == 'playlist') {
          enriched = await _fillMusicData(data, albumLevel: type == 'album');
        } else if (type == 'artist') {
          enriched = await _fillArtistImage(data);
        } else {
          enriched = await _imageEnricher.fillImages(data);
        }
      } catch (e) {
        debugPrint('Müzik bloğu zenginleştirilemedi: $e');
      }
      if (enriched == null) continue;

      final replacement =
          '```ui\n${const JsonEncoder.withIndent('  ').convert(enriched)}\n```';
      result = result.replaceRange(match.start, match.end, replacement);
    }
    return result;
  }

  Future<Map<String, dynamic>?> _fillMusicData(
    Map<String, dynamic> data, {
    required bool albumLevel,
  }) async {
    final albumTitle =
        (data['album'] ?? data['album_title'] ?? (albumLevel ? data['title'] : null))
            ?.toString()
            .trim();
    final artist = (data['artist'] ?? data['subtitle'] ?? data['sanatci'])
        ?.toString()
        .trim();

    final rawTracks = data['tracks'] ?? data['songs'];
    final tracks = rawTracks is List ? rawTracks : const <dynamic>[];

    CatalogAlbum? album;
    if (albumTitle != null && albumTitle.isNotEmpty) {
      album = await MusicCatalogService.instance
          .findAlbum(albumTitle, artist: artist);
    }
    // Albüm adı yoksa ilk parçadan albümü tahmin et.
    if (album == null && tracks.isNotEmpty) {
      final firstTitle = _trackTitle(tracks.first);
      if (firstTitle != null) {
        album = await MusicCatalogService.instance
            .findAlbum(firstTitle, artist: artist);
      }
    }
    if (album == null) return null;

    var changed = false;
    final cover = (data['cover'] ?? data['cover_url'] ?? data['image_url'])
        ?.toString()
        .trim();
    if ((cover == null || cover.isEmpty) && album.coverUrl != null) {
      data['cover'] = album.coverUrl;
      changed = true;
    }
    if ((data['year'] == null || data['year'].toString().trim().isEmpty) &&
        album.year != null) {
      data['year'] = album.year;
      changed = true;
    }

    if (tracks.isEmpty) {
      if (album.tracks.isNotEmpty) {
        data['tracks'] = album.tracks.map((track) => track.toJson()).toList();
        changed = true;
      }
    } else {
      final filled = <Map<String, dynamic>>[];
      for (final track in tracks) {
        var map = _asTrackMap(track);
        if (map == null) {
          filled.add({'title': track.toString()});
          continue;
        }
        final title = _trackTitle(map);
        if (title != null) {
          final match = _matchTrack(album.tracks, title);
          final artwork = (map['artwork'] ?? map['cover'] ?? map['image_url'])
              ?.toString()
              .trim();
          if (artwork == null || artwork.isEmpty) {
            final artworkUrl = match?.artworkUrl ?? album.coverUrl;
            if (artworkUrl != null) {
              map['artwork'] = artworkUrl;
              changed = true;
            }
          }
          final duration = (map['duration'] ?? map['length'])?.toString().trim();
          if ((duration == null || duration.isEmpty) &&
              match?.durationLabel != null) {
            map['duration'] = match!.durationLabel;
            changed = true;
          }
        }
        filled.add(map);
      }
      // Albümde eşleşmeyen parçalar (çalma listesi/farklı sanatçılar) için tek
      // tek şarkı araması yap — her satır kendi kapağını alsın.
      final missing = <int>[];
      for (var i = 0; i < filled.length; i++) {
        final artwork =
            (filled[i]['artwork'] ?? '').toString().trim();
        if (artwork.isEmpty) missing.add(i);
      }
      if (missing.isNotEmpty) {
        final lookups = missing.take(4).toList();
        final results = await Future.wait(
          lookups.map((index) {
            final map = filled[index];
            final title = _trackTitle(map);
            if (title == null) return Future<CatalogTrack?>.value(null);
            return MusicCatalogService.instance.findTrack(
              title,
              artist: (map['artist'] ?? artist)?.toString(),
            );
          }),
        );
        for (var i = 0; i < lookups.length; i++) {
          final track = results[i];
          if (track?.artworkUrl == null) continue;
          filled[lookups[i]]['artwork'] = track!.artworkUrl;
          if ((filled[lookups[i]]['duration'] ?? '').toString().trim().isEmpty &&
              track.durationLabel != null) {
            filled[lookups[i]]['duration'] = track.durationLabel;
          }
          changed = true;
        }
      }

      if (changed) data['tracks'] = filled;
    }

    return changed ? data : null;
  }

  /// Sanatçı kartına gerçek fotoğraf ekler (Wikipedia/Apple Music).
  Future<Map<String, dynamic>?> _fillArtistImage(
      Map<String, dynamic> data) async {
    final current = (data['image_url'] ?? data['image'] ?? data['avatar'])
        ?.toString()
        .trim();
    if (current != null && current.isNotEmpty) return null;

    final name = (data['name'] ?? data['title'])?.toString().trim();
    if (name == null || name.isEmpty) return null;

    final images = await ImageDiscoveryService.instance
        .discover(name, limit: 3, musicFirst: true);
    if (images.isEmpty) return null;
    data['image_url'] = images.first.url;
    return data;
  }

  Map<String, dynamic>? _asTrackMap(dynamic raw) {
    if (raw is String) return {'title': raw};
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  String? _trackTitle(dynamic raw) {
    if (raw is String) return raw.trim().isEmpty ? null : raw.trim();
    if (raw is Map) {
      final value =
          (raw['title'] ?? raw['name'] ?? raw['track'])?.toString().trim();
      return (value == null || value.isEmpty) ? null : value;
    }
    return null;
  }

  CatalogTrack? _matchTrack(List<CatalogTrack> tracks, String title) {
    final wanted = _normalizeForMatch(title);
    if (wanted.isEmpty) return null;
    for (final track in tracks) {
      if (_normalizeForMatch(track.title) == wanted) return track;
    }
    for (final track in tracks) {
      final candidate = _normalizeForMatch(track.title);
      if (candidate.contains(wanted) || wanted.contains(candidate)) return track;
    }
    return null;
  }

  String _normalizeForMatch(String value) {
    const map = {
      'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u',
    };
    var out = value.toLowerCase();
    map.forEach((key, replacement) => out = out.replaceAll(key, replacement));
    return out
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String? _automaticWebQuery(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.length < 4 || _checkExplicitSearch(text) != null) return null;
    final needsFreshOrFactualAnswer = RegExp(
      r'\b(kimdir|kimdi|nedir|nerede|ne zaman|nasıl|neden|kaç|hangi|güncel|son|bugün|yarın|haber|fiyat|maç|hava durumu|özellikleri|hakkında)\b',
      caseSensitive: false,
    ).hasMatch(lower);
    return needsFreshOrFactualAnswer ? text : null;
  }

  Future<void> _sendToGemini(
    String promptText, {
    Uint8List? imageBytes,
    String? mimeType,
  }) async {
    final isMusic = _isMusicCommand(promptText);
    final stopwatch = Stopwatch()..start();
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
      final automaticQuery = _automaticWebQuery(promptText);
      final initialSearchQuery = explicitQuery ?? automaticQuery;
      if (initialSearchQuery != null && initialSearchQuery.isNotEmpty) {
        wasWebSearch = true;
        executedSearchQuery = initialSearchQuery;
        final results = await WebSearchService.instance
            .search(initialSearchQuery, limit: 5, includeDetail: false);
        if (results.isNotEmpty) {
          collectedSources =
              results.map((r) => {'title': r.title, 'url': r.url}).toList();
        }
        if (mounted) {
          setState(() {
            _activeSearchingSources = collectedSources;
          });
        }
        final webContext = WebSearchService.instance
            .formatForPrompt(results, initialSearchQuery);
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

      // 3. MÜZİK KARTLARI: albüm kapağı + her parçanın kendi kapağı/süresi.
      // Model kapak uydurmak zorunda kalmıyor; katalogdan gerçeği yazıyoruz.
      try {
        cleanContent = await _enrichUiBlocks(cleanContent);
      } catch (e) {
        debugPrint('Kart zenginleştirme hatası: $e');
      }

      // 4. GÖRSEL İSTEĞİ: "görsellerini göster / fotoğrafları / kapak" vb.
      final imageQuery =
          imageIntentQuery(promptText, content: cleanContent);
      if (imageQuery != null && imageQuery.isNotEmpty) {
        try {
          final images = await ImageDiscoveryService.instance.discover(
            imageQuery,
            limit: 6,
            musicFirst: looksMusical(promptText) || looksMusical(cleanContent),
          );
          cleanContent = insertImagesIntoMarkdown(
            cleanContent,
            images.map((image) => image.url).toList(),
          );
          if (images.isNotEmpty) {
            collectedSources ??= <Map<String, String>>[];
            final known = collectedSources
                .map((source) => source['url'])
                .whereType<String>()
                .toSet();
            for (final image in images.take(4)) {
              final page = image.sourceUrl;
              if (page == null ||
                  page.isEmpty ||
                  image.source.isEmpty ||
                  known.contains(page)) {
                continue;
              }
              known.add(page);
              collectedSources.add({
                'title': '${image.source} · ${image.title ?? imageQuery}',
                'url': page,
              });
            }
          }
        } catch (e) {
          // Metin yanıtı, görsel sağlayıcısı hata verdiğinde kaybolmaz.
          debugPrint('Görsel arama hatası: $e');
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
        thinkingMs: stopwatch.elapsedMilliseconds,
        activitySteps: [
          'İçerik değerlendiriliyor',
          if (wasWebSearch) 'Web sonuçları karşılaştırılıyor',
          'Yanıt yazılıyor',
        ],
      );
      stopwatch.stop();

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
              const SizedBox(height: 32),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  _buildPromptChip(
                    icon: Icons.account_balance_rounded,
                    label: 'Modern Banka Uygulaması Tasarla',
                    prompt: 'Modern bir banka uygulaması tasarla.',
                  ),
                  _buildPromptChip(
                    icon: Icons.dashboard_rounded,
                    label: 'Fintech Dashboard ve Grafik',
                    prompt:
                        'Haftalık finans ve harcama analizi içeren bir dashboard hazırla.',
                  ),
                  _buildPromptChip(
                    icon: Icons.compare_arrows_rounded,
                    label: 'Tasarım Alternatifi Karşılaştır',
                    prompt:
                        'Modern banka uygulaması için iki farklı tasarım alternatifini karşılaştır.',
                  ),
                  _buildPromptChip(
                    icon: Icons.dynamic_form_rounded,
                    label: 'Geri Bildirim Formu',
                    prompt:
                        'Banka uygulaması için etkileşimli bir geri bildirim formu hazırla.',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromptChip({
    required IconData icon,
    required String label,
    required String prompt,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _handleSendMessage(prompt),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1F20),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: GeminiColors.geminiCyan),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFE3E3E3),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
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
    final domains = <String>{};
    for (final src in _activeSearchingSources ?? const <Map<String, String>>[]) {
      final domain = _extractDomain(src['url'] ?? '');
      if (domain.isNotEmpty && domain != 'web') domains.add(domain);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: GeminiSparkleIcon(size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ChatThinkingRow(
              label: domains.isEmpty ? 'Düşünüyor' : 'Web siteleri aranıyor',
              scanningDomains: domains.take(6).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// Kullanıcı mesajı — ChatGPT tarzı sade, yumuşak köşeli baloncuk.
  Widget _buildUserMessage(ChatMessage msg) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 18, left: 44),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(ChatUi.bubbleRadius),
            onLongPress: () => _showUserMessageOptions(msg),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: BoxDecoration(
                color: ChatUi.userBubble,
                borderRadius: BorderRadius.circular(ChatUi.bubbleRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (msg.imageBytes != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 240,
                          maxWidth: 280,
                        ),
                        child: Image.memory(msg.imageBytes!, fit: BoxFit.cover),
                      ),
                    ),
                    if (msg.content.isNotEmpty) const SizedBox(height: 10),
                  ],
                  if (msg.content.isNotEmpty)
                    Text(
                      msg.content,
                      style: const TextStyle(
                        color: ChatUi.textPrimary,
                        fontSize: 15.5,
                        height: 1.5,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Asistan mesajı — aktivite satırı + markdown + kaynaklar + aksiyonlar.
  Widget _buildAssistantMessage(ChatMessage msg) {
    final thinking = msg.thinkingMs != null
        ? Duration(milliseconds: msg.thinkingMs!)
        : null;
    final sourceCount = msg.sources?.length ?? 0;
    final hasActivity = thinking != null || sourceCount > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: GeminiSparkleIcon(size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasActivity)
                  ChatActivityRow(
                    thinking: thinking,
                    sourceCount: sourceCount,
                    searchQuery: msg.searchQuery,
                    extraSteps: msg.activitySteps ?? const [],
                    sources: msg.sources ?? const [],
                  ),
                GenerativeMessageView(
                  content: msg.content,
                  onActionPrompt: (prompt) => _handleSendMessage(prompt),
                  onActionUrl: (url) async {
                    final uri = Uri.tryParse(url);
                    if (uri != null) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  onFormSubmit: (data, promptText) =>
                      _handleSendMessage(promptText),
                ),
                if (msg.isMusicCommand &&
                    widget.onNavigateToMusicDownload != null) ...[
                  const SizedBox(height: 14),
                  _buildMusicTransferCard(msg),
                ],
                const SizedBox(height: 4),
                ValueListenableBuilder<bool>(
                  valueListenable: JarvisTtsService.instance.isSpeakingNotifier,
                  builder: (context, _, __) {
                    final isSpeaking = JarvisTtsService.instance
                        .isSpeakingSpecificText(msg.content);
                    return ChatMessageActions(
                      rawText: msg.content,
                      isSpeaking: isSpeaking,
                      onSpeak: () =>
                          JarvisTtsService.instance.toggleSpeak(msg.content),
                      onRegenerate: () => _regenerateMessage(msg),
                    );
                  },
                ),
                if (msg.usedModel != null && msg.usedModel!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      msg.usedModel!,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: ChatUi.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Müzik komutlarında gösterilen "indiriciye aktar" kartı.
  Widget _buildMusicTransferCard(ChatMessage msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ChatUi.cardDecoration(
        borderColor: ChatUi.accent.withValues(alpha: 0.35),
      ),
      child: Row(
        children: [
          const Icon(Icons.music_note_rounded, color: ChatUi.accent, size: 26),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '320kbps MP3 indiriciye aktar',
                  style: TextStyle(
                    color: ChatUi.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Şarkıyı hemen arayıp cihazına indirebilirsin',
                  style: TextStyle(color: ChatUi.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ChatUi.accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              final songName = _extractSongQuery(msg.content);
              widget.onNavigateToMusicDownload!(songName);
            },
            child: const Text(
              'İndir',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// Bir asistan yanıtını yeniden üretir: kendisinden sonraki mesajları siler
  /// ve son kullanıcı isteğini tekrar gönderir.
  void _regenerateMessage(ChatMessage msg) {
    if (_isLoading) return;
    final idx = _messages.indexWhere((m) => m.id == msg.id);
    if (idx < 0) return;

    var userIdx = idx - 1;
    while (userIdx >= 0 && !_messages[userIdx].isUser) {
      userIdx--;
    }
    if (userIdx < 0) return;

    final userMsg = _messages[userIdx];
    setState(() {
      _messages.removeRange(userIdx + 1, _messages.length);
      _isLoading = true;
    });
    _scrollToBottom();
    _sendToGemini(
      userMsg.content,
      imageBytes: userMsg.imageBytes,
      mimeType: userMsg.imageMimeType,
    );
  }

  Widget _buildMessageItem(ChatMessage msg) {
    return msg.isUser ? _buildUserMessage(msg) : _buildAssistantMessage(msg);
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
