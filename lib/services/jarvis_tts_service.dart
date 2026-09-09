import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Jarvis Doğal ve Karizmatik Erkek Seslendirme (Text-To-Speech) Servisi
class JarvisTtsService {
  static final JarvisTtsService instance = JarvisTtsService._internal();
  JarvisTtsService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;

  final ValueNotifier<bool> isSpeakingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> currentlySpeakingTextNotifier = ValueNotifier<String?>(null);

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // 1. Dil ve Temel Ayarlar (Türkçe)
      await _flutterTts.setLanguage('tr-TR');
      // Karizmatik, tok ve oturaklı Jarvis erkek tonu için pitch 0.82 (daha tok/derin)
      await _flutterTts.setPitch(0.82);
      // Akıcı ve anlaşılır konuşma hızı
      await _flutterTts.setSpeechRate(0.50);
      await _flutterTts.setVolume(1.0);

      // 2. Cihazdaki Türkçe Erkek Sesini Seç (Android / iOS / Web)
      await _configureMaleVoice();

      // 3. Durum Dinleyicileri
      _flutterTts.setStartHandler(() {
        isSpeakingNotifier.value = true;
      });

      _flutterTts.setCompletionHandler(() {
        isSpeakingNotifier.value = false;
        currentlySpeakingTextNotifier.value = null;
      });

      _flutterTts.setCancelHandler(() {
        isSpeakingNotifier.value = false;
        currentlySpeakingTextNotifier.value = null;
      });

      _flutterTts.setErrorHandler((msg) {
        debugPrint('[JarvisTTS] Hata: $msg');
        isSpeakingNotifier.value = false;
        currentlySpeakingTextNotifier.value = null;
      });

      _isInitialized = true;
    } catch (e) {
      debugPrint('[JarvisTTS] Başlatma hatası: $e');
    }
  }

  /// Cihazda kurulu ses motorlarından Türkçe erkek / en kaliteli sesi bulur ve ayarlar
  Future<void> _configureMaleVoice() async {
    try {
      final dynamic rawVoices = await _flutterTts.getVoices;
      if (rawVoices is List && rawVoices.isNotEmpty) {
        Map<String, String>? bestMaleVoice;

        for (final v in rawVoices) {
          if (v is Map) {
            final locale = (v['locale'] ?? v['lang'] ?? '').toString().toLowerCase();
            final name = (v['name'] ?? '').toString().toLowerCase();

            // Sadece Türkçe sesler arasından filtrele
            if (locale.contains('tr') || name.contains('tr')) {
              // Erkek (male) göstergelerini ara (örn: male, tr-tr-x-dfz, tr-tr-x-male, tr-tr-language-1)
              if (name.contains('male') ||
                  name.contains('erkek') ||
                  name.contains('man') ||
                  name.contains('dfz') || // Google TTS Türkçe Erkek sesi genelde tr-tr-x-dfz veya dfz'dir
                  name.contains('tr-tr-x-ama-network') ||
                  name.contains('network')) {
                bestMaleVoice = {
                  'name': v['name'].toString(),
                  'locale': (v['locale'] ?? 'tr-TR').toString(),
                };
                break;
              }

              // Yedek olarak herhangi bir Türkçe ses
              bestMaleVoice ??= {
                'name': v['name'].toString(),
                'locale': (v['locale'] ?? 'tr-TR').toString(),
              };
            }
          }
        }

        if (bestMaleVoice != null) {
          debugPrint('[JarvisTTS] Seçilen Türkçe Erkek Ses: ${bestMaleVoice['name']} (${bestMaleVoice['locale']})');
          await _flutterTts.setVoice(bestMaleVoice);
        }
      }
    } catch (e) {
      debugPrint('[JarvisTTS] Ses seçimi hatası: $e');
    }
  }

  /// Jarvis'in konuşmasını sağlar
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;

    await init();
    try {
      await stop(); // Varsa önceki konuşmayı hemen kes

      // Markdown ve gereksiz sembolleri temizle (seslendirmede yıldız, kare okunmasın)
      final cleanText = _cleanForSpeech(text);
      if (cleanText.isEmpty) return;

      currentlySpeakingTextNotifier.value = text;
      isSpeakingNotifier.value = true;
      await _flutterTts.speak(cleanText);
    } catch (e) {
      debugPrint('[JarvisTTS] Speak hatası: $e');
      isSpeakingNotifier.value = false;
      currentlySpeakingTextNotifier.value = null;
    }
  }

  /// Konuşmayı anında durdur
  Future<void> stop() async {
    try {
      await _flutterTts.stop();
      isSpeakingNotifier.value = false;
      currentlySpeakingTextNotifier.value = null;
    } catch (_) {}
  }

  /// Belirli bir metin şu an okunuyor mu kontrolü
  bool isSpeakingSpecificText(String text) {
    return isSpeakingNotifier.value && currentlySpeakingTextNotifier.value == text;
  }

  /// Belirli bir metni seslendir / durdur toggle
  Future<void> toggleSpeak(String text) async {
    if (isSpeakingSpecificText(text)) {
      await stop();
    } else {
      await speak(text);
    }
  }

  String _cleanForSpeech(String input) {
    return input
        .replaceAll(RegExp(r'\[ACTION:[^\]]+\]'), '') // Eylem etiketlerini temizle
        .replaceAll(RegExp(r'\*\*|\*|#+|`+|_{1,2}'), '') // Markdown
        .replaceAll(RegExp(r'\[.*?\]\(.*?\)'), '') // Linkler
        .replaceAll(RegExp(r'https?:\/\/\S+'), '') // URL'ler
        .replaceAll(RegExp(r'\n+'), '. ') // Satır başlarını nokta ile bağla
        .trim();
  }
}
