import 'dart:async';

import '../gemini_service.dart';
import 'agent_memory.dart';
import 'agent_models.dart';
import 'agent_paths.dart';
import 'agent_prompts.dart';
import 'turn_model.dart';

/// Model turunu üreten soyutlama. Gerçek hayatta [GeminiService], testlerde sahte.
/// [systemPrompt] ajanın karakteridir; sesli asistan farklı bir prompt ile aynı
/// döngüyü kullanabilsin diye modele her turda iletilir.
typedef ModelCaller = Future<ModelTurn> Function(
  List<TurnContent> contents,
  String systemPrompt,
);

/// Riskli bir araç çağrısı için kullanıcı kararı.
enum ApprovalDecision { allow, allowAlways, deny }

typedef ApprovalHandler = Future<ApprovalDecision> Function(
  AgentStep step,
  String reason,
);

class AgentRunResult {
  final String answer;
  final List<AgentStep> steps;
  final List<AgentPlanItem> plan;
  final int totalTokens;
  final int modelCalls;
  final bool cancelled;
  final bool hitStepLimit;
  final Duration elapsed;

  const AgentRunResult({
    required this.answer,
    required this.steps,
    required this.plan,
    required this.totalTokens,
    required this.modelCalls,
    this.cancelled = false,
    this.hitStepLimit = false,
    this.elapsed = Duration.zero,
  });
}

class AgentLoopException implements Exception {
  final String message;
  const AgentLoopException(this.message);
  @override
  String toString() => message;
}

/// Ajanın kalbi: model -> araç -> model -> ... döngüsü.
///
/// Bu sınıf Flutter bilmez. UI [onEvent] üzerinden adım adım beslenir,
/// onaylar [onNeedsApproval] ile istenir, iptal [cancel] ile yapılır.
class AgentLoop {
  AgentLoop({
    required ModelCaller model,
    required AgentToolRegistry registry,
    String? systemPrompt,
    this.maxSteps = 25,
    this.onEvent,
    this.onNeedsApproval,
    AgentMemory? memory,
  })  : _model = model,
        _registry = registry,
        _systemPrompt = systemPrompt ?? AgentPrompts.agent,
        _memory = memory;

  final ModelCaller _model;
  final AgentToolRegistry _registry;
  final String _systemPrompt;

  /// Verilirse görev geçmişi modele taşınır ve her görev sonunda kaydedilir.
  final AgentMemory? _memory;
  final int maxSteps;
  final void Function(AgentEvent event)? onEvent;
  final ApprovalHandler? onNeedsApproval;

  final List<AgentStep> _steps = [];
  final Set<String> _alwaysAllowed = {};
  final Map<String, int> _repeatGuard = {};

  bool _cancelled = false;
  bool _running = false;
  int _modelCalls = 0;
  int _totalTokens = 0;

  bool get isRunning => _running;
  List<AgentStep> get steps => List.unmodifiable(_steps);

  /// "Bu tur için hep izin ver" seçimlerini tutar.
  void rememberApproval(String toolName) => _alwaysAllowed.add(toolName);
  void clearApprovals() => _alwaysAllowed.clear();

  void cancel() => _cancelled = true;

  void reset() {
    _steps.clear();
    _repeatGuard.clear();
    _cancelled = false;
  }

  void _emit(AgentEvent event) => onEvent?.call(event);

  /// Görevi baştan sona yürütür ve son yanıtı döner.
  Future<AgentRunResult> run(String task) async {
    if (_running) {
      throw const AgentLoopException('Ajan zaten bir görev yürütüyor.');
    }
    if (task.trim().isEmpty) {
      throw const AgentLoopException('Görev metni boş olamaz.');
    }
    if (_registry.isEmpty) {
      throw const AgentLoopException('Ajanın hiç aracı yok.');
    }

    _running = true;
    _cancelled = false;
    _modelCalls = 0;
    _totalTokens = 0;
    final stopwatch = Stopwatch()..start();

    final contents = <TurnContent>[
      TurnContent.user([task.trim()])
    ];
    _emit(AgentEvent(type: AgentEventType.task, message: task.trim()));
    if (!AgentPlanStore.instance.isEmpty) {
      _emit(AgentEvent(
        type: AgentEventType.plan,
        plan: AgentPlanStore.instance.items,
      ));
    }

    var finalText = '';
    var hitLimit = false;

    try {
      for (var step = 0; step < maxSteps; step++) {
        if (_cancelled) break;

        final turn = await _model(contents, _systemPrompt);
        _modelCalls++;
        _totalTokens += turn.totalTokens;

        if (!turn.hasCalls) {
          // Son tur: bu metin zaten "görev bitti" kartında gösterilecek,
          // ayrıca bir "AJAN" kartı açmak aynı içeriği iki kez yazıyordu.
          finalText = turn.text.trim();
          break;
        }

        if (turn.text.trim().isNotEmpty) {
          _emit(AgentEvent(
            type: AgentEventType.modelText,
            message: turn.text.trim(),
          ));
        }

        contents.add(
          TurnContent.model([
            if (turn.text.trim().isNotEmpty) turn.text.trim(),
            ...turn.calls.map(functionCallPart),
          ]),
        );

        final responses = <Map<String, dynamic>>[];
        for (final call in turn.calls) {
          if (_cancelled) {
            responses.add(functionResponsePart(
              callId: call.id,
              name: call.name,
              output: 'Kullanıcı görevi iptal etti.',
              ok: false,
            ));
            continue;
          }
          responses.add(await _execute(call, step));
        }
        contents.add(TurnContent.user(responses));
      }

      if (finalText.isEmpty && !_cancelled) {
        // Adım limiti doldu: kullanıcıya dürüst bir durum raporu bırak.
        hitLimit = true;
        contents.add(TurnContent.user([AgentPrompts.wrapUp]));
        final wrapTurn = await _model(contents, _systemPrompt);
        _modelCalls++;
        _totalTokens += wrapTurn.totalTokens;
        finalText = wrapTurn.text.trim();
      }
    } catch (error) {
      final message = 'Ajan hatası: $error';
      _emit(AgentEvent(type: AgentEventType.error, message: message));
      stopwatch.stop();
      await _remember(task, message);
      return AgentRunResult(
        answer: message,
        steps: steps,
        plan: AgentPlanStore.instance.items,
        totalTokens: _totalTokens,
        modelCalls: _modelCalls,
        cancelled: _cancelled,
        hitStepLimit: hitLimit,
        elapsed: stopwatch.elapsed,
      );
    }

    stopwatch.stop();
    final answer = finalText.isEmpty
        ? (_cancelled ? 'Görev iptal edildi.' : 'Ajan yanıt üretmedi.')
        : finalText;

    await _remember(task, answer);

    _emit(AgentEvent(
      type: AgentEventType.done,
      message: answer,
      cancelled: _cancelled,
    ));

    return AgentRunResult(
      answer: answer,
      steps: steps,
      plan: AgentPlanStore.instance.items,
      totalTokens: _totalTokens,
      modelCalls: _modelCalls,
      cancelled: _cancelled,
      hitStepLimit: hitLimit,
      elapsed: stopwatch.elapsed,
    );
  }

  /// Görevi kalıcı günlüğe işler. Hata görevin kendisini bozmasın.
  Future<void> _remember(String task, String answer) async {
    final memory = _memory;
    if (memory == null) return;
    try {
      await memory.rememberTurn(
        task: task,
        answer: answer,
        toolsUsed: _steps.map((s) => s.toolName).toList(),
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _execute(
    ModelFunctionCall call,
    int loopStep,
  ) async {
    final tool = _registry[call.name];
    final agentStep = AgentStep(
      index: _steps.length + 1,
      toolName: call.name,
      args: call.args,
    );
    _steps.add(agentStep);
    _emit(AgentEvent(type: AgentEventType.step, step: agentStep));

    if (tool == null) {
      final message =
          '"${call.name}" adında bir araç yok. Kullanılabilir araçlar: '
          '${_registry.tools.map((t) => t.name).join(', ')}';
      return _finishStep(agentStep, message, AgentStepStatus.error, call.id,
          ok: false);
    }

    // 1. Onay kapısı: aracın kendi riski + komut bazlı risk analizi.
    final verdict = call.name == 'shell'
        ? const CommandRiskAnalyzer()
            .analyze((call.args['command'] as String?) ?? '')
        : null;

    if (verdict != null && verdict.isBlocked) {
      return _finishStep(
          agentStep, verdict.reason, AgentStepStatus.denied, call.id,
          ok: false);
    }

    final needsApproval = tool.requiresApproval ||
        (verdict?.needsApproval ?? false) ||
        _touchesPathOutsideWorkspace(call.args);
    if (needsApproval && !_alwaysAllowed.contains(call.name)) {
      final reason = verdict?.reason ??
          (tool.requiresApproval
              ? '"${tool.name}" cihazda kalıcı etki bırakabilir.'
              : 'Çalışma alanı dışındaki bir yola dokunuyor.');
      final decision = onNeedsApproval == null
          ? ApprovalDecision.deny
          : await onNeedsApproval!(agentStep, reason);
      if (decision == ApprovalDecision.allowAlways) {
        _alwaysAllowed.add(call.name);
      }
      if (decision == ApprovalDecision.deny) {
        return _finishStep(
          agentStep,
          'Kullanıcı bu adımı onaylamadı. Başka bir yol dene ya da neden '
          'gerekli olduğunu açıklayıp onay iste.',
          AgentStepStatus.denied,
          call.id,
          ok: false,
        );
      }
    }

    // 2. Aynı çağrıyı tekrar tekrar denemeyi kes.
    final signature = agentStep.signature;
    _repeatGuard[signature] = (_repeatGuard[signature] ?? 0) + 1;
    if (_repeatGuard[signature]! >= 3) {
      return _finishStep(
        agentStep,
        'Aynı araç aynı argümanlarla 3. kez çağrıldı. Bu yolu bırak: '
        'çıktıyı oku, farklı bir argüman ya da farklı bir araç dene.',
        AgentStepStatus.error,
        call.id,
        ok: false,
      );
    }

    // 3. Çalıştır.
    final stopwatch = Stopwatch()..start();
    try {
      final result = await tool.invoke(call.args);
      stopwatch.stop();
      return _finishStep(
        agentStep,
        wrapToolResponse(result.output, ok: result.ok),
        result.ok ? AgentStepStatus.done : AgentStepStatus.error,
        call.id,
        ok: result.ok,
        elapsed: stopwatch.elapsed,
      );
    } catch (error) {
      stopwatch.stop();
      return _finishStep(
        agentStep,
        'Araç çalışırken hata oluştu: $error',
        AgentStepStatus.error,
        call.id,
        ok: false,
        elapsed: stopwatch.elapsed,
      );
    }
  }

  Map<String, dynamic> _finishStep(
    AgentStep agentStep,
    String output,
    AgentStepStatus status,
    String callId, {
    required bool ok,
    Duration elapsed = Duration.zero,
  }) {
    final index = _steps.indexWhere((s) => s.index == agentStep.index);
    final updated = agentStep.copyWith(
      status: status,
      result: output,
      elapsed: elapsed,
    );
    if (index >= 0) _steps[index] = updated;
    _emit(AgentEvent(type: AgentEventType.step, step: updated));
    // Plan değişmiş olabilir (update_plan çağrısı): UI'ı tazele.
    _emit(AgentEvent(
      type: AgentEventType.plan,
      plan: AgentPlanStore.instance.items,
    ));
    return functionResponsePart(
      callId: callId,
      name: agentStep.toolName,
      output: output,
      ok: ok,
    );
  }

  /// path/source/destination argümanı çalışma alanı dışına çıkıyorsa onay iste.
  bool _touchesPathOutsideWorkspace(Map<String, dynamic> args) {
    const keys = ['path', 'source', 'destination', 'cwd'];
    for (final key in keys) {
      final value = args[key];
      if (value is! String || value.trim().isEmpty) continue;
      if (!AgentPathPolicy.instance.isInsideWorkspace(value.trim())) {
        return true;
      }
    }
    return false;
  }
}
