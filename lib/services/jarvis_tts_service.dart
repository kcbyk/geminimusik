import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Jarvis Doğal Seslendirme (Text-To-Speech) Servisi
class JarvisTtsService {
  static final JarvisTtsService instance = JarvisTtsService._internal();
  JarvisTtsService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;

  final ValueNotifier<bool> isSpeakingNotifier = ValueNotifier<bool>(false);

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      await _flutterTts.setLanguage('tr-TR');
      await _flutterTts.setSpeechRate(0.52); // Doğal asistan konuşma hızı
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _flutterTts.setStartHandler(() {
        isSpeakingNotifier.value = true;
      });

      _flutterTts.setCompletionHandler(() {
        isSpeakingNotifier.value = false;
      });

      _flutterTts.setCancelHandler(() {
        isSpeakingNotifier.value = false;
      });

      _flutterTts.setErrorHandler((msg) {
        debugPrint('[JarvisTTS] Hata: $msg');
        isSpeakingNotifier.value = false;
      });

      _isInitialized = true;
    } catch (e) {
      debugPrint('[JarvisTTS] Başlatma hatası: $e');
    }
  }

  /// Jarvis'in konuşmasını sağlar
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;

    await init();
    try {
      await stop(); // Önceki konuşmayı kes

      // Markdown ve gereksiz sembolleri temizle (seslendirmede yıldız, kare okunmasın)
      final cleanText = _cleanForSpeech(text);
      await _flutterTts.speak(cleanText);
    } catch (e) {
      debugPrint('[JarvisTTS] Speak hatası: $e');
      isSpeakingNotifier.value = false;
    }
  }

  /// Konuşmayı anında durdur
  Future<void> stop() async {
    try {
      await _flutterTts.stop();
      isSpeakingNotifier.value = false;
    } catch (_) {}
  }

  String _cleanForSpeech(String input) {
    return input
        .replaceAll(RegExp(r'\*\*|\*|#+|`+|_{1,2}'), '')
        .replaceAll(RegExp(r'\[.*?\]\(.*?\)'), '')
        .replaceAll(RegExp(r'\n+'), '. ')
        .trim();
  }
}
