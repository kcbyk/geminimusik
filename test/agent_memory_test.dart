import 'package:flutter_test/flutter_test.dart';
import 'package:ai_music_hub/services/agent/agent_loop.dart';
import 'package:ai_music_hub/services/agent/agent_memory.dart';
import 'package:ai_music_hub/services/agent/agent_models.dart';
import 'package:ai_music_hub/services/agent/turn_model.dart';
import 'package:ai_music_hub/services/agent/tools/memory_tool.dart';

/// Testlerde SharedPreferences'a dokunmadan çalışan basit depo.
class _TestStore implements AgentMemoryStore {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

void main() {
  late _TestStore store;
  late AgentMemory memory;

  setUp(() {
    store = _TestStore();
    memory = AgentMemory(store: store);
  });

  group('görev günlüğü', () {
    test('görev kaydedilir ve bir sonraki görevde bağlama girer', () async {
      await memory.rememberTurn(
        task: 'notlar klasörü oluştur',
        answer: 'notlar/ klasörünü oluşturdum ve doğruladım.',
        toolsUsed: const ['shell', 'list_dir'],
      );

      final context = memory.buildContextBlock();
      expect(context, contains('[ONCEKI_GOREVLER]'));
      expect(context, contains('notlar klasörü oluştur'));
      expect(context, contains('doğruladım'));
      expect(context, contains('shell'));
      expect(memory.turnCount, 1);
    });

    test('kalıcı olarak saklanır: yeni örnek aynı veriyi okur', () async {
      await memory.rememberTurn(task: 'pil durumuna bak', answer: 'yüzde 42');

      final reopened = AgentMemory(store: store);
      await reopened.load();

      expect(reopened.turnCount, 1);
      expect(reopened.buildContextBlock(), contains('yüzde 42'));
    });

    test('maxTurns aşılınca en eski görevler düşer', () async {
      final small = AgentMemory(store: store, maxTurns: 3);
      for (var i = 1; i <= 5; i++) {
        await small.rememberTurn(task: 'görev $i', answer: 'sonuç $i');
      }

      expect(small.turnCount, 3);
      final context = small.buildContextBlock();
      expect(context, isNot(contains('görev 1')));
      expect(context, contains('görev 5'));
    });

    test('çok uzun yanıt kısaltılır', () async {
      await memory.rememberTurn(
          task: 'uzun görev', answer: List.filled(5000, 'a').join());

      final answer = memory.turns.single.answer;
      expect(answer.length, lessThan(AgentMemory.maxAnswerChars + 32));
      expect(memory.buildContextBlock(), contains('…'));
    });

    test('hiç geçmiş yokken boş bağlam döner', () {
      expect(memory.buildContextBlock(), isEmpty);
      expect(memory.turnCount, 0);
    });

    test('geçmiş sıfırlanabilir', () async {
      await memory.rememberTurn(task: 'x', answer: 'y');
      await memory.clearHistory();

      expect(memory.turnCount, 0);
      expect(memory.buildContextBlock(), isEmpty);
    });

    test('kayıt zamanı ve araç listesi saklanır', () async {
      await memory.rememberTurn(
        task: 't',
        answer: 'a',
        toolsUsed: const ['shell', 'shell', 'read_file'],
      );

      final turn = memory.turns.single;
      expect(turn.task, 't');
      expect(turn.answer, 'a');
      expect(turn.toolsUsed, ['shell', 'read_file']);
    });
  });

  group('kalıcı notlar', () {
    test('ekleme, listeleme, sıfırlama', () async {
      final tool = MemoryTool(memory: memory);

      final empty = await tool.invoke({'action': 'list'});
      expect(empty.output, contains('Henüz kalıcı not yok'));

      final added = await tool.invoke({
        'action': 'add',
        'text': 'Kullanıcı dosyaları /sdcard/Notlar altında istiyor.',
      });
      expect(added.ok, isTrue);
      expect(memory.hasNotes, isTrue);

      final listed = await tool.invoke({'action': 'list'});
      expect(listed.output, contains('/sdcard/Notlar'));

      final cleared = await tool.invoke({'action': 'clear'});
      expect(cleared.ok, isTrue);
      expect(memory.hasNotes, isFalse);
    });

    test('boş not eklenmez', () async {
      final tool = MemoryTool(memory: memory);
      final result = await tool.invoke({'action': 'add', 'text': '   '});

      expect(result.ok, isFalse);
      expect(memory.hasNotes, isFalse);
    });

    test('bilinmeyen eylem hata döner', () async {
      final tool = MemoryTool(memory: memory);
      final result = await tool.invoke({'action': 'uç'});

      expect(result.ok, isFalse);
    });

    test('notlar bağlam bloğunda görünür', () async {
      await memory.addNote('Her zaman Türkçe yanıt ver.');

      final context = memory.buildContextBlock();
      expect(context, contains('[KALICI_HAFIZA_NOTLARIN]'));
      expect(context, contains('Türkçe'));
    });

    test('notlar kalıcıdır', () async {
      await memory.addNote('kalıcı bilgi');

      final reopened = AgentMemory(store: store);
      await reopened.load();

      expect(reopened.hasNotes, isTrue);
      expect(reopened.notes, contains('kalıcı bilgi'));
    });

    test('geçmiş ve notlar birlikte bağlama girer', () async {
      await memory.addNote('not');
      await memory.rememberTurn(task: 'görev', answer: 'yanıt');

      final context = memory.buildContextBlock();
      expect(context, contains('[KALICI_HAFIZA_NOTLARIN]'));
      expect(context, contains('[ONCEKI_GOREVLER]'));
    });

    test('bağlam bloğu üst sınırı aşmaz', () async {
      for (var i = 0; i < 20; i++) {
        await memory.rememberTurn(
            task: 'görev $i', answer: List.filled(1000, 'b').join());
      }

      expect(memory.buildContextBlock().length,
          lessThan(AgentMemory.maxContextChars + 2000));
    });
  });

  group('döngü entegrasyonu', () {
    test('görev bitince hafızaya yazılır', () async {
      final loop = AgentLoop(
        model: (contents, prompt) async => const ModelTurn(text: 'tamamdır'),
        registry: AgentToolRegistry()..register(_NoopTool()),
        memory: memory,
      );

      await loop.run('diski kontrol et');

      expect(memory.turnCount, 1);
      expect(memory.turns.single.task, 'diski kontrol et');
      expect(memory.turns.single.answer, 'tamamdır');
    });

    test('kullanılan araçlar kaydedilir', () async {
      final loop = AgentLoop(
        model: (contents, prompt) async {
          if (contents.length == 1) {
            return const ModelTurn(
              text: '',
              calls: [
                ModelFunctionCall(
                    id: '1', name: 'noop', args: <String, dynamic>{}),
              ],
            );
          }
          return const ModelTurn(text: 'bitti');
        },
        registry: AgentToolRegistry()..register(_NoopTool()),
        memory: memory,
      );

      await loop.run('bir şey yap');

      expect(memory.turns.single.toolsUsed, contains('noop'));
    });

    test('hafıza olmadan da döngü çalışır', () async {
      final loop = AgentLoop(
        model: (contents, prompt) async => const ModelTurn(text: 'bitti'),
        registry: AgentToolRegistry()..register(_NoopTool()),
      );

      final result = await loop.run('görev');
      expect(result.answer, 'bitti');
    });

    test('model son tur metnini iki kez üretmez (tek SONUÇ kartı)', () async {
      final events = <AgentEvent>[];
      final loop = AgentLoop(
        model: (contents, prompt) async =>
            const ModelTurn(text: 'görev tamamlandı'),
        registry: AgentToolRegistry()..register(_NoopTool()),
        onEvent: events.add,
      );

      final result = await loop.run('bir şey yap');

      expect(result.answer, 'görev tamamlandı');
      // Metin hem "AJAN" kartı hem "SONUÇ" kartı olarak yayınlanmamalı.
      expect(events.where((e) => e.type == AgentEventType.modelText), isEmpty);
      expect(events.where((e) => e.type == AgentEventType.done), hasLength(1));
    });
  });
}

class _NoopTool extends AgentTool {
  @override
  String get name => 'noop';

  @override
  String get description => 'test aracı';

  @override
  Map<String, dynamic> get parameters =>
      const {'type': 'OBJECT', 'properties': <String, dynamic>{}};

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async =>
      const ToolResult('ok');
}
