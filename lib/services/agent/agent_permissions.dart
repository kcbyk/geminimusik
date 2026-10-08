import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'tools/permissions_tool.dart';

/// Çalışma zamanı izinlerini `permission_handler` ile bağlar.
///
/// Yalnızca `main()` içinden çağrılır: böylece ajan servisleri/testleri bu
/// eklentiye bağımlı olmaz. Android'in "Ayarlardan ver" dediği özel izinler
/// (tüm dosyalar, üzerinde çizim, pil) burada değil native katmanda ele alınır.
void wireAgentPermissions() {
  PermissionsTool.runtimeRequest = (permission) async {
    final target = _permissionFor(permission);
    if (target == null) return false;
    try {
      final status = await target.request();
      return status.isGranted || status.isLimited;
    } catch (error) {
      debugPrint('[Permissions] $permission istenemedi: $error');
      return false;
    }
  };
}

Permission? _permissionFor(String permission) => switch (permission) {
      'storage' => Permission.storage,
      'microphone' => Permission.microphone,
      'camera' => Permission.camera,
      'notifications' => Permission.notification,
      'location' => Permission.locationWhenInUse,
      'phone' => Permission.phone,
      _ => null,
    };
