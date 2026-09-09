import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:porcupine_flutter/porcupine.dart';
import 'package:porcupine_flutter/porcupine_error.dart';

import 'jarvis_brain_service.dart';

/// Arka planda ve kilit ekranında çalışan düşük güçlü sesli asistan servisi.
/// Porcupine ile pil tüketmeden wake-word (örn. 'Jarvis', 'Porcupine') dinler,
/// algılandığında SpeechToText ile komutu alıp GlobalAudioService müzik motoruna iletir.
class VoiceAssistantService extends ChangeNotifier {
  static final VoiceAssistantService instance = VoiceAssistantService._();

  VoiceAssistantService._() {
    _initSettings();
  }

  // Ayar Anahtarları
  static const String _prefEnabled = 'voice_assistant_enabled';
  static const String _prefAccessKey = 'picovoice_access_key';
  static const String _prefKeyword = 'voice_assistant_keyword';

  // Varsayılan / Kayıtlı Ayarlar
  bool isEnabled = false;
  String accessKey = '';
  BuiltInKeyword selectedKeyword = BuiltInKeyword.JARVIS;

  // Durum Değişkenleri
  bool isListeningWakeWord = false;
  bool isListeningCommand = false;
  String lastStatus = 'Hazır';
  String lastRecognizedText = '';
  String? errorMessage;

  PorcupineManager? _porcupineManager;
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  Timer? _sttTimeoutTimer;

  /// SharedPreferences'tan kayıtlı ayarları yükler
  Future<void> _initSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isEnabled = prefs.getBool(_prefEnabled) ?? true;
      accessKey = prefs.getString(_prefAccessKey) ?? '';
      final keywordName = prefs.getString(_prefKeyword);
      if (keywordName != null) {
        selectedKeyword = BuiltInKeyword.values.firstWhere(
          (k) => k.name == keywordName,
          orElse: () => BuiltInKeyword.JARVIS,
        );
      }

      if (isEnabled && !kIsWeb) {
        await startAssistant();
      }
    } catch (e) {
      debugPrint('VoiceAssistantService init hatası: $e');
    }
  }

  /// Ayarları kaydeder
  Future<void> saveSettings({
    required bool enabled,
    required String key,
    required BuiltInKeyword keyword,
  }) async {
    isEnabled = enabled;
    accessKey = key.trim();
    selectedKeyword = keyword;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, isEnabled);
    await prefs.setString(_prefAccessKey, accessKey);
    await prefs.setString(_prefKeyword, selectedKeyword.name);

    notifyListeners();

    if (isEnabled) {
      await startAssistant();
    } else {
      await stopAssistant();
    }
  }

  bool get isKeylessMode => accessKey.trim().isEmpty;

  /// Foreground Servis'i başlatır (AccessKey varsa Porcupine, yoksa yerel STT modu)
  Future<void> startAssistant() async {
    if (kIsWeb) {
      lastStatus = 'Web tarayıcısında arka plan servisi desteklenmiyor.';
      notifyListeners();
      return;
    }

    try {
      errorMessage = null;
      lastStatus = 'Başlatılıyor...';
      notifyListeners();

      // 1. Android İzinleri ve Foreground Servis Yapılandırması
      await _initForegroundTask();

      if (isKeylessMode) {
        // Picovoice AccessKey olmadan: Doğrudan cihazın yerel motoruyla arka planda dinle
        await _startKeylessListening();
      } else {
        // Picovoice AccessKey ile: Düşük güçlü Porcupine wake-word motorunu çalıştır
        await _initPorcupine();
        await _porcupineManager?.start();
        isListeningWakeWord = true;
        lastStatus = 'Dinliyor ("${selectedKeyword.name}")...';
        notifyListeners();
        _updateForegroundNotification('AI Sesli Asistan Aktif', 'Uyandırma kelimesi bekleniyor...');
      }
    } catch (e) {
      isListeningWakeWord = false;
      errorMessage = 'Asistan başlatılamadı: $e';
      lastStatus = 'Hata oluştu';
      notifyListeners();
      debugPrint('startAssistant error: $e');
    }
  }

  /// Asistanı ve dinleme motorlarını güvenli şekilde durdurur
  Future<void> stopAssistant() async {
    try {
      isListeningWakeWord = false;
      isListeningCommand = false;
      _sttTimeoutTimer?.cancel();

      if (_porcupineManager != null) {
        await _porcupineManager?.stop();
        await _porcupineManager?.delete();
        _porcupineManager = null;
      }

      if (_speechToText.isListening) {
        await _speechToText.stop();
      }

      if (!kIsWeb && await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }

      lastStatus = 'Durduruldu';
      notifyListeners();
    } catch (e) {
      debugPrint('stopAssistant error: $e');
    }
  }

  /// Porcupine yöneticisini başlatır
  Future<void> _initPorcupine() async {
    if (_porcupineManager != null) {
      await _porcupineManager?.stop();
      await _porcupineManager?.delete();
      _porcupineManager = null;
    }

    _porcupineManager = await PorcupineManager.fromBuiltInKeywords(
      accessKey,
      [selectedKeyword],
      _onWakeWordDetected,
      errorCallback: (PorcupineException error) {
        debugPrint('Porcupine Hata: ${error.message}');
        errorMessage = 'Porcupine: ${error.message}';
        notifyListeners();
      },
    );
  }

  /// Wake-Word algılandığında tetiklenir
  Future<void> _onWakeWordDetected(int keywordIndex) async {
    debugPrint('*** WAKE WORD ALGILANDI: ${selectedKeyword.name} ***');
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.click);

    // Siri tarzı overlay'i aç
    JarvisBrainService.instance.showOverlay();

    isListeningWakeWord = false;
    isListeningCommand = true;
    lastStatus = 'Sizi dinliyor...';
    notifyListeners();

    _updateForegroundNotification('J.A.R.V.I.S. Sizi Dinliyor...', 'Komutunuzu söyleyin...');

    // Mikrofon çakışmaması için Porcupine'ı geçici durdur
    try {
      await _porcupineManager?.stop();
    } catch (_) {}

    // Speech-To-Text ile sesli komutu al
    await _listenForVoiceCommand();
  }

  /// Sesli komutu dinler ve ayrıştırıcıya iletir
  Future<void> _listenForVoiceCommand() async {
    final available = await _speechToText.initialize(
      onError: (val) {
        debugPrint('STT Hata: $val');
        _resumeWakeWordListening();
      },
      onStatus: (val) {
        if (val == 'done' || val == 'notListening') {
          _resumeWakeWordListening();
        }
      },
    );

    if (!available) {
      lastStatus = 'Konuşma tanıma başlatılamadı';
      _resumeWakeWordListening();
      return;
    }

    String recognizedWords = '';

    _sttTimeoutTimer?.cancel();
    _sttTimeoutTimer = Timer(const Duration(seconds: 6), () {
      if (isListeningCommand) {
        _resumeWakeWordListening();
      }
    });

    await _speechToText.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: 'tr_TR',
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 3),
      ),
      onResult: (result) {
        recognizedWords = result.recognizedWords;
        lastRecognizedText = recognizedWords;
        JarvisBrainService.instance.userSpeechNotifier.value = recognizedWords;
        notifyListeners();

        if (result.finalResult && recognizedWords.isNotEmpty) {
          _sttTimeoutTimer?.cancel();
          _executeCommand(recognizedWords);
        }
      },
    );
  }

  /// Alınan komutu Jarvis Brain servisine gönderir
  Future<void> _executeCommand(String text) async {
    debugPrint('Jarvis komutu işleniyor: "$text"');
    lastStatus = 'İşleniyor: "$text"';
    notifyListeners();

    JarvisBrainService.instance.showOverlay();
    final reply = await JarvisBrainService.instance.processCommand(text);
    _updateForegroundNotification('J.A.R.V.I.S.', reply);

    if (isKeylessMode) {
      isListeningCommand = false;
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (isEnabled && isKeylessMode) {
          _listenKeylessTurn();
        }
      });
    } else {
      _resumeWakeWordListening();
    }
  }

  /// AccessKey gerekmeden doğrudan telefonun mikrofonu ve yerel STT motoruyla çalışan arka plan döngüsü
  Future<void> _startKeylessListening() async {
    isListeningWakeWord = true;
    lastStatus = 'Yerel Dinlemede (Anahtar Gerekmez)...';
    notifyListeners();
    _updateForegroundNotification('AI Asistan Dinliyor (Yerel Mod)', 'Şarkı veya komut söyleyin (Örn: "Duman çal")');

    final available = await _speechToText.initialize(
      onError: (val) {
        debugPrint('Keyless STT Hata: $val');
        if (isEnabled && isKeylessMode) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (isEnabled && isKeylessMode) _listenKeylessTurn();
          });
        }
      },
      onStatus: (val) {
        if (val == 'done' || val == 'notListening') {
          if (isEnabled && isKeylessMode && !isListeningCommand) {
            Future.delayed(const Duration(milliseconds: 900), () {
              if (isEnabled && isKeylessMode) _listenKeylessTurn();
            });
          }
        }
      },
    );

    if (!available) {
      lastStatus = 'Mikrofon / Konuşma tanıma açılamadı';
      notifyListeners();
      return;
    }

    _listenKeylessTurn();
  }

  Future<void> _listenKeylessTurn() async {
    if (!isEnabled || !isKeylessMode) return;
    if (_speechToText.isListening) return;

    try {
      await _speechToText.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: 'tr_TR',
          listenFor: const Duration(seconds: 8),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
        ),
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            lastRecognizedText = words;
            notifyListeners();

            if (result.finalResult) {
              isListeningCommand = true;
              _executeCommand(words);
            }
          }
        },
      );
    } catch (e) {
      debugPrint('Keyless turn dinleme hatası: $e');
    }
  }

  /// Komut alımı bittikten sonra tekrar Porcupine ile düşük güçlü dinlemeye döner
  Future<void> _resumeWakeWordListening() async {
    isListeningCommand = false;
    _sttTimeoutTimer?.cancel();

    if (_speechToText.isListening) {
      await _speechToText.stop();
    }

    if (isEnabled && _porcupineManager != null) {
      try {
        await _porcupineManager?.start();
        isListeningWakeWord = true;
        lastStatus = 'Dinliyor ("${selectedKeyword.name}")...';
        _updateForegroundNotification('AI Sesli Asistan Aktif', 'Uyandırma kelimesi bekleniyor...');
      } catch (e) {
        debugPrint('Porcupine yeniden başlatma hatası: $e');
      }
    }
    notifyListeners();
  }

  /// Android Foreground Task başlatma
  Future<void> _initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ai_voice_assistant_channel',
        channelName: 'AI Sesli Asistan',
        channelDescription: 'Arka planda sesli komut ve wake-word dinleme servisi.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    if (!await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'AI Sesli Asistan Aktif',
        notificationText: 'Uyandırma kelimesi bekleniyor...',
        callback: _foregroundTaskCallback,
      );
    }
  }

  void _updateForegroundNotification(String title, String text) {
    if (!kIsWeb) {
      FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    }
  }

  /// Pil Optimizasyonunu Yoksayma İsteği (Battery Optimization Whitelist)
  Future<bool> requestBatteryOptimizationException() async {
    if (kIsWeb) return false;
    return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }
}

/// Foreground Task arka plan boş döngüsü
@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_VoiceTaskHandler());
}

class _VoiceTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
