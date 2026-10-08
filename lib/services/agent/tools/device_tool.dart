import 'dart:io';

import 'package:flutter/foundation.dart';

import '../agent_models.dart';
import 'shell_tool.dart';

/// Cihazın kendisi: kurulu uygulamalar, uygulama açma, uygulama bilgisi ve
/// cihaz özeti.
///
/// Uygulama açma iki yoldan denenir:
/// 1. `cmd package resolve-activity` ile launcher aktivitesini bulup `am start -n`
/// 2. yedek olarak `monkey -p <paket> -c android.intent.category.LAUNCHER 1`
///
/// Böylece adı bilinmeyen/hardcode edilmemiş uygulamalar da açılabilir.
class DeviceTool extends AgentTool {
  @override
  String get name => 'device';

  @override
  String get description =>
      'Cihazı yönetir. list_apps: kurulu uygulamaları listele (third_party=true '
      'sadece kullanıcı uygulamaları). open_app: herhangi bir uygulamayı paketi '
      'veya adıyla aç. app_info: bir uygulamanın sürüm/izin/kurulum bilgisi. '
      'info: cihaz özeti. Uygulama açmadan önce list_apps ile gerçek paket adını bul.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'action': {
            'type': 'STRING',
            'enum': ['list_apps', 'open_app', 'app_info', 'info'],
          },
          'query': {
            'type': 'STRING',
            'description':
                'open_app/app_info için paket adı veya uygulamanın adı (ör. "whatsapp").',
          },
          'third_party': {
            'type': 'BOOLEAN',
            'description': 'list_app için: true ise yalnızca kullanıcı uygulamaları.',
          },
          'limit': {
            'type': 'INTEGER',
            'description': 'list_apps için en fazla kaç satır (varsayılan 300).',
          },
        },
        'required': ['action'],
      };

  @override
  bool get speaksResult => true;

  /// Uygulama açmak cihazda görünür etki bırakır ama geri alınabilir;
  /// riskli saymıyoruz. Silme/izin değiştirme gibi işler zaten `shell` + onay.
  @override
  bool get requiresApproval => false;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final action = args['action'] as String? ?? 'info';
    final query = (args['query'] as String?)?.trim() ?? '';

    switch (action) {
      case 'list_apps':
        return _listApps(
          thirdParty: args['third_party'] != false,
          limit: ((args['limit'] as num?)?.toInt() ?? 300).clamp(10, 1000),
        );
      case 'open_app':
        if (query.isEmpty) {
          return ToolResult.error('open_app için query gerekli (paket adı veya uygulama adı).');
        }
        return _openApp(query);
      case 'app_info':
        if (query.isEmpty) {
          return ToolResult.error('app_info için query gerekli.');
        }
        return _appInfo(query);
      case 'info':
      default:
        return _deviceInfo();
    }
  }

  Future<ToolResult> _listApps({
    required bool thirdParty,
    required int limit,
  }) async {
    final flag = thirdParty ? '-3' : '';
    final run = await ShellTool.runRaw('pm list packages $flag'.trim());
    if (!run.ok) {
      return ToolResult.error(
          'Uygulama listesi alınamadı (exit ${run.exitCode}). ${run.stderr.trim()}');
    }
    final packages = run.stdout
        .split('\n')
        .map((line) => line.replaceFirst('package:', '').trim())
        .where((line) => line.isNotEmpty)
        .toList()
      ..sort();

    if (packages.isEmpty) return ToolResult('Liste boş döndü.');
    final shown = packages.take(limit).join('\n');
    return ToolResult(
        '${packages.length} uygulama${thirdParty ? ' (kullanıcı tarafından kurulanlar)' : ''}:\n'
        '$shown${packages.length > limit ? '\n… ${packages.length - limit} tane daha' : ''}');
  }

  Future<ToolResult> _openApp(String query) async {
    final package = await _resolvePackage(query);
    if (package == null) {
      return ToolResult.error(
          '"$query" için kurulu uygulama bulunamadı. list_apps ile gerçek paket '
          'adına bak (ör. WhatsApp -> com.whatsapp).');
    }

    // 1. Launcher aktivitesini çözümle.
    final resolve = await ShellTool.runRaw(
      'cmd package resolve-activity --brief -c android.intent.category.LAUNCHER $package '
      '| tail -n 1',
    );
    final component = resolve.stdout.trim();
    if (resolve.ok && component.contains('/') && !component.contains('Error')) {
      final start = await ShellTool.runRaw('am start -n ${_quote(component)}');
      if (start.ok) {
        return ToolResult('$package açıldı ($component).');
      }
    }

    // 2. Yedek: monkey ile launcher intent'i fırlat.
    final monkey = await ShellTool.runRaw(
      'monkey -p ${_quote(package)} -c android.intent.category.LAUNCHER 1',
    );
    final combined = '${monkey.stdout}\n${monkey.stderr}';
    if (monkey.ok && !combined.contains('No activities found')) {
      return ToolResult('$package açıldı.');
    }
    return ToolResult.error(
        '$package bulundu ama başlatılamadı. Çıktı: ${combined.trim()}');
  }

  Future<ToolResult> _appInfo(String query) async {
    final package = await _resolvePackage(query);
    if (package == null) {
      return ToolResult.error('"$query" için kurulu uygulama bulunamadı.');
    }
    final run = await ShellTool.runRaw(
      'dumpsys package ${_quote(package)} | '
      "grep -E 'versionName|versionCode|firstInstallTime|lastUpdateTime|"
      "dataDir|targetSdk' | head -n 12",
    );
    if (!run.ok || run.stdout.trim().isEmpty) {
      return ToolResult.error('$package bilgisi okunamadı. ${run.stderr.trim()}');
    }
    return ToolResult('$package:\n${run.stdout.trim()}');
  }

  Future<ToolResult> _deviceInfo() async {
    final buffer = StringBuffer();
    Future<void> add(String label, String command) async {
      final run = await ShellTool.runRaw(command, timeout: const Duration(seconds: 10));
      final value = run.stdout.trim();
      buffer.writeln('$label: ${value.isEmpty ? 'okunamadı' : value}');
    }

    await add('model', 'getprop ro.product.model');
    await add('üretici', 'getprop ro.product.manufacturer');
    await add('android', 'getprop ro.build.version.release');
    await add('sdk', 'getprop ro.build.version.sdk');
    await add('cihaz', 'getprop ro.product.device');
    await add('pil', 'dumpsys battery | grep level');
    await add('çözünürlük', 'wm size');
    await add('dil', 'getprop persist.sys.locale');

    final storage = await ShellTool.runRaw('df -h /sdcard 2>/dev/null | tail -n 1');
    buffer.writeln('depolama: ${storage.stdout.trim()}');
    buffer.write('ajan çalışma alanı: ${Directory.current.path}');
    return ToolResult(buffer.toString().trim());
  }

  /// Verilen metin zaten bir paket adıysa onu, değilse kurulu paketler içinde
  /// geçen en yakın eşleşmeyi döndürür.
  Future<String?> _resolvePackage(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.contains('.') && !_looksLikeAppName(normalized)) {
      final check = await ShellTool.runRaw('pm list packages $normalized');
      final found = check.stdout
          .split('\n')
          .map((l) => l.replaceFirst('package:', '').trim())
          .where((l) => l == normalized)
          .toList();
      if (found.isNotEmpty) return found.first;
    }

    final all = await ShellTool.runRaw('pm list packages');
    final packages = all.stdout
        .split('\n')
        .map((l) => l.replaceFirst('package:', '').trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return matchPackage(normalized, packages);
  }

  /// Kurulu paket listesi içinden en iyi eşleşmeyi seçer (saf fonksiyon,
  /// test edilebilir): önce tam eşleşme, sonra paket adının noktasız halinde
  /// geçenler; birden çok eşleşmede en kısa paket adı kazanır.
  @visibleForTesting
  static String? matchPackage(String query, List<String> packages) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty || packages.isEmpty) return null;

    for (final package in packages) {
      if (package.toLowerCase() == normalized) return package;
    }
    final key = normalized.replaceAll(RegExp(r'\s+'), '');
    if (key.isEmpty) return null;
    final matches = packages
        .where((p) => p.toLowerCase().replaceAll('.', '').contains(key))
        .toList();
    if (matches.isEmpty) return null;
    if (matches.length == 1) return matches.first;
    matches.sort((a, b) => a.length.compareTo(b.length));
    return matches.first;
  }

  static bool _looksLikeAppName(String value) =>
      !value.startsWith('com.') &&
      !value.startsWith('org.') &&
      !value.startsWith('net.') &&
      !value.startsWith('io.');

  static String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";
}
