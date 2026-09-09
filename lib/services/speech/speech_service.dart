import 'speech_service_stub.dart'
    if (dart.library.html) 'speech_service_web.dart'
    if (dart.library.io) 'speech_service_io.dart';

abstract class AppSpeechService {
  factory AppSpeechService() => getSpeechService();

  bool get isListening;

  Future<bool> initialize({
    required Function(String status) onStatus,
    required Function(String error) onError,
  });

  Future<void> listen({
    required Function(String text) onResult,
    String localeId = 'tr-TR',
  });

  Future<void> stop();
}
