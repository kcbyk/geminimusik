import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_music_hub/services/agent/agent_native.dart';
import 'package:ai_music_hub/services/agent/agent_tool_registry.dart';
import 'package:ai_music_hub/services/agent/tools/device_tool.dart';
import 'package:ai_music_hub/services/agent/tools/permissions_tool.dart';
import 'package:ai_music_hub/services/agent/tools/termux_tool.dart';

/// Native kanalı sahte yanıtlarla besler. `null` döndüren bir handler
/// "native katman yok" senaryosunu taklit eder.
void _mockDevice(Object? Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(AgentNative.deviceChannel,
          handler == null ? null : (c) async => handler(c));
}

void _mockTermux(Object? Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(AgentNative.termuxChannel,
          handler == null ? null : (c) async => handler(c));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Araçlar native kanalı yalnızca Android'de çağırıyor; testte taklit ediyoruz.
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    _mockDevice(null);
    _mockTermux(null);
    PermissionsTool.runtimeRequest = null;
  });

  group('cihaz aracı (native PackageManager)', () {
    test('list_apps native listeyi okunur biçimde yazar', () async {
      _mockDevice((call) {
        if (call.method == 'listApps') {
          return {
            'apps': [
              {
                'package': 'com.whatsapp',
                'label': 'WhatsApp',
                'system': false,
                'launchable': true,
                'version': '2.24.1',
                'enabled': true,
              },
              {
                'package': 'com.android.shell',
                'label': 'Kabuk',
                'system': true,
                'launchable': false,
                'version': '14',
                'enabled': true,
              },
            ],
            'count': 2,
            'truncated': false,
            'visibleTotal': 187,
          };
        }
        return null;
      });

      final result = await DeviceTool().invoke({'action': 'list_apps'});

      expect(result.ok, isTrue);
      expect(result.output, contains('WhatsApp  →  com.whatsapp'));
      expect(result.output, contains('sistem'));
      expect(result.output, contains('açılamaz'));
    });

    test('open_app paketi native çözümleyip açar', () async {
      final calls = <String>[];
      _mockDevice((call) {
        calls.add(call.method);
        if (call.method == 'resolvePackage') {
          return {
            'ok': true,
            'package': 'com.spotify.music',
            'label': 'Spotify',
            'candidates': [
              {'package': 'com.spotify.music', 'label': 'Spotify'}
            ],
          };
        }
        if (call.method == 'openApp') {
          return {
            'ok': true,
            'via': 'launchIntent',
            'package': 'com.spotify.music'
          };
        }
        return null;
      });

      final result = await DeviceTool().invoke({
        'action': 'open_app',
        'query': 'spotify',
      });

      expect(result.ok, isTrue);
      expect(result.output, contains('Spotify'));
      expect(result.output, contains('launchIntent'));
      expect(calls, containsAll(<String>['resolvePackage', 'openApp']));
    });

    test('open_app bulunamayınca tahmin yürütmez, listeye yönlendirir',
        () async {
      _mockDevice((call) {
        if (call.method == 'resolvePackage') {
          return {'ok': false, 'error': 'bulunamadı'};
        }
        return null;
      });

      final result = await DeviceTool().invoke({
        'action': 'open_app',
        'query': 'olmayanuygulama',
      });

      expect(result.ok, isFalse);
      expect(result.output, contains('bulunamadı'));
      expect(result.output, contains('list_apps'));
    });

    test('app_info sürüm ve izinleri raporlar', () async {
      _mockDevice((call) {
        if (call.method == 'resolvePackage') {
          return {'ok': true, 'package': 'com.termux', 'label': 'Termux'};
        }
        if (call.method == 'appInfo') {
          return {
            'ok': true,
            'label': 'Termux',
            'version': '0.118.0',
            'versionCode': 118,
            'system': false,
            'enabled': true,
            'launchable': true,
            'firstInstall': 1700000000,
            'lastUpdate': 1700000000,
            'permissions': [
              'android.permission.INTERNET',
              'com.termux.permission.RUN_COMMAND'
            ],
          };
        }
        return null;
      });

      final result = await DeviceTool().invoke({
        'action': 'app_info',
        'query': 'com.termux',
      });

      expect(result.ok, isTrue);
      expect(result.output, contains('0.118.0'));
      expect(result.output, contains('com.termux.permission.RUN_COMMAND'));
    });

    test('native yoksa kabuk yedeğine düşer ve uydurmaz', () async {
      _mockDevice(null);

      final result = await DeviceTool().invoke({
        'action': 'open_app',
        'query': 'com.ornek.yok',
      });

      // Test makinesinde `pm` yok: hata dönmeli, "açıldı" dememeli.
      expect(result.ok, isFalse);
      expect(result.output, isNot(contains('açıldı')));
    });

    test('bilinmeyen eylem hata döner', () async {
      final result = await DeviceTool().invoke({'action': 'uç'});
      expect(result.ok, isFalse);
      expect(result.output, contains('Bilinmeyen eylem'));
    });
  });

  group('termux aracı (native RUN_COMMAND)', () {
    Map<String, Object?> kuruluTermux({bool allowed = false}) => {
          'installed': true,
          'externalAppsAllowed': allowed,
          'propertiesReadable': false,
          'runCommandPermission': true,
          'prefixExists': false,
          'message': allowed
              ? 'Termux hazır: dışarıdan komut kabul ediyor.'
              : 'Termux kurulu ama dış uygulamalardan komut kabul etmiyor.',
          'setupSteps': [
            'Termux\'u aç ve şu komutu çalıştır: mkdir -p ~/.termux && '
                'echo "allow-external-apps=true" >> ~/.termux/termux.properties',
            'Ardından: termux-reload-settings',
          ],
        };

    test('probe kurulu Termux\'u kurulu olarak bildirir', () async {
      _mockDevice((call) =>
          call.method == 'termuxInfo' ? kuruluTermux(allowed: true) : null);

      final result = await TermuxTool().invoke({'action': 'probe'});

      expect(result.ok, isTrue);
      expect(result.output, contains('- kurulu: evet'));
      expect(result.output, contains('dışarıdan komut kabul ediyor: evet'));
    });

    test('izin verilmemişse tek seferlik kurulumu adım adım verir', () async {
      _mockDevice((call) =>
          call.method == 'termuxInfo' ? kuruluTermux(allowed: false) : null);

      final result = await TermuxTool().invoke({'action': 'probe'});

      expect(result.output, contains('allow-external-apps=true'));
      expect(result.output, contains('termux-reload-settings'));
      expect(result.output, contains('TERMUX TEK SEFERLİK AYAR'));
    });

    test('run komutu Termux\'a devreder ve çıktıyı geri getirir', () async {
      _mockDevice((call) =>
          call.method == 'termuxInfo' ? kuruluTermux(allowed: true) : null);
      _mockTermux((call) {
        if (call.method == 'run') {
          return {
            'ok': true,
            'exitCode': 0,
            'timedOut': false,
            'stdout': 'Python 3.12.1\n',
            'stderr': '',
            'elapsedMs': 84,
          };
        }
        return null;
      });

      final result = await TermuxTool()
          .invoke({'action': 'run', 'command': 'python --version'});

      expect(result.ok, isTrue);
      expect(result.output, contains('exit_code: 0'));
      expect(result.output, contains('Python 3.12.1'));
      expect(result.output, contains('termux RUN_COMMAND'));
    });

    test('run başarısızsa ve ayar kapalıysa kurulumu söyler', () async {
      _mockDevice((call) =>
          call.method == 'termuxInfo' ? kuruluTermux(allowed: false) : null);
      _mockTermux((call) {
        if (call.method == 'run') {
          return {
            'ok': false,
            'exitCode': 1,
            'timedOut': false,
            'stdout': '',
            'stderr': 'permission denied',
            'elapsedMs': 12,
          };
        }
        return null;
      });

      final result = await TermuxTool()
          .invoke({'action': 'run', 'command': 'python --version'});

      expect(result.ok, isFalse);
      expect(result.output, contains('allow-external-apps=true'));
    });

    test('Termux kurulu değilse kurulum yolunu gösterir', () async {
      _mockDevice((call) => call.method == 'termuxInfo'
          ? {
              'installed': false,
              'externalAppsAllowed': false,
              'message': 'kurulu değil'
            }
          : null);

      final result = await TermuxTool().invoke({'action': 'probe'});

      expect(result.output, contains('- kurulu: hayır'));
      expect(result.output, contains('install_app'));
    });

    test('setup izin zaten açıksa gereksiz adım çıkarmaz', () async {
      _mockDevice((call) =>
          call.method == 'termuxInfo' ? kuruluTermux(allowed: true) : null);

      final result = await TermuxTool().invoke({'action': 'setup'});

      expect(result.ok, isTrue);
      expect(result.output, contains('Zaten hazır'));
    });
  });

  group('izin aracı', () {
    test('status native ölçümü Türkçe raporlar', () async {
      _mockDevice((call) => call.method == 'permissionStatus'
          ? {'storage': 'granted', 'microphone': 'denied'}
          : null);

      final granted = await PermissionsTool()
          .invoke({'action': 'status', 'permission': 'storage'});
      final denied = await PermissionsTool()
          .invoke({'action': 'status', 'permission': 'microphone'});

      expect(granted.output, contains('verilmiş'));
      expect(denied.output, contains('verilmemiş'));
    });

    test('request çalışma zamanı iznini isteyip sonucu söyler', () async {
      _mockDevice((call) =>
          call.method == 'permissionStatus' ? {'camera': 'denied'} : null);
      PermissionsTool.runtimeRequest =
          (permission) async => permission == 'camera';

      final result = await PermissionsTool()
          .invoke({'action': 'request', 'permission': 'camera'});

      expect(result.ok, isTrue);
      expect(result.output, contains('verildi'));
    });

    test('izin reddedilirse Ayarlar yolunu gösterir', () async {
      _mockDevice((call) =>
          call.method == 'permissionStatus' ? {'camera': 'denied'} : null);
      PermissionsTool.runtimeRequest = (_) async => false;

      final result = await PermissionsTool()
          .invoke({'action': 'request', 'permission': 'camera'});

      expect(result.ok, isFalse);
      expect(result.output, contains('open_settings'));
    });

    test('Ayarlardan verilen izinler doğrudan ekran açar', () async {
      var opened = '';
      _mockDevice((call) {
        if (call.method == 'openPermissionSettings') {
          opened = '${call.arguments['permission']}';
          return {'ok': true};
        }
        return null;
      });

      final result = await PermissionsTool()
          .invoke({'action': 'request', 'permission': 'allFiles'});

      expect(opened, 'allFiles');
      expect(result.ok, isTrue);
      expect(result.output, contains('ayar ekranı açıldı'));
    });

    test('bilinmeyen izin ve eylem hata döner', () async {
      expect(
          (await PermissionsTool()
                  .invoke({'action': 'status', 'permission': 'uçanhalı'}))
              .ok,
          isFalse);
      expect(
          (await PermissionsTool()
                  .invoke({'action': 'ver', 'permission': 'camera'}))
              .ok,
          isFalse);
    });

    test('izin istemek onaya bağlıdır', () {
      expect(PermissionsTool().requiresApproval, isTrue);
    });
  });

  group('araç setleri', () {
    test('permissions üç sette de var', () {
      for (final registry in [
        AgentToolRegistryBuilder.full(),
        AgentToolRegistryBuilder.voice(),
        AgentToolRegistryBuilder.developer(),
      ]) {
        expect(registry.tools.map((t) => t.name), contains('permissions'));
      }
      // device yalnızca tam ve ses setinde: geliştirici seti dosya/kabuk odaklı.
      expect(AgentToolRegistryBuilder.full().tools.map((t) => t.name),
          contains('device'));
      expect(AgentToolRegistryBuilder.voice().tools.map((t) => t.name),
          contains('device'));
    });

    test('ses setinde kabuk/dosya araçları yok', () {
      final voice =
          AgentToolRegistryBuilder.voice().tools.map((t) => t.name).toList();
      expect(voice, isNot(contains('shell')));
      expect(voice, isNot(contains('write_file')));
    });
  });
}
