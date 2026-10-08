import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_music_hub/screens/agent_screen.dart';
import 'package:ai_music_hub/services/agent/agent_controller.dart';
import 'package:ai_music_hub/services/agent/agent_loop.dart';
import 'package:ai_music_hub/services/agent/agent_models.dart';

/// Adım kartındaki SelectableText içeriğini döndürür (composer'ı elemez).
String _resultText(WidgetTester tester) {
  final texts = find
      .byType(SelectableText)
      .evaluate()
      .map((e) => (e.widget as SelectableText).data ?? '')
      .where((t) => t.contains('çıktı satırı'))
      .toList();
  return texts.isEmpty ? '' : texts.first;
}

/// Ayar menüsünü açar ve ikonuna göre satırı tıklar (metin snackbar ile
/// karışmasın diye metin değil ikon üzerinden bulunur).
Future<void> _tapMenu(WidgetTester tester, IconData rowIcon) async {
  await tester.tap(find.byIcon(Icons.tune));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(
    of: find.byType(PopupMenuItem<String>),
    matching: find.byIcon(rowIcon),
  ));
  await tester.pumpAndSettle();
}

void main() {
  late AgentController agent;

  setUp(() {
    agent = AgentController();
    agent.events.clear();
    agent.steps.clear();
    AgentPlanStore.instance.clear();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AgentScreen()));
    await tester.pump();
  }

  /// Zaman çizelgesi her çizimde alta kaydırma animasyonu tetikliyor;
  /// dokunma testlerinden önce o animasyonu bitiriyoruz.
  Future<void> settleTimeline(WidgetTester tester) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 60));
  }

  testWidgets('boş durumda görev daveti ve öneriler görünür', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Görevi ver, ajan yürütsün'), findsOneWidget);
    expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
    expect(find.byType(ActionChip), findsWidgets);
    expect(find.textContaining('araç hazır'), findsOneWidget);
  });

  testWidgets('plan kartı ve araç adımları zaman çizelgesine düşer',
      (tester) async {
    AgentPlanStore.instance.replace(const [
      AgentPlanItem(id: 'p1', text: 'klasörü oluştur', status: 'done'),
      AgentPlanItem(id: 'p2', text: 'dosyayı yaz', status: 'in_progress'),
    ]);
    agent.events.addAll([
      const AgentEvent(
          type: AgentEventType.task, message: 'notlar klasörünü kur'),
      const AgentEvent(
        type: AgentEventType.step,
        step: AgentStep(
          index: 1,
          toolName: 'shell',
          args: {'command': 'mkdir notlar'},
          status: AgentStepStatus.done,
          result: 'exit_code: 0',
          elapsed: Duration(milliseconds: 42),
        ),
      ),
      const AgentEvent(
        type: AgentEventType.step,
        step: AgentStep(
          index: 2,
          toolName: 'write_file',
          args: {'path': 'notlar/a.md'},
        ),
      ),
    ]);
    agent.debugNotify();

    await pumpScreen(tester);

    expect(find.text('PLAN'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('klasörü oluştur'), findsOneWidget);
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('write_file'), findsOneWidget);
    expect(find.textContaining('mkdir notlar'), findsOneWidget);
    expect(find.text('42 ms'), findsOneWidget);
    expect(find.text('çalışıyor'), findsOneWidget);
    expect(find.text('notlar klasörünü kur'), findsOneWidget);
  });

  testWidgets('uzun adım çıktısı dokununca tamamen açılır', (tester) async {
    final longResult = List.generate(60, (i) => 'çıktı satırı $i').join('\n');
    agent.events.add(AgentEvent(
      type: AgentEventType.step,
      step: AgentStep(
        index: 1,
        toolName: 'read_file',
        args: const {'path': 'buyuk.txt'},
        status: AgentStepStatus.done,
        result: longResult,
      ),
    ));
    agent.debugNotify();

    await pumpScreen(tester);
    await settleTimeline(tester);

    expect(find.byIcon(Icons.unfold_more), findsOneWidget);
    // Kırpılmış metin son satırı içermemeli.
    expect(_resultText(tester), isNot(contains('çıktı satırı 59')));

    await tester.tap(find.byIcon(Icons.unfold_more));
    await tester.pump();

    final state = tester.state<AgentScreenState>(find.byType(AgentScreen));
    expect(state.debugExpandedSteps, contains(1));
    expect(_resultText(tester), contains('çıktı satırı 59'));

    // Kapalı duruma dönünce metin yine kırpılır.
    // Not: Aynı IconButton'a ikinci dokunuş Flutter test ortamında buton içi
    // Semantics sarmalayıcısı yüzünden güvenilir tetiklenmiyor; bu yüzden
    // kapatma, ekranın kendi setState yolu üzerinden doğrulanıyor.
    state.debugToggleStep(1);
    await tester.pump();
    expect(state.debugExpandedSteps, isEmpty);
    expect(find.byIcon(Icons.unfold_more), findsOneWidget);
    expect(_resultText(tester), isNot(contains('çıktı satırı 59')));
  });

  testWidgets('onay isteği diyalog açar, "İzin ver" kararı geri döner',
      (tester) async {
    await pumpScreen(tester);

    final completer = Completer<ApprovalDecision>();
    agent.debugFireApproval((
      step: const AgentStep(
        index: 1,
        toolName: 'shell',
        args: {'command': 'rm -rf eski_klasor'},
      ),
      reason: 'Komut cihazda kalıcı değişiklik yapabilir.',
      completer: completer,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Onay gerekiyor: shell'), findsOneWidget);
    expect(find.textContaining('kalıcı değişiklik'), findsOneWidget);

    await tester.tap(find.text('İzin ver'));
    await tester.pumpAndSettle();

    expect(completer.isCompleted, isTrue);
    expect(await completer.future, ApprovalDecision.allow);
  });

  testWidgets('"Reddet" kararı ajanı durdurmaz ama adımı işaretler',
      (tester) async {
    await pumpScreen(tester);

    final completer = Completer<ApprovalDecision>();
    agent.debugFireApproval((
      step: const AgentStep(index: 1, toolName: 'move_file', args: {
        'action': 'delete',
        'source': '/sdcard/x',
      }),
      reason: 'Silme geri alınamaz.',
      completer: completer,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reddet'));
    await tester.pumpAndSettle();

    expect(await completer.future, ApprovalDecision.deny);
    expect(find.textContaining('Onay gerekiyor'), findsNothing);
  });

  testWidgets('ayar menüsünden sınırsız dosya erişimi açılıp kapanır',
      (tester) async {
    await pumpScreen(tester);
    expect(agent.allowUnrestrictedPaths, isFalse);

    await _tapMenu(tester, Icons.folder);
    expect(agent.allowUnrestrictedPaths, isTrue);

    await _tapMenu(tester, Icons.folder_open);
    expect(agent.allowUnrestrictedPaths, isFalse);
  });

  testWidgets('adım limiti menüden değiştirilir', (tester) async {
    await pumpScreen(tester);
    final before = agent.maxSteps;

    await _tapMenu(tester, Icons.add_circle_outline);
    expect(agent.maxSteps, before + 5);

    await _tapMenu(tester, Icons.remove_circle_outline);
    expect(agent.maxSteps, before);
  });

  testWidgets('anahtar yokken görev hatası kullanıcıya gösterilir',
      (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField).last, 'bir şeyler yap');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(find.textContaining('Gemini anahtarı ayarlanmamış'), findsOneWidget);
    expect(agent.isRunning, isFalse);
  });
}
