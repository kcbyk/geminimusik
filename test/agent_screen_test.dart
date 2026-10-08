import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_music_hub/screens/agent_screen.dart';
import 'package:ai_music_hub/services/agent/agent_controller.dart';
import 'package:ai_music_hub/services/agent/agent_loop.dart';
import 'package:ai_music_hub/services/agent/agent_models.dart';

/// Adım kartındaki sonuç metnini döndürür (composer'daki TextField'i elemez).
String _resultText(WidgetTester tester) {
  final texts = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data ?? '')
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
    // Bu iki kanal mock'lanmazsa initialize()/hafıza zinciri test ortamında
    // hiç tamamlanmıyor ve ajan "çalışıyor" durumunda takılı kalıyor.
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final dir = Directory.systemTemp.createTempSync('agent_test_');
      return dir.path;
    });

    agent = AgentController();
    agent.events.clear();
    agent.steps.clear();
    AgentPlanStore.instance.clear();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AgentScreen()));
    await tester.pump();
  }

  testWidgets('boş durumda görev daveti ve öneriler görünür', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Görevi ver, ajan yürütsün'), findsOneWidget);
    expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
    expect(find.byType(ActionChip), findsWidgets);
    // "12 araç hazır" tarzı durum yazısı kaldırıldı; yerinde plan düğmesi var.
    expect(find.byKey(const ValueKey('plan_button')), findsOneWidget);
    expect(find.textContaining('araç hazır'), findsNothing);
  });

  testWidgets('plan düğmesi paneli açar ve kapatır', (tester) async {
    AgentPlanStore.instance.replace(const [
      AgentPlanItem(id: 'p1', text: 'klasörü oluştur', status: 'done'),
      AgentPlanItem(id: 'p2', text: 'dosyayı yaz', status: 'in_progress'),
    ]);
    agent.events.add(
        const AgentEvent(type: AgentEventType.task, message: 'notları kur'));

    await pumpScreen(tester);

    // Panel kapalıyken içerik görünmez, düğme "plan 1/2" der.
    expect(find.byKey(const ValueKey('plan_panel')), findsNothing);
    expect(find.text('plan 1/2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plan_panel')), findsOneWidget);
    expect(find.text('AJAN NE YAPIYOR'), findsOneWidget);
    expect(find.text('klasörü oluştur'), findsOneWidget);
    expect(find.text('dosyayı yaz'), findsOneWidget);
    expect(find.text('1/2 tamamlandı'), findsOneWidget);
    expect(find.text('kapat'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plan_panel')), findsNothing);
    expect(find.text('plan 1/2'), findsOneWidget);
  });

  testWidgets('panel son adımları ve hafıza özetini gösterir', (tester) async {
    agent.steps.addAll(const [
      AgentStep(
        index: 1,
        toolName: 'device',
        args: {'action': 'list_apps'},
        status: AgentStepStatus.done,
        elapsed: Duration(milliseconds: 120),
      ),
      AgentStep(
        index: 2,
        toolName: 'memory',
        args: {'action': 'add'},
        status: AgentStepStatus.done,
        elapsed: Duration(milliseconds: 8),
      ),
    ]);
    agent.events.add(const AgentEvent(
        type: AgentEventType.step,
        step: AgentStep(index: 1, toolName: 'device', args: {})));
    agent.debugNotify();

    await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('plan_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Son adımlar (2)'), findsOneWidget);
    expect(find.text('device'), findsWidgets);
    expect(find.text('memory'), findsOneWidget);
    expect(find.textContaining('Hafıza boş'), findsOneWidget);
  });

  testWidgets('araç adımları zaman çizelgesine düşer, plan kartı tekrarlanmaz',
      (tester) async {
    AgentPlanStore.instance.replace(const [
      AgentPlanItem(id: 'p1', text: 'klasörü oluştur'),
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
    ]);
    agent.debugNotify();

    await pumpScreen(tester);

    expect(find.text('shell'), findsOneWidget);
    expect(find.textContaining('mkdir notlar'), findsOneWidget);
    expect(find.text('42 ms'), findsOneWidget);
    expect(find.text('notlar klasörünü kur'), findsOneWidget);
    // Plan artık timeline'da değil, sadece panelde.
    expect(find.text('klasörü oluştur'), findsNothing);
  });

  testWidgets('adım kartına dokununca açılır, tekrar dokununca küçülür',
      (tester) async {
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

    final state = tester.state<AgentScreenState>(find.byType(AgentScreen));
    expect(state.debugExpandedSteps, isEmpty);
    // Kırpılmış metin son satırı içermemeli.
    expect(_resultText(tester), isNot(contains('çıktı satırı 59')));

    // Kartın başlığına dokun -> açılır.
    final card = find.byKey(const ValueKey('step_card_1'));
    await tester.tapAt(tester.getTopLeft(card) + const Offset(60, 14));
    await tester.pump();

    expect(state.debugExpandedSteps, contains(1));
    expect(_resultText(tester), contains('çıktı satırı 59'));
    expect(find.byIcon(Icons.unfold_less), findsOneWidget);

    // Açıkken karta tekrar dokunmak küçültür (SelectableText yok).
    await tester.ensureVisible(card);
    await tester.pump();
    await tester.tapAt(tester.getTopLeft(card) + const Offset(60, 14));
    await tester.pump();

    expect(state.debugExpandedSteps, isEmpty);
    expect(_resultText(tester), isNot(contains('çıktı satırı 59')));
    expect(find.byIcon(Icons.unfold_more), findsOneWidget);
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

  testWidgets('"Reddet" kararı diyaloğu kapatır ve deny döner', (tester) async {
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

  testWidgets('araç seti menüden değiştirilir', (tester) async {
    await pumpScreen(tester);
    expect(agent.profile, AgentToolProfile.full);

    await _tapMenu(tester, Icons.code);
    expect(agent.profile, AgentToolProfile.developer);

    await _tapMenu(tester, Icons.handyman);
    expect(agent.profile, AgentToolProfile.full);
  });

  testWidgets('anahtar yokken görev hatası kullanıcıya gösterilir',
      (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField).last, 'bir şeyler yap');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('Gemini anahtarı ayarlanmamış'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(agent.isRunning, isFalse);
  });
}
