import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import 'gemini_service.dart';
import 'global_audio_service.dart';
import 'jarvis_tts_service.dart';
import 'phone_control_service.dart';
import 'voice_command_parser.dart';

enum JarvisStatus {
  idle,
  listening,
  thinking,
  speaking,
}

class JarvisBrainService {
  static final JarvisBrainService instance = JarvisBrainService._internal();
  JarvisBrainService._internal();

  final GeminiService _geminiService = GeminiService();
  final PhoneControlService _phoneControl = PhoneControlService.instance;
  final JarvisTtsService _tts = JarvisTtsService.instance;

  final ValueNotifier<JarvisStatus> statusNotifier = ValueNotifier<JarvisStatus>(JarvisStatus.idle);
  final ValueNotifier<String> userSpeechNotifier = ValueNotifier<String>('');
  final ValueNotifier<String> jarvisResponseNotifier = ValueNotifier<String>('');
  final ValueNotifier<bool> isOverlayVisibleNotifier = ValueNotifier<bool>(false);

  final List<ChatMessage> _jarvisHistory = [];

  /// Siri tarzı overlay'i göster
  void showOverlay() {
    isOverlayVisibleNotifier.value = true;
    statusNotifier.value = JarvisStatus.listening;
    userSpeechNotifier.value = 'Sizi dinliyorum efendim...';
    jarvisResponseNotifier.value = '';
  }

  /// Siri tarzı overlay'i kapat
  void hideOverlay() {
    _tts.stop();
    isOverlayVisibleNotifier.value = false;
    statusNotifier.value = JarvisStatus.idle;
  }

  /// Kullanıcının sesli komutunu dinleyip işler
  Future<String> processCommand(String rawCommand) async {
    final cleaned = rawCommand
        .replaceAll(RegExp(r'^(hey\s+)?jarvis[\s,]*', caseSensitive: false), '')
        .trim();

    if (cleaned.isEmpty) {
      const resp = 'Buyrun efendim, sizi dinliyorum.';
      jarvisResponseNotifier.value = resp;
      await _speak(resp);
      return resp;
    }

    userSpeechNotifier.value = cleaned;
    statusNotifier.value = JarvisStatus.thinking;

    final lower = cleaned.toLowerCase();

    // 1. DONANIM KONTROLLERİ: FENER
    if (lower.contains('fener') || lower.contains('flaş') || lower.contains('ışık')) {
      final enable = lower.contains('aç') || lower.contains('yak')
          ? true
          : (lower.contains('kapat') || lower.contains('söndür') ? false : null);
      final result = await _phoneControl.toggleFlashlight(enable: enable);
      return await _respond(result);
    }

    // 2. DONANIM KONTROLLERİ: PİL / ŞARJ
    if (lower.contains('pil') || lower.contains('şarj') || lower.contains('batarya')) {
      final result = await _phoneControl.getBatteryInfo();
      return await _respond(result);
    }

    // 3. DONANIM KONTROLLERİ: SES AYARI
    if (lower.contains('ses') &&
        (lower.contains('aç') ||
            lower.contains('yükselt') ||
            lower.contains('kıs') ||
            lower.contains('azalt') ||
            lower.contains('sessiz') ||
            lower.contains('ful') ||
            lower.contains('son ses'))) {
      final result = await _phoneControl.adjustVolume(lower);
      return await _respond(result);
    }

    // 4. UYGULAMA BAŞLATMA
    if (lower.contains('aç') &&
        (lower.contains('whatsapp') ||
            lower.contains('youtube') ||
            lower.contains('spotify') ||
            lower.contains('harita') ||
            lower.contains('maps') ||
            lower.contains('tarayıcı') ||
            lower.contains('chrome') ||
            lower.contains('kamera') ||
            lower.contains('mail') ||
            lower.contains('gmail'))) {
      final result = await _phoneControl.openApplication(lower);
      return await _respond(result);
    }

    // 5. MÜZİK KONTROLLERİ (Sadece açıkça "çal/aç/oynat/duraklat/kapat" denildiğinde)
    final musicCmd = VoiceCommandParser.parse(cleaned);
    if (musicCmd.type != VoiceActionType.unknown) {
      final result = await _handleMusicCommand(musicCmd);
      return await _respond(result);
    }

    // 6. YARATICI VE GENEL CEVAPLAR: GEMINI 2.5 FLASH BEYNİ (Sohbet & Genel Konuşma)
    try {
      const jarvisSystemPrompt = '''
Sen kullanıcının son derece sadık, karizmatik, zeki ve genel konularda sohbet edebilen Iron Man tarzı kişisel asistanı J.A.R.V.I.S.'sin.
Kullanıcı seninle Türkçe konuşuyor. Sorularını yanıtla, dertleş, bilgi ver veya emirlerini yerine getir.

YÖNERGELER:
- Kullanıcıya her zaman 'efendim' diyerek saygılı, samimi, esprili ve kendinden emin bir tonda konuş.
- Kullanıcı doğrudan müzik/şarkı aç demedikçe asla şarkı aramaya kalkma; sorusuna doğrudan ve zekice yanıt ver.
- Yanıtın sesli Türkçe konuşma motoru (TTS) ile seslendirileceği için en fazla 1 veya 2 akıcı, net cümle kur.
- Asla yıldız (*), diyez (#), emoji, parantez içi veya markdown sembolleri kullanma. Doğal konuşma Türkçesi kullan.
''';

      _jarvisHistory.add(
        ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content: cleaned,
          isUser: true,
          timestamp: DateTime.now(),
        ),
      );

      final geminiResp = await _geminiService.sendMessage(
        prompt: cleaned,
        history: _jarvisHistory,
        model: 'gemini-2.5-flash',
        customSystemPrompt: jarvisSystemPrompt,
      );

      final cleanText = geminiResp.text
          .replaceAll(RegExp(r'\[.*?\]'), '')
          .replaceAll(RegExp(r'\*\*|\*|#+|`+'), '')
          .trim();

      final reply = cleanText.isNotEmpty ? cleanText : 'Emredersiniz efendim, sizi dinliyorum.';

      _jarvisHistory.add(
        ChatMessage(
          id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
          content: reply,
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );

      if (_jarvisHistory.length > 20) {
        _jarvisHistory.removeRange(0, _jarvisHistory.length - 20);
      }

      return await _respond(reply);
    } catch (e) {
      debugPrint('[JarvisBrain] Gemini hatası: $e');
      return await _respond('Sizi duyabiliyorum efendim ancak bağlantımda ufak bir aksaklık oldu. Bir saniye sonra tekrar dener misiniz?');
    }
  }

  Future<String> _handleMusicCommand(ParsedVoiceCommand cmd) async {
    final audio = GlobalAudioService.instance;
    switch (cmd.type) {
      case VoiceActionType.pause:
        await audio.pauseOrResume();
        return 'Müzik duraklatıldı efendim.';
      case VoiceActionType.resume:
        await audio.pauseOrResume();
        return 'Müzik devam ettiriliyor efendim.';
      case VoiceActionType.stop:
        await audio.stop();
        return 'Müzik sonlandırıldı efendim.';
      case VoiceActionType.next:
        return 'Sonraki parçaya geçiliyor efendim.';
      case VoiceActionType.play:
        final song = cmd.songQuery ?? 'müzik';
        await audio.searchAndPlay(song);
        return '$song parçasını hemen arayıp çalıyorum efendim.';
      default:
        return 'Komutunuz anlaşıldı efendim.';
    }
  }

  Future<String> _respond(String reply) async {
    jarvisResponseNotifier.value = reply;
    statusNotifier.value = JarvisStatus.speaking;
    await _speak(reply);
    statusNotifier.value = JarvisStatus.idle;
    return reply;
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }
}
