import 'package:flutter/services.dart';

class ImageDownloadService {
  static const MethodChannel _channel =
      MethodChannel('ai_music_hub/image_download');

  static Future<void> download(
      {required String url, required String fileName}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw const FormatException(
          'Yalnızca güvenli HTTPS görseller indirilebilir.');
    }
    await _channel.invokeMethod<void>(
        'downloadImage', {'url': url, 'fileName': fileName});
  }
}
