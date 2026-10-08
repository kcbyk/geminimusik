import 'package:flutter/foundation.dart';

import '../agent_models.dart';
import '../agent_native.dart';

/// Ajanın yetki kontrolü: bir iş için gereken izni ister, verilmediyse
/// kullanıcının verebileceği ekranı açar.
///
/// Çalışma zamanı izinleri (mikrofon, kamera, bildirim, depolama)
/// `permission_handler` ile Dart tarafından istenir. Android'in "Ayarlardan
/// ver" dediği özel izinler (tüm dosyalar, pil optimizasyonu, üzerinde çizim)
/// native katmandan ilgili sistem ekranı açılarak istenir.
class PermissionsTool extends AgentTool {
  @override
  String get name => 'permissions';

  @override
  String get description =>
      'İzin yönetimi. action=status: hangi izinler verilmiş. action=request: '
      'eksik izni kullanıcıdan iste (ekranda sistem diyaloğu açılır). '
      'action=open_settings: iznin verildiği sistem ekranını aç. '
      'Bir iş "izin yok" diye kaldıysa tahmin yürütme: önce status, sonra request, '
      'reddedildiyse open_settings ile kullanıcıya yolu göster.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'action': {
            'type': 'STRING',
            'enum': ['status', 'request', 'open_settings'],
          },
          'permission': {
            'type': 'STRING',
            'enum': [
              'storage',
              'allFiles',
              'microphone',
              'camera',
              'notifications',
              'location',
              'overlay',
              'battery',
              'phone',
              'appSettings',
            ],
            'description': 'storage: medya okuma/yazma. allFiles: tüm dosyalara tam erişim '
                '(Ayarlardan). microphone/camera/notifications/location: çalışma '
                'zamanı izinleri. overlay: ekran üzerinde çizim (Jarvis balonu). '
                'battery: pil optimizasyonundan muafiyet. appSettings: uygulamanın '
                'kendi ayar sayfası.',
          },
        },
        'required': ['action', 'permission'],
      };

  /// İzin istemek kullanıcıya görünür bir diyalog/ekran açar: onaya sunulur.
  @override
  bool get requiresApproval => true;

  @override
  bool get speaksResult => true;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final action = args['action'] as String? ?? 'status';
    final permission = (args['permission'] as String?)?.trim() ?? '';

    if (permission.isEmpty) {
      return ToolResult.error('permission alanı zorunlu.');
    }
    if (!_known.contains(permission)) {
      return ToolResult.error('Bilinmeyen izin: $permission. '
          'Kullanılabilecekler: ${_known.join(', ')}.');
    }

    switch (action) {
      case 'status':
        return _status(permission);
      case 'request':
        return _request(permission);
      case 'open_settings':
        return _openSettings(permission);
      default:
        return ToolResult.error(
            'Bilinmeyen eylem: $action. Kullanılabilecekler: status, request, open_settings.');
    }
  }

  Future<ToolResult> _status(String permission) async {
    final native = await AgentNative.permissionStatus([permission]);
    if (native == null) {
      return ToolResult.error(
          'İzin durumu bu sürümde okunamıyor (native katman yok). '
          'Kullanıcıdan Ayarlar > Uygulamalar üzerinden vermesini iste.');
    }
    final raw = '${native[permission] ?? 'unknown'}';
    return ToolResult('$permission: ${_label(raw)}');
  }

  Future<ToolResult> _request(String permission) async {
    // Ayarlardan verilen özel izinler: diyalog yok, ekran açılır.
    if (_settingsOnly.contains(permission)) {
      return _openSettings(permission);
    }

    final handler = runtimeRequest;
    if (handler == null) {
      return ToolResult.error(
          'Bu sürümde çalışma zamanı izni istenemiyor. open_settings ile '
          'kullanıcıyı Ayarlar\'a yönlendir.');
    }

    final before = await AgentNative.permissionStatus([permission]);
    final granted = await handler(permission);
    if (granted) {
      return ToolResult('$permission izni verildi. İşe devam edebilirsin.');
    }
    final after = await AgentNative.permissionStatus([permission]);
    final permanentlyDenied = '${before?[permission]}' == 'denied' &&
        '${after?[permission]}' == 'denied';
    return ToolResult.error(
        '$permission izni verilmedi${permanentlyDenied ? ' (sistem artık sormuyor olabilir)' : ''}. '
        'open_settings ile Ayarlar ekranını aç ve kullanıcıdan elle vermesini iste.');
  }

  Future<ToolResult> _openSettings(String permission) async {
    final native = await AgentNative.openPermissionSettings(permission);
    if (native == null) {
      return ToolResult.error('Ayarlar ekranı bu sürümde açılamıyor.');
    }
    if (native['ok'] != true) {
      return ToolResult.error('Ayarlar açılamadı: ${native['error']}');
    }
    return ToolResult(
        '${_title(permission)} ayar ekranı açıldı. Kullanıcıdan izni '
        'vermesini iste; verdikten sonra status ile doğrula.');
  }

  static const Set<String> _known = {
    'storage',
    'allFiles',
    'microphone',
    'camera',
    'notifications',
    'location',
    'overlay',
    'battery',
    'phone',
    'appSettings',
  };

  /// Diyaloğu olmayan, yalnızca sistem ekranından verilebilen izinler.
  static const Set<String> _settingsOnly = {
    'allFiles',
    'overlay',
    'battery',
    'appSettings',
  };

  static String _title(String permission) => switch (permission) {
        'storage' => 'Depolama',
        'allFiles' => 'Tüm dosyalara erişim',
        'microphone' => 'Mikrofon',
        'camera' => 'Kamera',
        'notifications' => 'Bildirim',
        'location' => 'Konum',
        'overlay' => 'Üzerinde çizim',
        'battery' => 'Pil optimizasyonu',
        'phone' => 'Telefon',
        _ => 'Uygulama',
      };

  static String _label(String status) => switch (status) {
        'granted' => 'verilmiş',
        'denied' => 'verilmemiş',
        'notRequired' => 'bu Android sürümünde gerekmiyor',
        _ => 'bilinmiyor',
      };

  /// Çalışma zamanı iznini isteyen fonksiyon. `permission_handler` ile
  /// `AgentController.initialize()` içinde bağlanır; testlerde sahte verilir.
  @visibleForTesting
  static Future<bool> Function(String permission)? runtimeRequest;
}
