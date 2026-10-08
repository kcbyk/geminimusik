import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

/// Ajanın Android tarafındaki kolları.
///
/// `pm list packages` / `am start` gibi kabuk komutları sıradan bir
/// uygulamada çoğu cihazda "Permission Denial" ile döner. Bu yüzden
/// paket/uygulama işleri ve Termux devri native kanallardan yapılır
/// (PackageManager + RUN_COMMAND intent).
///
/// Kanallar yalnızca Android'de ve yalnızca gerçek cihazda çalışır; test
/// ortamında [available] false döner ve araçlar kabuk yedeğine düşer.
class AgentNative {
  AgentNative._();

  static const MethodChannel deviceChannel =
      MethodChannel('ai_music_hub/device');
  static const MethodChannel termuxChannel =
      MethodChannel('ai_music_hub/termux');

  /// Native katman bu platformda kullanılabilir mi?
  ///
  /// `defaultTargetPlatform` kullanılıyor (Platform.isAndroid değil): böylece
  /// testler `debugDefaultTargetPlatformOverride` ile Android'i taklit edip
  /// sahte kanalı gerçekten çalıştırabiliyor.
  static bool get available =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<Object?> _invoke(MethodChannel channel, String method,
      [Map<String, Object?>? args]) async {
    if (!available) return null;
    try {
      return await channel.invokeMethod<Object?>(method, args ?? const {});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Cihaz kanalı gerçekten yanıt veriyor mu? (eski APK'larda false döner)
  static Future<bool> deviceChannelAlive() async {
    if (!available) return false;
    final info = await deviceInfo();
    return info != null;
  }

  // ------------------------------------------------------------------ device

  static Future<Map<String, dynamic>?> deviceInfo() async {
    final raw = await _invoke(deviceChannel, 'deviceInfo');
    return _asMap(raw);
  }

  static Future<Map<String, dynamic>?> listApps({
    String query = '',
    bool thirdParty = false,
    bool launchable = false,
    int limit = 300,
  }) async {
    final raw = await _invoke(deviceChannel, 'listApps', {
      'query': query,
      'thirdParty': thirdParty,
      'launchable': launchable,
      'limit': limit,
    });
    return _asMap(raw);
  }

  static Future<Map<String, dynamic>?> resolvePackage(String query) async {
    final raw =
        await _invoke(deviceChannel, 'resolvePackage', {'query': query});
    return _asMap(raw);
  }

  static Future<Map<String, dynamic>?> appInfo(String package) async {
    final raw = await _invoke(deviceChannel, 'appInfo', {'package': package});
    return _asMap(raw);
  }

  static Future<Map<String, dynamic>?> openApp(String package) async {
    final raw = await _invoke(deviceChannel, 'openApp', {'package': package});
    return _asMap(raw);
  }

  static Future<Map<String, dynamic>?> openAppSettings(
      [String? package]) async {
    final raw = await _invoke(deviceChannel, 'openAppSettings', {
      'package': package ?? '',
    });
    return _asMap(raw);
  }

  // ------------------------------------------------------------------ termux

  static Future<bool> isTermuxInstalled() async {
    final raw = await _invoke(deviceChannel, 'isTermuxInstalled');
    return raw == true;
  }

  static Future<Map<String, dynamic>?> termuxInfo() async {
    final raw = await _invoke(deviceChannel, 'termuxInfo');
    return _asMap(raw);
  }

  static Future<Map<String, dynamic>?> termuxOpenStore() async {
    final raw = await _invoke(deviceChannel, 'termuxOpenStore');
    return _asMap(raw);
  }

  static Future<Map<String, dynamic>?> runInTermux({
    required String command,
    int timeoutSeconds = 30,
    bool background = false,
    String workdir = '',
  }) async {
    final raw = await _invoke(termuxChannel, 'run', {
      'command': command,
      'timeoutSeconds': timeoutSeconds,
      'background': background,
      'workdir': workdir,
    });
    return _asMap(raw);
  }

  // ------------------------------------------------------------- permissions

  static Future<Map<String, dynamic>?> permissionStatus(
      List<String> permissions) async {
    final raw = await _invoke(
        deviceChannel, 'permissionStatus', {'permissions': permissions});
    return _asMap(raw);
  }

  static Future<Map<String, dynamic>?> openPermissionSettings(
      String key) async {
    final raw = await _invoke(
        deviceChannel, 'openPermissionSettings', {'permission': key});
    return _asMap(raw);
  }

  static Map<String, dynamic>? _asMap(Object? raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }
}
