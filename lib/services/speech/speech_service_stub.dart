import 'speech_service.dart';

AppSpeechService getSpeechService() => StubSpeechService();

class StubSpeechService implements AppSpeechService {
  @override
  bool get isListening => false;

  @override
  Future<bool> initialize({
    required Function(String status) onStatus,
    required Function(String error) onError,
  }) async {
    onError('Bu platformda ses tanıma desteklenmiyor.');
    return false;
  }

  @override
  Future<void> listen({
    required Function(String text) onResult,
    String localeId = 'tr-TR',
  }) async {}

  @override
  Future<void> stop() async {}
}
