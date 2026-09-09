import 'dart:html' as html;
import 'speech_service.dart';

AppSpeechService getSpeechService() => WebSpeechService();

class WebSpeechService implements AppSpeechService {
  html.SpeechRecognition? _recognition;
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

    if (!html.SpeechRecognition.supported) {
      onError('Tarayıcınız Web Speech API ses tanımayı desteklemiyor.');
      return false;
    }
    return true;
  }

  @override
  Future<void> listen({
    required Function(String text) onResult,
    String localeId = 'tr-TR',
  }) async {
    if (!html.SpeechRecognition.supported) return;

    try {
      _recognition?.stop();
    } catch (_) {}

    _recognition = html.SpeechRecognition();
    _recognition!.continuous = true;
    _recognition!.interimResults = true;
    _recognition!.lang = localeId;

    _recognition!.onStart.listen((_) {
      _isListening = true;
      _onStatus?.call('listening');
    });

    _recognition!.onResult.listen((html.SpeechRecognitionEvent event) {
      final results = event.results;
      if (results != null) {
        final buffer = StringBuffer();
        for (final res in results) {
          final len = res.length ?? 0;
          if (len > 0) {
            final item = res.item(0);
            if (item.transcript != null) {
              buffer.write(item.transcript);
            }
          }
        }
        final text = buffer.toString().trim();
        if (text.isNotEmpty) {
          onResult(text);
        }
      }
    });

    _recognition!.onError.listen((html.SpeechRecognitionError event) {
      _isListening = false;
      _onError?.call(event.error ?? 'Ses tanıma hatası');
    });

    _recognition!.onEnd.listen((_) {
      _isListening = false;
      _onStatus?.call('done');
    });

    _isListening = true;
    _recognition!.start();
  }

  @override
  Future<void> stop() async {
    _isListening = false;
    try {
      _recognition?.stop();
    } catch (_) {}
    _onStatus?.call('done');
  }
}
