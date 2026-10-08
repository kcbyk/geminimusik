import 'dart:io';

import 'package:flutter/foundation.dart';

import '../agent_models.dart';
import '../agent_native.dart';
import 'shell_tool.dart';

/// Cihazın kendisi: kurulu uygulamalar, uygulama açma, uygulama bilgisi,
/// Termux kurulumu, izin ayarları ve cihaz özeti.
///
/// Birincil yol Android API'sidir (PackageManager / launch intent):
/// `pm list packages` ve `am start` kabuk komutları sıradan bir uygulamada
/// çoğu cihazda "Permission Denial" ile döner. Native katman yoksa (eski APK,
/// masaüstü, test) kabuk yedeğine düşülür.
class DeviceTool extends AgentTool {
  @override
  String get name => 'device';

  @override
  String get description =>
      'Cihazı yönetir. list_apps: kurulu uygulamaları listele (query ile ara, '
      'third_party=true sadece kullanıcı uygulamaları, launchable=true sadece '
      'açılabilir olanlar). open_app: herhangi bir uygulamayı adıyla veya '
      'paketiyle aç. app_info: sürüm/izin/kurulum bilgisi. open_app_settings: '
      'bir uygulamanın sistem ayar sayfasını aç. install_app: mağazada ara. '
      'termux: Termux kurulu mu, dışarıdan komut kabul ediyor mu. info: cihaz '
      'özeti. Bilmediğin bir uygulama için önce list_apps ile gerçek adı bul.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'action': {
            'type': 'STRING',
            'enum': [
              'list_apps',
              'open_app',
              'app_info',
              'open_app_settings',
              'install_app',
              'termux',
              'info',
            ],
          },
          'query': {
            'type': 'STRING',
            'description':
                'Uygulama adı veya paket adı (ör. "whatsapp" ya da "com.whatsapp").',
          },
          'third_party': {
            'type': 'BOOLEAN',
            'description':
                'list_apps: true ise yalnızca kullanıcı uygulamaları.',
          },
          'launchable': {
            'type': 'BOOLEAN',
            'description':
                'list_apps: true ise yalnızca açılabilir uygulamalar.',
          },
          'limit': {
            'type': 'INTEGER',
            'description':
                'list_apps için en fazla kaç satır (varsayılan 300).',
          },
        },
        'required': ['action'],
      };

  @override
  bool get speaksResult => true;

  /// Uygulama açmak görünür ama geri alınabilir bir etki; onay istemiyoruz.
  /// Silme/izin değiştirme gibi işler zaten `shell` + onay gerektirir.
  @override
  bool get requiresApproval => false;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final action = args['action'] as String? ?? 'info';
    final query = (args['query'] as String?)?.trim() ?? '';

    switch (action) {
      case 'list_apps':
        return _listApps(
          query: query,
          thirdParty: args['third_party'] != false,
          launchable: args['launchable'] == true,
          limit: ((args['limit'] as num?)?.toInt() ?? 300).clamp(10, 1000),
        );
      case 'open_app':
        if (query.isEmpty) {
          return ToolResult.error(
              'open_app için query gerekli (paket adı veya uygulama adı).');
        }
        return _openApp(query);
      case 'app_info':
        if (query.isEmpty) {
          return ToolResult.error('app_info için query gerekli.');
        }
        return _appInfo(query);
      case 'open_app_settings':
        return _openAppSettings(query);
      case 'install_app':
        if (query.isEmpty) {
          return ToolResult.error('install_app için query gerekli.');
        }
        return _installApp(query);
      case 'termux':
        return _termux();
      case 'info':
        return _deviceInfo();
      default:
        return ToolResult.error(
            'Bilinmeyen eylem: $action. Kullanılabilecekler: list_apps, open_app, '
            'app_info, open_app_settings, install_app, termux, info.');
    }
  }

  // -------------------------------------------------------------- list_apps

  Future<ToolResult> _listApps({
    required String query,
    required bool thirdParty,
    required bool launchable,
    required int limit,
  }) async {
    final native = await AgentNative.listApps(
      query: query,
      thirdParty: thirdParty,
      launchable: launchable,
      limit: limit,
    );

    if (native != null) {
      final apps = (native['apps'] as List?) ?? const [];
      if (apps.isEmpty) {
        return ToolResult(
            'Eşleşen uygulama yok (görünen toplam paket: ${native['visibleTotal']}). '
            "query'yi kısaltmayı ya da third_party=false deneyebilirsin.");
      }
      final buffer = StringBuffer()
        ..writeln('${apps.length} uygulama'
            '${thirdParty ? ' (kullanıcı uygulamaları)' : ''}'
            '${query.isEmpty ? '' : ' — "$query" için'}:');
      for (final raw in apps) {
        final app = _asMap(raw);
        if (app == null) continue;
        final flags = <String>[
          if (app['system'] == true) 'sistem',
          if (app['launchable'] == false) 'açılamaz',
          if (app['enabled'] == false) 'devre dışı',
        ];
        buffer.writeln('- ${app['label']}  →  ${app['package']}'
            '  [${app['version']}]'
            '${flags.isEmpty ? '' : ' (${flags.join(', ')})'}');
      }
      if (native['truncated'] == true) {
        buffer.writeln('… liste kırpıldı, query ile daralt.');
      }
      return ToolResult(buffer.toString().trim());
    }

    // --- yedek: kabuk (çoğu cihazda izin vermez, yine de denenir) ---
    final flag = thirdParty ? '-3' : '';
    final run = await ShellTool.runRaw('pm list packages $flag'.trim());
    if (!run.ok || run.stdout.trim().isEmpty) {
      return ToolResult.error(
          'Uygulama listesi alınamadı (exit ${run.exitCode}). '
          '${run.stderr.trim().isEmpty ? 'Cihaz kabuk üzerinden paket listesi vermeyi '
              'reddediyor.' : run.stderr.trim()}');
    }
    var packages = run.stdout
        .split('\n')
        .map((line) => line.replaceFirst('package:', '').trim())
        .where((line) => line.isNotEmpty)
        .toList()
      ..sort();
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      packages = packages.where((p) => p.toLowerCase().contains(q)).toList();
    }
    if (packages.isEmpty) return ToolResult('Liste boş döndü.');
    final shown = packages.take(limit).join('\n');
    return ToolResult('${packages.length} uygulama:\n$shown'
        '${packages.length > limit ? '\n… ${packages.length - limit} tane daha' : ''}');
  }

  // --------------------------------------------------------------- open_app

  Future<ToolResult> _openApp(String query) async {
    final resolved = await _resolve(query);
    if (resolved == null) {
      return ToolResult.error(
          '"$query" için kurulu uygulama bulunamadı. list_apps ile gerçek adı ara '
          '(ör. WhatsApp → com.whatsapp).');
    }
    final package = resolved['package'] as String;
    final label = (resolved['label'] as String?)?.trim() ?? '';
    final candidates = resolved['candidates'];

    final native = await AgentNative.openApp(package);
    if (native != null) {
      if (native['ok'] == true) {
        return ToolResult(
            '${label.isEmpty ? package : '$label ($package)'} açıldı '
            '— yol: ${native['via']}.');
      }
      final hint = candidates is List && candidates.length > 1
          ? '\nBenzer adaylar: '
              '${candidates.map((c) => _asMap(c)?['package']).take(4).join(', ')}'
          : '';
      return ToolResult.error(
          '${label.isEmpty ? package : label} açılamadı: ${native['error']}$hint');
    }

    // --- yedek: kabuk ---
    final resolve = await ShellTool.runRaw(
      'cmd package resolve-activity --brief -c android.intent.category.LAUNCHER $package '
      '| tail -n 1',
    );
    final component = resolve.stdout.trim();
    if (resolve.ok && component.contains('/') && !component.contains('Error')) {
      final start = await ShellTool.runRaw('am start -n ${_quote(component)}');
      if (start.ok) return ToolResult('$package açıldı ($component).');
    }
    final monkey = await ShellTool.runRaw(
      'monkey -p ${_quote(package)} -c android.intent.category.LAUNCHER 1',
    );
    final combined = '${monkey.stdout}\n${monkey.stderr}';
    if (monkey.ok && !combined.contains('No activities found')) {
      return ToolResult('$package açıldı.');
    }
    return ToolResult.error(
        '$package bulundu ama başlatılamadı. Cihaz kabuk üzerinden uygulama '
        'açmayı reddediyor olabilir. Çıktı: ${combined.trim()}');
  }

  // --------------------------------------------------------------- app_info

  Future<ToolResult> _appInfo(String query) async {
    final resolved = await _resolve(query);
    if (resolved == null) {
      return ToolResult.error('"$query" için kurulu uygulama bulunamadı.');
    }
    final package = resolved['package'] as String;

    final native = await AgentNative.appInfo(package);
    if (native != null && native['ok'] == true) {
      final permissions = (native['permissions'] as List?) ?? const [];
      final buffer = StringBuffer()
        ..writeln('Uygulama: ${native['label']}')
        ..writeln('Paket: $package')
        ..writeln('Sürüm: ${native['version']} (kod ${native['versionCode']})')
        ..writeln(
            'Sistem uygulaması: ${native['system'] == true ? 'evet' : 'hayır'}')
        ..writeln('Etkin: ${native['enabled'] == true ? 'evet' : 'hayır'}')
        ..writeln(
            'Açılabilir: ${native['launchable'] == true ? 'evet' : 'hayır'}')
        ..writeln('Kurulum: ${_epoch(native['firstInstall'])}, '
            'güncelleme: ${_epoch(native['lastUpdate'])}')
        ..writeln('İstediği izinler (${permissions.length}):');
      for (final permission in permissions.take(40)) {
        buffer.writeln('- $permission');
      }
      if (permissions.length > 40) {
        buffer.writeln('… ${permissions.length - 40} izin daha');
      }
      return ToolResult(buffer.toString().trim());
    }

    final run = await ShellTool.runRaw(
      'dumpsys package ${_quote(package)} | '
      "grep -E 'versionName|versionCode|firstInstallTime|lastUpdateTime|"
      "dataDir|targetSdk' | head -n 12",
    );
    if (!run.ok || run.stdout.trim().isEmpty) {
      return ToolResult.error(
          '$package bilgisi okunamadı. ${run.stderr.trim()}');
    }
    return ToolResult('$package:\n${run.stdout.trim()}');
  }

  // ------------------------------------------------------ open_app_settings

  Future<ToolResult> _openAppSettings(String query) async {
    String? package;
    if (query.isNotEmpty) {
      final resolved = await _resolve(query);
      if (resolved == null) {
        return ToolResult.error('"$query" için kurulu uygulama bulunamadı.');
      }
      package = resolved['package'] as String;
    }
    final native = await AgentNative.openAppSettings(package);
    if (native == null) {
      return ToolResult.error(
          'Ayarlar sayfası bu sürümde açılamıyor (native katman yok).');
    }
    return native['ok'] == true
        ? ToolResult(
            'Ayarlar sayfası açıldı${package == null ? '' : ': $package'}.')
        : ToolResult.error('Ayarlar açılamadı: ${native['error']}');
  }

  // ------------------------------------------------------------- install_app

  Future<ToolResult> _installApp(String query) async {
    // Uygulama kurmak kullanıcının kararına bırakılır: mağaza/sayfa açılır,
    // sessiz kurulum denenmez (zaten sistem izni gerektirir).
    final resolved = await _resolve(query);
    final package = (resolved?['package'] as String?) ?? query;

    final launched = await ShellTool.runRaw(
      'am start -a android.intent.action.VIEW '
      '-d ${_quote('market://details?id=$package')} 2>/dev/null',
    );
    if (launched.ok) {
      return ToolResult(
          '$package için mağaza sayfası açıldı. Kurulumu kullanıcı onaylar.');
    }
    final web = await ShellTool.runRaw(
      'am start -a android.intent.action.VIEW '
      '-d ${_quote('https://f-droid.org/packages/$package/')} 2>/dev/null',
    );
    if (web.ok) {
      return ToolResult('$package için F-Droid sayfası açıldı.');
    }
    return ToolResult.error(
        '$package için mağaza açılamadı. Kullanıcıdan uygulamayı elle kurmasını iste.');
  }

  // ------------------------------------------------------------------ termux

  Future<ToolResult> _termux() async {
    final info = await AgentNative.termuxInfo();
    if (info != null) {
      if (info['installed'] != true) {
        return ToolResult(
            'Termux kurulu DEĞİL. device(action="install_app", query="com.termux") '
            'ile mağaza sayfasını açabilirsin; python/git/node gerekiyorsa tek yol bu.');
      }
      final buffer = StringBuffer()
        ..writeln('Termux kurulu: evet')
        ..writeln('Dışarıdan komut kabul ediyor: '
            '${info['externalAppsAllowed'] == true ? 'evet' : 'hayır'}')
        ..writeln('RUN_COMMAND izni: '
            '${info['runCommandPermission'] == true ? 'verilmiş' : 'verilmemiş'}')
        ..writeln('Ölçüm: ${info['message']}');
      if (info['propertiesReadable'] == true) {
        buffer.writeln('termux.properties okundu, satır: ${info['allowLine']}');
      } else {
        buffer.writeln(
            'Not: termux.properties okunamadı (Termux veri klasörü korumalı); '
            '"hayır" görünüyorsa aşağıdaki adımı bir kez uygula.');
      }
      if (info['externalAppsAllowed'] != true) {
        buffer.writeln();
        buffer.writeln('TEK SEFERLİK KURULUM (kullanıcıya aynen göster):');
        final steps = (info['setupSteps'] as List?) ?? const [];
        for (var i = 0; i < steps.length; i++) {
          buffer.writeln('${i + 1}. ${steps[i]}');
        }
        buffer.writeln(
            "Bu ayar yapılmadan Termux'ta hiçbir komut çalıştırılamaz.");
      }
      return ToolResult(buffer.toString().trim());
    }

    // --- yedek: kabuk ---
    final run = await ShellTool.runRaw('pm list packages com.termux');
    final installed = run.stdout.contains('com.termux');
    if (!installed) {
      return ToolResult('Termux kurulu değil (kabuk ölçümü).');
    }
    final probe = await ShellTool.runRaw(
        '/data/data/com.termux/files/usr/bin/bash -c "echo ok"');
    return ToolResult('Termux paketi var. Doğrudan çalıştırma: '
        '${probe.ok ? 'çalışıyor' : 'çalışmıyor (exit ${probe.exitCode}: ${probe.stderr.trim()})'}. '
        'Uygulamanın güncel sürümünde RUN_COMMAND kanalı var mı kontrol et.');
  }

  // -------------------------------------------------------------------- info

  Future<ToolResult> _deviceInfo() async {
    final native = await AgentNative.deviceInfo();
    final buffer = StringBuffer();

    if (native != null) {
      final heap = _asMap(native['javaHeap']) ?? const {};
      buffer
        ..writeln('model: ${native['manufacturer']} ${native['model']}')
        ..writeln('android: ${native['androidVersion']} (SDK ${native['sdk']})')
        ..writeln('uygulama: ${native['package']} ${native['appVersion']}')
        ..writeln('abi: ${(native['abi'] as List?)?.join(', ')}')
        ..writeln('java heap: ${heap['freeMb']}MB boş / ${heap['totalMb']}MB '
            '(üst sınır ${heap['maxMb']}MB)')
        ..writeln('harici depolama boş: '
            '${(native['externalFreeGb'] as num?)?.toStringAsFixed(1)} GB')
        ..writeln('tüm dosyalara erişim: '
            '${native['isExternalStorageManager'] == true ? 'var' : 'yok'}')
        ..writeln('üzerinde çizim: '
            '${native['canDrawOverlays'] == true ? 'var' : 'yok'}')
        ..writeln('uid/pid: ${native['uid']}/${native['pid']}');
    } else {
      // Native katman yok: aynı alanları kabuktan toplamayı dene.
      final model = await ShellTool.runRaw('getprop ro.product.model',
          timeout: const Duration(seconds: 8));
      final manufacturer = await ShellTool.runRaw(
          'getprop ro.product.manufacturer',
          timeout: const Duration(seconds: 8));
      final release = await ShellTool.runRaw('getprop ro.build.version.release',
          timeout: const Duration(seconds: 8));
      buffer
        ..writeln('model: '
                '${manufacturer.stdout.trim()} ${model.stdout.trim()}'
            .trim())
        ..writeln('android: '
            '${release.stdout.trim().isEmpty ? 'okunamadı' : release.stdout.trim()}');
    }

    Future<void> add(String label, String command) async {
      final run =
          await ShellTool.runRaw(command, timeout: const Duration(seconds: 10));
      final value = run.stdout.trim();
      buffer.writeln('$label: ${value.isEmpty ? 'okunamadı' : value}');
    }

    await add('pil',
        'dumpsys battery 2>/dev/null | grep -E "level|status" | tr "\\n" " "');
    await add('çözünürlük', 'wm size 2>/dev/null');
    await add('dil', 'getprop persist.sys.locale');
    buffer.write('ajan çalışma alanı: ${Directory.current.path}');
    return ToolResult(buffer.toString().trim());
  }

  // ---------------------------------------------------------------- helpers

  /// Sorguyu kurulu bir pakete eşler: önce native PackageManager, olmazsa kabuk.
  Future<Map<String, Object?>?> _resolve(String query) async {
    final native = await AgentNative.resolvePackage(query);
    if (native != null && native['ok'] == true && native['package'] is String) {
      return native;
    }

    final all = await ShellTool.runRaw('pm list packages');
    final packages = all.stdout
        .split('\n')
        .map((l) => l.replaceFirst('package:', '').trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final matched = matchPackage(query, packages);
    if (matched == null) return null;
    return {'package': matched, 'label': ''};
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

  static Map<String, Object?>? _asMap(Object? raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static String _epoch(Object? seconds) {
    final value = (seconds as num?)?.toInt();
    if (value == null || value <= 0) return 'bilinmiyor';
    return DateTime.fromMillisecondsSinceEpoch(value * 1000)
        .toIso8601String()
        .substring(0, 10);
  }

  static String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";
}
