import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'speech_service.dart';

AppSpeechService getSpeechService() => IoSpeechService();

class IoSpeechService implements AppSpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  Function(String status)? _onStatus;
  Function(String error)? _onError;

  @override
  bool get isListening => _isListening;

  @override
  Future<bool> initialize({
    required Function(String status) onStatus,
    required Function(String error) onError,
  }) async {
    _onStatus = onStatus;
    _onError = onError;

    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
            _onStatus?.call('done');
          }
        },
        onError: (err) {
          _isListening = false;
          _onError?.call(err.errorMsg);
        },
      );
      return available;
    } catch (e) {
      onError('Mikrofon başlatılamadı: $e');
      return false;
    }
  }

  @override
  Future<void> listen({
    required Function(String text) onResult,
    String localeId = 'tr-TR',
  }) async {
    _isListening = true;
    _onStatus?.call('listening');

    try {
      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords;
          if (words.isNotEmpty) {
            onResult(words);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          cancelOnError: true,
          partialResults: true,
        ),
      );
    } catch (e) {
      _isListening = false;
      _onError?.call('Dinleme hatası: $e');
    }
  }

  @override
  Future<void> stop() async {
    _isListening = false;
    try {
      await _speech.stop();
    } catch (_) {}
    _onStatus?.call('done');
  }
}
