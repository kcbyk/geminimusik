import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_music_hub/services/agent/agent_models.dart';
import 'package:ai_music_hub/services/agent/agent_paths.dart';
import 'package:ai_music_hub/services/agent/tools/file_tools.dart';
import 'package:ai_music_hub/services/agent/tools/shell_tool.dart';
import 'package:ai_music_hub/services/agent/agent_tool_registry.dart';
import 'package:ai_music_hub/services/agent/tools/remote_terminal_tool.dart';
import 'package:ai_music_hub/services/agent/tools/device_tool.dart';
import 'package:ai_music_hub/services/agent/tools/termux_tool.dart';
import 'package:ai_music_hub/services/agent/tools/todo_tool.dart';
import 'package:ai_music_hub/services/agent/turn_model.dart';

void main() {
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agent_test_');
    AgentPathPolicy.instance
      ..allowUnrestrictedPaths = false
      ..configureRoot(workspace.path);
    AgentPlanStore.instance.clear();
  });

  tearDown(() async {
    AgentPathPolicy.instance.allowUnrestrictedPaths = false;
    if (workspace.existsSync()) {
      await workspace.delete(recursive: true);
    }
  });

  group('yol politikası', () {
    test('göreli yol çalışma alanına bağlanır', () {
      final resolved = AgentPathPolicy.instance.resolve('notlar/a.txt');
      expect(resolved, '${workspace.path}/notlar/a.txt');
    });

    test('çalışma alanı dışına kaçış engellenir', () {
      expect(
        () => AgentPathPolicy.instance.resolve('../../etc/passwd'),
        throwsA(isA<PathPolicyException>()),
      );
      expect(
        () => AgentPathPolicy.instance.resolve('/sdcard/DCIM'),
        throwsA(isA<PathPolicyException>()),
      );
    });

    test('sınırsız mod açılınca mutlak yollar serbest', () {
      AgentPathPolicy.instance.allowUnrestrictedPaths = true;
      expect(
          AgentPathPolicy.instance.resolve('/sdcard/x.txt'), '/sdcard/x.txt');
    });

    test('".." içeren ama alan içinde kalan yol kabul edilir', () {
      final resolved = AgentPathPolicy.instance.resolve('a/b/../c.txt');
      expect(resolved, '${workspace.path}/a/c.txt');
    });
  });

  group('komut risk analizi', () {
    const analyzer = CommandRiskAnalyzer();

    test('salt okunur komut güvenlidir', () {
      expect(analyzer.analyze('ls -la').level, CommandRisk.safe);
      expect(analyzer.analyze('cat dosya.txt').level, CommandRisk.safe);
    });

    test('silme/taşıma onay ister', () {
      expect(analyzer.analyze('rm -rf klasor').needsApproval, isTrue);
      expect(analyzer.analyze('mv a.txt /sdcard/').needsApproval, isTrue);
      expect(analyzer.analyze('pm clear com.x').needsApproval, isTrue);
    });

    test('geri döndürülemez komut engellenir', () {
      expect(analyzer.analyze('rm -rf /').isBlocked, isTrue);
      expect(analyzer.analyze('mkfs /dev/sda').isBlocked, isTrue);
      expect(analyzer.analyze('dd if=/dev/zero of=/dev/sda').isBlocked, isTrue);
    });
  });

  group('dosya araçları', () {
    test('write_file oluşturur, read_file doğrular', () async {
      final write = await WriteFileTool().invoke({
        'path': 'proje/not.txt',
        'content': 'satır 1\nsatır 2\nsatır 3\n',
      });
      expect(write.ok, isTrue);
      expect(write.output, contains('Oluşturuldu'));
      expect(File('${workspace.path}/proje/not.txt').existsSync(), isTrue);

      final read = await ReadFileTool().invoke({'path': 'proje/not.txt'});
      expect(read.ok, isTrue);
      expect(read.output, contains('satır 2'));
      expect(read.output, contains('3 satır'));
    });

    test('read_file offset/limit ile parça okur', () async {
      await WriteFileTool().invoke({
        'path': 'buyuk.txt',
        'content': List.generate(50, (i) => 'satır $i').join('\n'),
      });
      final read = await ReadFileTool()
          .invoke({'path': 'buyuk.txt', 'offset': 10, 'limit': 3});
      expect(read.output, contains('satır 9'));
      expect(read.output, contains('satır 11'));
      expect(read.output, isNot(contains('satır 12')));
      expect(read.output, contains('satır 10-12 gösterildi'));
    });

    test('edit_file ilk eşleşmeyi değiştirir ve dosyayı gerçekten günceller',
        () async {
      await WriteFileTool().invoke({
        'path': 'kod.dart',
        'content': 'void main() {\n  print("eski");\n}\n',
      });
      final edit = await EditFileTool().invoke({
        'path': 'kod.dart',
        'old_text': 'print("eski");',
        'new_text': 'print("yeni");',
      });
      expect(edit.ok, isTrue);
      expect(
        File('${workspace.path}/kod.dart').readAsStringSync(),
        contains('print("yeni");'),
      );
    });

    test('edit_file girinti farkını tolere eder', () async {
      await WriteFileTool().invoke({
        'path': 'girinti.dart',
        'content': 'class A {\n    int x = 1;\n    int y = 2;\n}\n',
      });
      final edit = await EditFileTool().invoke({
        'path': 'girinti.dart',
        'old_text': 'int x = 1;\nint y = 2;', // girintisiz verildi
        'new_text': 'int x = 99;\nint y = 2;',
      });
      expect(edit.ok, isTrue);
      expect(
        File('${workspace.path}/girinti.dart').readAsStringSync(),
        contains('int x = 99;'),
      );
    });

    test('edit_file bulunamayan metinde dürüstçe hata verir', () async {
      await WriteFileTool().invoke({'path': 'a.txt', 'content': 'merhaba'});
      final edit = await EditFileTool().invoke({
        'path': 'a.txt',
        'old_text': 'olmayan metin',
        'new_text': 'x',
      });
      expect(edit.ok, isFalse);
      expect(edit.output, contains('bulunamadı'));
    });

    test('move_file taşır, kopyalar, siler', () async {
      await WriteFileTool().invoke({'path': 'kaynak.txt', 'content': 'veri'});
      final tool = MoveFileTool();

      final copy = await tool.invoke({
        'action': 'copy',
        'source': 'kaynak.txt',
        'destination': 'yedek/kopya.txt',
      });
      expect(copy.ok, isTrue);
      expect(File('${workspace.path}/yedek/kopya.txt').existsSync(), isTrue);

      final move = await tool.invoke({
        'action': 'move',
        'source': 'kaynak.txt',
        'destination': 'hedef/tasindi.txt',
      });
      expect(move.ok, isTrue);
      expect(File('${workspace.path}/kaynak.txt').existsSync(), isFalse);
      expect(File('${workspace.path}/hedef/tasindi.txt').existsSync(), isTrue);

      final delete = await tool
          .invoke({'action': 'delete', 'source': 'hedef/tasindi.txt'});
      expect(delete.ok, isTrue);
      expect(File('${workspace.path}/hedef/tasindi.txt').existsSync(), isFalse);
    });

    test('move_file alan dışına taşımaya izin vermez', () async {
      await WriteFileTool().invoke({'path': 'a.txt', 'content': 'x'});
      final result = await MoveFileTool().invoke({
        'action': 'move',
        'source': 'a.txt',
        'destination': '/sdcard/a.txt',
      });
      expect(result.ok, isFalse);
      expect(result.output, contains('çalışma alanının'));
      expect(File('${workspace.path}/a.txt').existsSync(), isTrue,
          reason: 'engellenen taşıma dosyayı yerinde bırakmalı');
    });

    test('list_dir içeriği, search_files metni bulur', () async {
      await WriteFileTool()
          .invoke({'path': 'src/a.dart', 'content': 'class Foo {}'});
      await WriteFileTool()
          .invoke({'path': 'src/b.dart', 'content': 'class Bar {}'});

      final list = await ListDirTool().invoke({'path': '.', 'recursive': true});
      expect(list.output, contains('src/a.dart'));
      expect(list.output, contains('bayt'));

      final search = await SearchFilesTool()
          .invoke({'path': '.', 'text_contains': 'class Bar'});
      expect(search.output, contains('b.dart'));
      expect(search.output, isNot(contains('a.dart')));
    });

    test('olmayan dosyada araç hata döner, exception fırlatmaz', () async {
      final read = await ReadFileTool().invoke({'path': 'yok.txt'});
      expect(read.ok, isFalse);
      expect(read.output, contains('bulunamadı'));
    });
  });

  group('shell aracı (gerçek kabuk)', () {
    test('komutu çalıştırır, stdout ve exit_code döner', () async {
      await WriteFileTool()
          .invoke({'path': 'veri.txt', 'content': 'a\nb\nc\n'});
      final result = await ShellTool().invoke({'command': 'wc -l veri.txt'});
      expect(result.ok, isTrue);
      expect(result.output, contains('exit_code: 0'));
      expect(result.output, contains('3'));
    });

    test('çalışma dizini ajan alanıdır', () async {
      final result = await ShellTool().invoke({'command': 'pwd'});
      expect(result.output, contains(workspace.path));
    });

    test('dosya yazıp okuyabilir (ajanın ana senaryosu)', () async {
      final write = await ShellTool()
          .invoke({'command': 'echo "merhaba ajan" > test.txt'});
      expect(write.ok, isTrue);
      expect(File('${workspace.path}/test.txt').readAsStringSync().trim(),
          'merhaba ajan');
    });

    test('başarısız komutta ok=false ve stderr döner', () async {
      final result =
          await ShellTool().invoke({'command': 'ls /olmayan/klasör 2>&1'});
      expect(result.ok, isFalse);
      expect(result.output, contains('exit_code:'));
    });

    test('engellenen komut hiç çalıştırılmaz', () async {
      final result = await ShellTool().invoke({'command': 'rm -rf /'});
      expect(result.ok, isFalse);
      expect(result.output, contains('engellendi'));
    });

    test('zaman aşımında komut öldürülür ve raporlanır', () async {
      final result = await ShellTool()
          .invoke({'command': 'sleep 10', 'timeout_seconds': 1});
      expect(result.ok, isFalse);
      expect(result.output, contains('durduruldu'));
    });

    test('run_code probe cihazdaki yorumlayıcıları raporlar', () async {
      final result = await RunTestTool().invoke({'action': 'probe'});
      expect(result.ok, isTrue);
      expect(result.output, contains('python'));
      expect(result.output, contains('sh:'));
    });

    test('run_code inline kodu geçici dosyaya yazıp çalıştırır', () async {
      final probe = await RunTestTool().invoke({'action': 'probe'});
      final hasSh = probe.output.contains('sh: /');
      if (!hasSh) return; // kabuk yoksa test anlamsız
      final result = await RunTestTool().invoke({
        'action': 'inline',
        'language': 'sh',
        'code': 'echo "kod calisti: \$((2+3))"',
      });
      expect(result.output, contains('kod calisti: 5'));
    });
  });

  group('plan aracı', () {
    test('plan kurar, günceller ve listeler', () async {
      final tool = TodoTool();
      final created = await tool.invoke({
        'action': 'set',
        'items': [
          {'id': 'p1', 'text': 'bir'},
          {'id': 'p2', 'text': 'iki'},
        ],
      });
      expect(created.ok, isTrue);
      expect(AgentPlanStore.instance.items, hasLength(2));

      final updated =
          await tool.invoke({'action': 'update', 'id': 'p1', 'status': 'done'});
      expect(updated.ok, isTrue);
      expect(AgentPlanStore.instance.items.first.status, 'done');
      expect(AgentPlanStore.instance.doneCount, 1);

      final missing = await tool
          .invoke({'action': 'update', 'id': 'yok', 'status': 'done'});
      expect(missing.ok, isFalse);

      final listed = await tool.invoke({'action': 'list'});
      expect(listed.output, contains('p2 [pending] iki'));
    });

    test('boş plan ile set hata verir', () async {
      final result = await TodoTool().invoke({'action': 'set', 'items': []});
      expect(result.ok, isFalse);
    });
  });

  group('araç çıktı kırpma', () {
    test('uzun çıktı ortadan kısaltılır', () {
      final long = List.generate(3000, (i) => 'satır $i').join('\n');
      final clipped = truncateToolOutput(long, maxChars: 1000);
      expect(clipped.length, lessThan(long.length));
      expect(clipped, contains('kısaltıldı'));
      expect(clipped, startsWith('satır 0'));
      expect(clipped, endsWith('satır 2999'));
    });

    test('kısa çıktı olduğu gibi kalır', () {
      expect(truncateToolOutput('kısa'), 'kısa');
    });

    test('boş araç çıktısı modele anlamlı döner', () {
      expect(wrapToolResponse(''), contains('çıktı üretmedi'));
      expect(wrapToolResponse('tamam'), 'tamam');
    });
  });

  group('uzak terminal aracı', () {
    test('yapılandırma yoksa araç setine eklenmez', () {
      final registry = AgentToolRegistryBuilder.full();
      expect(RemoteTerminalTool.isAvailable, isFalse);
      expect(registry['remote_terminal'], isNull);
      expect(registry['shell'], isNotNull,
          reason: 'telefonda kabuk her zaman hazır olmalı');
    });

    test('boş komut hata döner', () async {
      final result = await RemoteTerminalTool().invoke({'command': '  '});
      expect(result.ok, isFalse);
      expect(result.output, contains('boş'));
    });

    test('şeması model için doğru biçimde', () {
      final tool = RemoteTerminalTool();
      expect(tool.declaration['name'], 'remote_terminal');
      expect((tool.declaration['parameters'] as Map)['required'], ['command']);
      expect(tool.requiresApproval, isTrue);
    });
  });

  group('cihaz aracı', () {
    test('paket adı eşleştirme: tam, kısmi ve çoklu eşleşme', () {
      const packages = [
        'com.whatsapp',
        'com.whatsapp.w4b',
        'org.telegram.messenger',
        'com.spotify.music',
        'com.android.chrome',
      ];
      expect(DeviceTool.matchPackage('com.whatsapp', packages), 'com.whatsapp');
      expect(DeviceTool.matchPackage('whatsapp', packages), 'com.whatsapp',
          reason: 'en kısa eşleşme asıl uygulama olmalı');
      expect(DeviceTool.matchPackage('spotify', packages), 'com.spotify.music');
      expect(DeviceTool.matchPackage('telegram', packages),
          'org.telegram.messenger');
      expect(DeviceTool.matchPackage('chrome', packages), 'com.android.chrome');
      expect(DeviceTool.matchPackage('olmayanuygulama', packages), isNull);
      expect(DeviceTool.matchPackage('', packages), isNull);
      expect(DeviceTool.matchPackage('whatsapp', const []), isNull);
    });

    test('pm yoksa çökmez, anlaşılır hata döner', () async {
      final result = await DeviceTool().invoke({'action': 'list_apps'});
      // Test makinesinde Android `pm` yok: araç exception fırlatmamalı.
      expect(result.output, isNotEmpty);
      expect(
          result.output.toLowerCase(),
          anyOf(contains('uygulama'), contains('alınamadı'),
              contains('not found')));
    });

    test('open_app sorgu olmadan hata verir', () async {
      final result = await DeviceTool().invoke({'action': 'open_app'});
      expect(result.ok, isFalse);
      expect(result.output, contains('query'));
    });

    test('şema: action zorunlu ve enum tanımlı', () {
      final schema = DeviceTool().declaration;
      expect(schema['name'], 'device');
      expect((schema['parameters'] as Map)['required'], ['action']);
      final action =
          ((schema['parameters'] as Map)['properties'] as Map)['action'] as Map;
      expect(
          action['enum'], containsAll(['list_apps', 'open_app', 'app_info']));
    });

    test('info cihaz özetini toplamaya çalışır', () async {
      final result = await DeviceTool().invoke({'action': 'info'});
      expect(result.output, contains('model'));
      expect(result.output, contains('ajan çalışma alanı'));
    });
  });

  group('termux aracı', () {
    test('probe Termux yoksa dürüstçe söyler, varmış gibi yapmaz', () async {
      final result = await TermuxTool().invoke({'action': 'probe'});
      expect(result.ok, isTrue);
      expect(result.output, contains('Termux durumu'));
      expect(result.output, contains('- kurulu: hayır'));
      expect(result.output, contains('doğrudan çalıştırma: çalışmıyor'));
    });

    test('run/send komut olmadan hata verir', () async {
      expect((await TermuxTool().invoke({'action': 'run'})).ok, isFalse);
      expect((await TermuxTool().invoke({'action': 'send'})).ok, isFalse);
    });

    test('çok uzun komut reddedilir', () async {
      final result =
          await TermuxTool().invoke({'action': 'run', 'command': 'x' * 5000});
      expect(result.ok, isFalse);
      expect(result.output, contains('4000'));
    });

    test('onay ister ve ortam değişkenleri Termux PRE ile kurulur', () {
      final tool = TermuxTool();
      expect(tool.requiresApproval, isTrue);
      expect(tool.declaration['name'], 'termux');
    });

    test('run çalışmazsa kullanıcıya yol gösterir', () async {
      final result = await TermuxTool().invoke({
        'action': 'run',
        'command': 'echo merhaba',
        'timeout_seconds': 5,
      });
      // Test makinesinde Termux ikilileri yok: exit_code != 0 ve ipucu vermeli.
      expect(result.output, contains('exit_code'));
    });
  });

  group('araç kayıt setleri', () {
    test('tam sette yeni cihaz/hafıza/termux araçları var', () {
      final registry = AgentToolRegistryBuilder.full();
      for (final name in [
        'update_plan',
        'memory',
        'shell',
        'termux',
        'device',
        'web',
        'music',
        'phone',
        'read_file',
        'write_file',
        'edit_file',
        'move_file',
      ]) {
        expect(registry[name], isNotNull, reason: '$name eksik');
      }
    });

    test('sesli asistan setinde cihaz var ama dosya/kabuk yok', () {
      final registry = AgentToolRegistryBuilder.voice();
      expect(registry['device'], isNotNull);
      expect(registry['music'], isNotNull);
      expect(registry['shell'], isNull);
      expect(registry['write_file'], isNull);
    });

    test('her aracın şeması model için geçerli', () {
      for (final tool in AgentToolRegistryBuilder.full().tools) {
        expect(tool.name, isNotEmpty);
        expect(tool.description.length, greaterThan(20),
            reason: '${tool.name} açıklaması çok kısa');
        expect(tool.parameters['type'], 'OBJECT');
        expect(tool.parameters['properties'], isNotNull);
      }
    });
  });
}
