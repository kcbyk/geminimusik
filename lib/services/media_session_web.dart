import 'dart:js' as js;
import 'package:flutter/foundation.dart';

void updateWebMediaSession({
  required String title,
  String? artist,
  String? artworkUrl,
  required bool isPlaying,
  VoidCallback? onPlay,
  VoidCallback? onPause,
  VoidCallback? onStop,
}) {
  try {
    if (onPlay != null) js.context['_flutterOnPlay'] = onPlay;
    if (onPause != null) js.context['_flutterOnPause'] = onPause;
    if (onStop != null) js.context['_flutterOnStop'] = onStop;
    js.context.callMethod('updateMediaSession', [title, artist ?? '', artworkUrl ?? '', isPlaying]);
  } catch (e) {
    debugPrint('Web MediaSession error: ');
  }
}

void clearWebMediaSession() {
  try {
    js.context.callMethod('clearMediaSession');
  } catch (_) {}
}
