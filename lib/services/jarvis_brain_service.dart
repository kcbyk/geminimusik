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

    // 5. MÜZİK KONTROLLERİ (Doğrudan Çalma, Durdurma vb.)
    final musicCmd = VoiceCommandParser.parse(cleaned);
    if (musicCmd.type != VoiceActionType.unknown) {
      final result = await _handleMusicCommand(musicCmd);
      return await _respond(result);
    }

    // 6. YARATICI VE GENEL CEVAPLAR: GEMINI 2.5 FLASH BEYNİ
    try {
      final prompt = '''
Sen kullanıcının kişisel akıllı asistanı J.A.R.V.I.S.'sin.
Kullanıcı sesli olarak sana şunu söyledi: "$cleaned".

YÖNERGELER:
- Kullanıcıya her zaman 'efendim' şeklinde nazik, zeki, hızlı, esprili ve sadık bir Iron Man Jarvis'i gibi konuş.
- Sesli asistan (TTS) tarafından seslendirileceği için yanıtın en fazla 2-3 akıcı ve net cümle olsun.
- Asla yıldız, kare, madde imi veya markdown işareti kullanma; doğrudan konuşma diliyle Türkçe yaz.
''';

      final geminiResp = await _geminiService.sendMessage(
        prompt: prompt,
        history: [
          ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            content: prompt,
            isUser: true,
            timestamp: DateTime.now(),
          ),
        ],
        model: 'gemini-2.5-flash',
      );

      final cleanText = geminiResp.text.replaceAll(RegExp(r'\[.*?\]'), '').trim();
      return await _respond(cleanText.isNotEmpty ? cleanText : 'Emredersiniz efendim, işlem tamam.');
    } catch (e) {
      debugPrint('[JarvisBrain] Gemini hatası: $e');
      return await _respond('Bir bağlantı aksaklığı oldu efendim, ancak her şey kontrolüm altında.');
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
