import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_music_hub/services/agent/agent_loop.dart';
import 'package:ai_music_hub/services/agent/agent_models.dart';
import 'package:ai_music_hub/services/agent/turn_model.dart';
import 'package:ai_music_hub/services/agent/tools/todo_tool.dart';

/// Kayıtlı turları sırayla döndüren sahte model.
class ScriptedModel {
  ScriptedModel(this.turns);

  final List<ModelTurn> turns;
  final List<List<TurnContent>> seen = [];
  int callCount = 0;

  Future<ModelTurn> call(
      List<TurnContent> contents, String systemPrompt) async {
    seen.add(List.of(contents));
    final index = callCount.clamp(0, turns.length - 1);
    callCount++;
    return turns[index];
  }
}

/// Çağrıları kaydeden sahte araç.
class RecordingTool extends AgentTool {
  RecordingTool(this.name);

  @override
  final String name;
  bool requiresApprovalFlag = false;
  final List<Map<String, dynamic>> calls = [];
  String output = 'araç çalıştı';
  bool ok = true;
  bool throwOnInvoke = false;

  @override
  String get description => 'test aracı: $name';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'command': {'type': 'STRING'},
        },
      };

  @override
  bool get requiresApproval => requiresApprovalFlag;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    calls.add(Map<String, dynamic>.from(args));
    if (throwOnInvoke) throw StateError('araç patladı');
    return ToolResult(output, ok: ok);
  }
}

ModelTurn callTurn(String name, Map<String, dynamic> args,
        {String id = 'c1'}) =>
    ModelTurn(calls: [ModelFunctionCall(id: id, name: name, args: args)]);

const ModelTurn textTurn = ModelTurn(text: 'görev bitti');

void main() {
  late AgentToolRegistry registry;
  late RecordingTool tool;

  setUp(() {
    tool = RecordingTool('shell_probe');
    registry = AgentToolRegistry()..register(tool);
    AgentPlanStore.instance.clear();
  });

  test('model aracı çağırır, çıktı modele geri döner ve final yanıt alınır',
      () async {
    final model = ScriptedModel([
      callTurn('shell_probe', {'command': 'ls'}),
      textTurn,
    ]);
    final events = <AgentEvent>[];
    final loop = AgentLoop(
      model: model.call,
      registry: registry,
      onEvent: events.add,
    );

    final result = await loop.run('klasörü listele');

    expect(result.answer, 'görev bitti');
    expect(result.cancelled, isFalse);
    expect(tool.calls, hasLength(1));
    expect(tool.calls.single['command'], 'ls');
    expect(result.steps, hasLength(1));
    expect(result.steps.single.status, AgentStepStatus.done);
    expect(result.steps.single.result, contains('araç çalıştı'));

    // 2. turda modele functionResponse gerçekten gönderilmiş mi?
    expect(model.callCount, 2);
    final secondTurn = model.seen[1];
    expect(secondTurn, hasLength(3)); // user task + model call + user response
    final responsePart = secondTurn.last.parts.single as Map<String, dynamic>;
    expect(responsePart.containsKey('functionResponse'), isTrue);
    final payload = responsePart['functionResponse'] as Map<String, dynamic>;
    expect(payload['name'], 'shell_probe');
    expect(payload['id'], 'c1');
    expect((payload['response'] as Map)['output'], contains('araç çalıştı'));
    expect((payload['response'] as Map)['ok'], isTrue);

    // Olay akışı: task -> step(running) -> step(done) -> done
    expect(events.first.type, AgentEventType.task);
    expect(events.last.type, AgentEventType.done);
    expect(
      events.where((e) => e.type == AgentEventType.step).length,
      2,
      reason: 'her adım running + finished olarak iki kez yayınlanmalı',
    );
  });

  test('onay reddedilirse araç ÇALIŞMAZ ve model bunu öğrenir', () async {
    tool.requiresApprovalFlag = true;
    final model = ScriptedModel([
      callTurn('shell_probe', {'command': 'rm -rf /sdcard/x'}),
      textTurn,
    ]);
    final loop = AgentLoop(
      model: model.call,
      registry: registry,
      onNeedsApproval: (step, reason) async => ApprovalDecision.deny,
    );

    final result = await loop.run('temizle');

    expect(tool.calls, isEmpty, reason: 'reddedilen adım hiç çalışmamalı');
    expect(result.steps.single.status, AgentStepStatus.denied);
    final responsePart =
        model.seen[1].last.parts.single as Map<String, dynamic>;
    final payload = responsePart['functionResponse'] as Map<String, dynamic>;
    expect((payload['response'] as Map)['ok'], isFalse);
    expect((payload['response'] as Map)['output'], contains('onaylamadı'));
  });

  test('"hep izin ver" seçilince aynı araç için tekrar sorulmaz', () async {
    tool.requiresApprovalFlag = true;
    var approvalRequests = 0;
    final model = ScriptedModel([
      callTurn('shell_probe', {'command': 'a'}, id: 'c1'),
      callTurn('shell_probe', {'command': 'b'}, id: 'c2'),
      textTurn,
    ]);
    final loop = AgentLoop(
      model: model.call,
      registry: registry,
      onNeedsApproval: (step, reason) async {
        approvalRequests++;
        return ApprovalDecision.allowAlways;
      },
    );

    final result = await loop.run('iki iş yap');

    expect(approvalRequests, 1, reason: 'ikinci çağrı için sorulmamalı');
    expect(tool.calls, hasLength(2));
    expect(result.steps, hasLength(2));
  });

  test('onay diyaloğu yoksa riskli araç çalışmaz (güvenli varsayılan)',
      () async {
    tool.requiresApprovalFlag = true;
    final model = ScriptedModel([
      callTurn('shell_probe', {'command': 'x'}),
      textTurn,
    ]);
    final loop = AgentLoop(model: model.call, registry: registry);

    final result = await loop.run('yap');

    expect(tool.calls, isEmpty);
    expect(result.steps.single.status, AgentStepStatus.denied);
  });

  test('aynı çağrı 3. kez tekrarlanırsa döngü durdurur', () async {
    final model = ScriptedModel([
      callTurn('shell_probe', {'command': 'aynı'}),
      callTurn('shell_probe', {'command': 'aynı'}),
      callTurn('shell_probe', {'command': 'aynı'}),
      textTurn,
    ]);
    final loop = AgentLoop(model: model.call, registry: registry);

    final result = await loop.run('takılı kaldı');

    expect(tool.calls, hasLength(2), reason: '3. çağrı çalıştırılmamalı');
    expect(result.steps.last.status, AgentStepStatus.error);
    expect(result.steps.last.result, contains('3. kez'));
  });

  test('olmayan araç adı model hatası olarak geri döner', () async {
    final model = ScriptedModel([
      callTurn('olmayan_arac', {}),
      textTurn,
    ]);
    final loop = AgentLoop(model: model.call, registry: registry);

    final result = await loop.run('dene');

    expect(result.steps.single.status, AgentStepStatus.error);
    expect(result.steps.single.result, contains('shell_probe'));
  });

  test('araç exception fırlatırsa döngü çökmez, hata modele döner', () async {
    tool.throwOnInvoke = true;
    final model = ScriptedModel([
      callTurn('shell_probe', {'command': 'x'}),
      textTurn,
    ]);
    final loop = AgentLoop(model: model.call, registry: registry);

    final result = await loop.run('dene');

    expect(result.steps.single.status, AgentStepStatus.error);
    expect(result.steps.single.result, contains('araç patladı'));
    expect(result.answer, 'görev bitti');
  });

  test('araç ok=false dönerse adım error işaretlenir', () async {
    tool.ok = false;
    tool.output = 'exit_code: 1';
    final model = ScriptedModel([
      callTurn('shell_probe', {'command': 'yanlış komut'}),
      textTurn,
    ]);
    final loop = AgentLoop(model: model.call, registry: registry);

    final result = await loop.run('dene');

    expect(result.steps.single.status, AgentStepStatus.error);
    expect(result.steps.single.result, contains('exit_code: 1'));
  });

  test('adım limiti dolunca dürüst durum raporu istenir', () async {
    final model = ScriptedModel([
      callTurn('shell_probe', {'command': '1'}, id: 'a'),
      callTurn('shell_probe', {'command': '2'}, id: 'b'),
      callTurn('shell_probe', {'command': '3'}, id: 'c'),
      const ModelTurn(text: 'durum raporu'),
    ]);
    final loop = AgentLoop(model: model.call, registry: registry, maxSteps: 3);

    final result = await loop.run('uzun görev');

    expect(result.hitStepLimit, isTrue);
    expect(result.answer, 'durum raporu');
    // Son turda wrap-up talimatı gönderilmiş olmalı.
    final lastTurn = model.seen.last;
    expect(lastTurn.last.parts.single.toString(), contains('Adım limitine'));
  });

  test('iptal edilince döngü durur ve sonuç cancelled olur', () async {
    late AgentLoop loop;
    final model = ScriptedModel([
      callTurn('shell_probe', {'command': '1'}, id: 'a'),
      textTurn,
    ]);
    loop = AgentLoop(
      model: (contents, prompt) async {
        final turn = await model.call(contents, prompt);
        loop.cancel(); // ilk turdan sonra kullanıcı durduruyor
        return turn;
      },
      registry: registry,
    );

    final result = await loop.run('başla');

    expect(result.cancelled, isTrue);
    expect(result.answer, contains('iptal'));
  });

  test('update_plan aracı planı yayınlar ve olay akışına düşer', () async {
    final planRegistry = AgentToolRegistry()..register(TodoTool());
    final model = ScriptedModel([
      callTurn('update_plan', {
        'action': 'set',
        'items': [
          {'id': 'p1', 'text': 'klasörü oluştur'},
          {'id': 'p2', 'text': 'dosyayı yaz'},
        ],
      }),
      callTurn(
          'update_plan', {'action': 'update', 'id': 'p1', 'status': 'done'},
          id: 'c2'),
      textTurn,
    ]);
    final events = <AgentEvent>[];
    final loop = AgentLoop(
      model: model.call,
      registry: planRegistry,
      onEvent: events.add,
    );

    final result = await loop.run('planla ve yap');

    expect(result.plan, hasLength(2));
    expect(result.plan.first.status, 'done');
    expect(result.plan.last.status, 'pending');
    expect(result.steps, hasLength(2));
    expect(
      events.where((e) => e.type == AgentEventType.plan).isNotEmpty,
      isTrue,
    );
  });

  test('boş görev ve boş araç seti için anlamlı hata verir', () async {
    final loop =
        AgentLoop(model: ScriptedModel([textTurn]).call, registry: registry);
    expect(() => loop.run('   '), throwsA(isA<AgentLoopException>()));

    final emptyLoop = AgentLoop(
      model: ScriptedModel([textTurn]).call,
      registry: AgentToolRegistry(),
    );
    expect(() => emptyLoop.run('görev'), throwsA(isA<AgentLoopException>()));
  });

  test('aynı anda iki görev başlatılamaz', () async {
    final completer = Completer<ModelTurn>();
    final loop = AgentLoop(
      model: (contents, prompt) => completer.future,
      registry: registry,
    );
    final first = loop.run('birinci');
    expect(() => loop.run('ikinci'), throwsA(isA<AgentLoopException>()));
    completer.complete(textTurn);
    await first;
  });

  test('token ve model turu sayacı toplanır', () async {
    final model = ScriptedModel([
      const ModelTurn(
        calls: [ModelFunctionCall(id: 'a', name: 'shell_probe', args: {})],
        promptTokens: 100,
        completionTokens: 20,
      ),
      const ModelTurn(text: 'bitti', promptTokens: 150, completionTokens: 30),
    ]);
    final loop = AgentLoop(model: model.call, registry: registry);

    final result = await loop.run('say');

    expect(result.totalTokens, 300);
    expect(result.modelCalls, 2);
  });
}
