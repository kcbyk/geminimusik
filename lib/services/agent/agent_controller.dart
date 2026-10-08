import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../gemini_service.dart';
import 'agent_loop.dart';
import 'agent_models.dart';
import 'agent_paths.dart';
import 'agent_prompts.dart';
import 'agent_tool_registry.dart';
import 'turn_model.dart';

enum AgentToolProfile { full, developer, voice }

/// Ajan çekirdeği ile Flutter UI arasındaki köprü.
///
/// Ekran yalnızca bunu dinler; döngü mantığı burada değil [AgentLoop] içindedir.
class AgentController extends ChangeNotifier {
  /// Tek örnek: Jarvis (ses) ve Agent ekranı aynı çalışma alanını paylaşır.
  factory AgentController() => _instance;
  AgentController._internal({GeminiService? gemini})
      : _gemini = gemini ?? GeminiService();

  static final AgentController _instance = AgentController._internal();

  final GeminiService _gemini;

  final List<AgentEvent> events = [];
  final List<AgentStep> steps = [];
  List<AgentPlanItem> plan = const [];

  StreamSubscription<List<AgentPlanItem>>? _planSub;
  AgentLoop? _loop;
  AgentRunResult? _lastResult;
  String _lastAnswer = '';
  bool _running = false;
  bool _initialized = false;
  String _workspaceRoot = '';
  String _model = 'gemini-2.5-flash';
  int _maxSteps = 25;
  AgentToolProfile _profile = AgentToolProfile.full;
  AgentToolRegistry _registry = AgentToolRegistryBuilder.full();

  final StreamController<
      ({
        AgentStep step,
        String reason,
        Completer<ApprovalDecision> completer
      })> _approvalController = StreamController.broadcast();

  /// UI bu akışı dinleyip onay diyaloğu gösterir.
  Stream<
      ({
        AgentStep step,
        String reason,
        Completer<ApprovalDecision> completer
      })> get approvalRequests => _approvalController.stream;

  bool get isRunning => _running;
  bool get isInitialized => _initialized;
  String get workspaceRoot => _workspaceRoot;
  String get model => _model;
  int get maxSteps => _maxSteps;
  AgentToolProfile get profile => _profile;
  String get lastAnswer => _lastAnswer;
  AgentRunResult? get lastResult => _lastResult;
  int get toolCount => _registry.length;
  List<String> get toolNames => _registry.tools.map((t) => t.name).toList();

  void setModel(String value) {
    _model = value;
    notifyListeners();
  }

  void setMaxSteps(int value) {
    _maxSteps = value.clamp(3, 60);
    notifyListeners();
  }

  /// Cihazda her yola yazma izni. Kapalıyken ajan sadece kendi alanına yazar.
  bool get allowUnrestrictedPaths =>
      AgentPathPolicy.instance.allowUnrestrictedPaths;

  void setAllowUnrestrictedPaths(bool value) {
    AgentPathPolicy.instance.allowUnrestrictedPaths = value;
    notifyListeners();
  }

  void setProfile(AgentToolProfile value) {
    _profile = value;
    _registry = switch (value) {
      AgentToolProfile.full => AgentToolRegistryBuilder.full(),
      AgentToolProfile.developer => AgentToolRegistryBuilder.developer(),
      AgentToolProfile.voice => AgentToolRegistryBuilder.voice(),
    };
    notifyListeners();
  }

  /// Uygulama açılırken bir kez çağrılır: ajan çalışma alanını hazırlar.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Plan aboneliği her şeyden önce kurulur: çalışma alanı hazırlanamasa bile
    // (web/test ortamı gibi) plan güncellemeleri ekrana ulaşsın.
    _planSub ??= AgentPlanStore.instance.onChange.listen((items) {
      plan = items;
      notifyListeners();
    });
    // Devam eden bir plan varsa (ör. Jarvis başlattı) ekran açılır açılmaz görünsün.
    plan = AgentPlanStore.instance.items;

    try {
      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final workspace = Directory('${dir.path}/agent');
      if (!workspace.existsSync()) {
        workspace.createSync(recursive: true);
      }
      Directory('${workspace.path}/tmp').createSync(recursive: true);
      _workspaceRoot = workspace.path;
    } catch (error) {
      debugPrint('[Agent] Çalışma alanı hazırlanamadı: $error');
      _workspaceRoot = '';
    }
    if (_workspaceRoot.isNotEmpty) {
      AgentPathPolicy.instance.configureRoot(_workspaceRoot);
    }
    notifyListeners();
  }

  Future<AgentRunResult> runTask(String task) async {
    if (_running) {
      throw const AgentLoopException('Ajan zaten bir görev yürütüyor.');
    }
    await initialize();

    events.clear();
    steps.clear();
    plan = AgentPlanStore.instance.items;
    _lastAnswer = '';
    _lastResult = null;
    _running = true;
    notifyListeners();

    final loop = AgentLoop(
      model: _callModel,
      registry: _registry,
      maxSteps: _maxSteps,
      onEvent: _handleEvent,
      onNeedsApproval: _requestApproval,
    );
    _loop = loop;

    try {
      final result = await loop.run(task);
      _lastResult = result;
      _lastAnswer = result.answer;
      return result;
    } finally {
      _running = false;
      _loop = null;
      notifyListeners();
    }
  }

  void cancel() => _loop?.cancel();

  /// Test/izleme kancası: dışarıdan eklenen olayları dinleyicilere duyurur.
  @visibleForTesting
  void debugNotify() => notifyListeners();

  /// Test kancası: onay akışını UI olmadan tetikler.
  @visibleForTesting
  void debugFireApproval(
    ({
      AgentStep step,
      String reason,
      Completer<ApprovalDecision> completer
    }) request,
  ) =>
      _approvalController.add(request);

  /// Jarvis yolu: kısa, onaysız, cihaz odaklı hızlı çalıştırma.
  Future<String> runQuick(String task, {int maxSteps = 4}) async {
    await initialize();
    final loop = AgentLoop(
      model: _callModel,
      registry: AgentToolRegistryBuilder.voice(),
      systemPrompt: AgentPrompts.voice,
      maxSteps: maxSteps,
    );
    final result = await loop.run(task);
    return result.answer;
  }

  Future<ModelTurn> _callModel(
    List<TurnContent> contents,
    String systemPrompt,
  ) async {
    final response = await _gemini.sendTurn(
      contents: contents,
      model: _model,
      systemPrompt: systemPrompt,
      tools: _registry.schemas,
    );
    return ModelTurn(
      text: response.text,
      calls: response.functionCalls,
      promptTokens: response.promptTokens,
      completionTokens: response.completionTokens,
    );
  }

  void _handleEvent(AgentEvent event) {
    events.add(event);
    if (event.type == AgentEventType.step && event.step != null) {
      final index = steps.indexWhere((s) => s.index == event.step!.index);
      if (index >= 0) {
        steps[index] = event.step!;
      } else {
        steps.add(event.step!);
      }
    }
    if (event.type == AgentEventType.plan && event.plan != null) {
      plan = event.plan!;
    }
    notifyListeners();
  }

  Future<ApprovalDecision> _requestApproval(
    AgentStep step,
    String reason,
  ) async {
    final completer = Completer<ApprovalDecision>();
    _approvalController.add((step: step, reason: reason, completer: completer));
    return completer.future;
  }

  bool _released = false;

  /// Bu bir singleton olduğu için `dispose()` edilmez (ChangeNotifier'ı
  /// öldürür ve Jarvis yolu bir daha kullanamaz). Yalnızca abonelikler
  /// bırakılır; örnek yeniden kullanılabilir durumda kalır.
  void release() {
    if (_released) return;
    _released = true;
    _planSub?.cancel();
    _planSub = null;
    // Onay akışı kapatılmaz: Jarvis yolu ve sonraki ekran aynı akışı kullanır.
  }
}
