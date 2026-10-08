import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/agent/agent_controller.dart';
import '../services/agent/agent_loop.dart';
import '../services/agent/agent_models.dart';
import '../services/agent/agent_tool_registry.dart';
import '../theme/gemini_colors.dart';

/// Ajan ekranı: görev ver, planı ve her adımı canlı izle, riskli adımda onay ver.
class AgentScreen extends StatefulWidget {
  final VoidCallback? onOpenSidebar;
  const AgentScreen({super.key, this.onOpenSidebar});

  @override
  State<AgentScreen> createState() => AgentScreenState();
}

/// Ekran durumu. Testlerin iç durumu (açık kartlar) doğrulayabilmesi için
/// bilerek public; uygulama kodu buna dokunmaz.
@visibleForTesting
class AgentScreenState extends State<AgentScreen> {
  final _taskController = TextEditingController();
  final AgentController _agent = AgentController();
  final _scrollController = ScrollController();
  final Set<int> _expandedSteps = {};
  StreamSubscription<dynamic>? _approvalSub;
  bool _approvalDialogOpen = false;

  /// Sağ üstteki düğmeyle açılan "ajan ne yapıyor" paneli.
  bool _planPanelOpen = false;

  /// Test kancası: hangi adım kartlarının açık olduğunu doğrulamak için.
  @visibleForTesting
  Set<int> get debugExpandedSteps => Set.unmodifiable(_expandedSteps);

  @visibleForTesting
  bool get debugPlanPanelOpen => _planPanelOpen;

  /// Test kancası: paneli setState üzerinden aç/kapat.
  @visibleForTesting
  void debugTogglePlanPanel() =>
      setState(() => _planPanelOpen = !_planPanelOpen);

  @override
  void initState() {
    super.initState();
    _agent.initialize();
    _approvalSub = _agent.approvalRequests.listen(_showApproval);
  }

  @override
  void dispose() {
    _approvalSub?.cancel();
    _taskController.dispose();
    _scrollController.dispose();
    // NOT: _agent bir singleton (Jarvis ile paylaşılıyor); burada dispose
    // edilmez, yalnızca abonelik bırakılır.
    super.dispose();
  }

  Future<void> _startTask() async {
    final task = _taskController.text.trim();
    if (task.isEmpty || _agent.isRunning) return;
    FocusScope.of(context).unfocus();
    _taskController.clear();
    _expandedSteps.clear();
    try {
      await _agent.runTask(task);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showApproval(dynamic request) async {
    if (_approvalDialogOpen || !mounted) {
      request.completer.complete(ApprovalDecision.deny);
      return;
    }
    _approvalDialogOpen = true;
    final AgentStep step = request.step as AgentStep;
    final String reason = request.reason as String;
    final Completer<ApprovalDecision> completer =
        request.completer as Completer<ApprovalDecision>;

    var always = false;
    final decision = await showDialog<ApprovalDecision>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          backgroundColor: const Color(0xFF1B1C20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(children: [
            const Icon(Icons.gpp_maybe_outlined, color: Colors.orangeAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Onay gerekiyor: ${step.toolName}',
                  style: const TextStyle(fontSize: 16, color: Colors.white)),
            ),
          ]),
          content: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(reason,
                      style: const TextStyle(
                          color: Colors.orangeAccent, fontSize: 13)),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101318),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      step.argsSummary.isEmpty
                          ? '(argümansız)'
                          : step.argsSummary,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontFamily: 'monospace',
                          fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: always,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: GeminiColors.geminiCyan,
                    title: const Text('Bu araç için tur boyunca tekrar sorma',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    onChanged: (value) =>
                        setLocalState(() => always = value ?? false),
                  ),
                ]),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, ApprovalDecision.deny),
              child: const Text('Reddet',
                  style: TextStyle(color: Colors.redAccent)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: GeminiColors.geminiCyan),
              onPressed: () => Navigator.pop(
                dialogContext,
                always ? ApprovalDecision.allowAlways : ApprovalDecision.allow,
              ),
              child: const Text('İzin ver',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    _approvalDialogOpen = false;
    if (!completer.isCompleted) {
      completer.complete(decision ?? ApprovalDecision.deny);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GeminiColors.background,
      appBar: AppBar(
        backgroundColor: GeminiColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: GeminiColors.textPrimary),
          onPressed: widget.onOpenSidebar,
        ),
        title:
            const Text('Agent', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          _buildPlanButton(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.tune, color: GeminiColors.textPrimary),
            color: const Color(0xFF1B1C20),
            onSelected: _onMenuSelected,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'model_flash',
                child: _menuItem(Icons.bolt, 'Model: gemini-2.5-flash',
                    _agent.model == 'gemini-2.5-flash'),
              ),
              PopupMenuItem(
                value: 'model_pro',
                child: _menuItem(Icons.workspace_premium,
                    'Model: gemini-2.5-pro', _agent.model == 'gemini-2.5-pro'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'profile_full',
                child: _menuItem(
                    Icons.handyman,
                    'Araç seti: Tam (${AgentToolRegistryBuilder.full().length})',
                    _agent.profile == AgentToolProfile.full),
              ),
              PopupMenuItem(
                value: 'profile_dev',
                child: _menuItem(Icons.code, 'Araç seti: Geliştirici',
                    _agent.profile == AgentToolProfile.developer),
              ),
              PopupMenuItem(
                value: 'profile_voice',
                child: _menuItem(Icons.graphic_eq, 'Araç seti: Ses/Cihaz',
                    _agent.profile == AgentToolProfile.voice),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'steps_minus',
                child: _menuItem(Icons.remove_circle_outline,
                    'Adım limiti: ${_agent.maxSteps} (azalt)', false),
              ),
              PopupMenuItem(
                value: 'steps_plus',
                child: _menuItem(Icons.add_circle_outline,
                    'Adım limiti: ${_agent.maxSteps} (artır)', false),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'unrestricted',
                child: _menuItem(
                  _agent.allowUnrestrictedPaths
                      ? Icons.folder_open
                      : Icons.folder,
                  'Sınırsız dosya erişimi: '
                  '${_agent.allowUnrestrictedPaths ? 'AÇIK' : 'kapalı'}',
                  _agent.allowUnrestrictedPaths,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'clear',
                child: _menuItem(Icons.delete_sweep_outlined,
                    'Zaman çizelgesini temizle', false),
              ),
              PopupMenuItem(
                value: 'clear_memory',
                child: _menuItem(
                    Icons.psychology_outlined,
                    'Hafızayı sıfırla (${_agent.memory.turnCount} görev)',
                    false),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: _agent,
          builder: (context, _) => Column(children: [
            if (_planPanelOpen) _buildPlanPanel(),
            Expanded(
              child:
                  _agent.events.isEmpty ? _buildEmptyState() : _buildTimeline(),
            ),
            _buildComposer(),
          ]),
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, bool active) => Row(children: [
        Icon(icon,
            size: 18, color: active ? GeminiColors.geminiCyan : Colors.white70),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: TextStyle(
                color: active ? GeminiColors.geminiCyan : Colors.white70,
                fontSize: 13,
              )),
        ),
      ]);

  void _onMenuSelected(String value) {
    switch (value) {
      case 'model_flash':
        _agent.setModel('gemini-2.5-flash');
      case 'model_pro':
        _agent.setModel('gemini-2.5-pro');
      case 'profile_full':
        _agent.setProfile(AgentToolProfile.full);
      case 'profile_dev':
        _agent.setProfile(AgentToolProfile.developer);
      case 'profile_voice':
        _agent.setProfile(AgentToolProfile.voice);
      case 'steps_minus':
        _agent.setMaxSteps(_agent.maxSteps - 5);
      case 'steps_plus':
        _agent.setMaxSteps(_agent.maxSteps + 5);
      case 'unrestricted':
        _agent.setAllowUnrestrictedPaths(!_agent.allowUnrestrictedPaths);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: _agent.allowUnrestrictedPaths
                ? Colors.orange
                : const Color(0xFF2A2B30),
            content: Text(_agent.allowUnrestrictedPaths
                ? 'Sınırsız dosya erişimi AÇIK: ajan /sdcard dahil her yola yazabilir.'
                : 'Ajan artık yalnızca kendi çalışma alanına yazıyor.'),
          ),
        );
      case 'clear':
        setState(() {
          _agent.events.clear();
          _agent.steps.clear();
          _expandedSteps.clear();
        });
      case 'clear_memory':
        _agent.clearMemory().then((_) {
          if (mounted) setState(() {});
        });
    }
  }

  /// Sağ üstteki plan düğmesi: ajanın ne yaptığını gösteren paneli açar/kapatır.
  Widget _buildPlanButton() {
    final total = _agent.plan.length;
    final done = _agent.plan.where((p) => p.status == 'done').length;
    final running = _agent.isRunning;
    final color = total == 0
        ? GeminiColors.textMuted
        : (running ? GeminiColors.geminiCyan : Colors.greenAccent);
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: TextButton.icon(
        key: const ValueKey('plan_button'),
        onPressed: () => setState(() => _planPanelOpen = !_planPanelOpen),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          backgroundColor: color.withValues(alpha: .12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        icon: Icon(_planPanelOpen ? Icons.close : Icons.checklist_rounded,
            size: 15, color: color),
        label: Text(
          _planPanelOpen
              ? 'kapat'
              : (total == 0 ? 'plan' : 'plan $done/$total'),
          style: TextStyle(
              color: color, fontSize: 11.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  /// Açılır/kapanır "ajan ne yapıyor" paneli: plan + son adımlar + hafıza.
  Widget _buildPlanPanel() {
    final plan = _agent.plan;
    final done = plan.where((p) => p.status == 'done').length;
    final lastSteps = _agent.steps.length <= 4
        ? _agent.steps
        : _agent.steps.sublist(_agent.steps.length - 4);

    return Container(
      key: const ValueKey('plan_panel'),
      constraints: const BoxConstraints(maxHeight: 300),
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1C20),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: GeminiColors.geminiCyan.withValues(alpha: .25)),
      ),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.checklist_rounded,
                size: 17, color: GeminiColors.geminiCyan),
            const SizedBox(width: 8),
            const Text('AJAN NE YAPIYOR',
                style: TextStyle(
                    color: GeminiColors.geminiCyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: .6)),
            const Spacer(),
            if (_agent.isRunning)
              Text('Adım ${_agent.steps.length}/${_agent.maxSteps}',
                  style: const TextStyle(
                      color: GeminiColors.geminiCyan, fontSize: 11)),
          ]),
          const SizedBox(height: 10),
          if (plan.isEmpty)
            const Text(
                'Henüz plan yok. Ajan çok adımlı bir görev aldığında planı '
                'burada canlı görünür.',
                style: TextStyle(
                    color: GeminiColors.textMuted, fontSize: 12.5, height: 1.4))
          else ...[
            for (final item in plan) _planRow(item),
            const SizedBox(height: 6),
            Text('$done/${plan.length} tamamlandı',
                style: const TextStyle(
                    color: GeminiColors.textMuted, fontSize: 11)),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFF2A2B30)),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.history_rounded,
                size: 15, color: GeminiColors.textMuted),
            const SizedBox(width: 8),
            Text(
              _agent.steps.isEmpty
                  ? 'Henüz adım yok'
                  : 'Son adımlar (${_agent.steps.length})',
              style: const TextStyle(
                  color: GeminiColors.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600),
            ),
          ]),
          const SizedBox(height: 6),
          for (final step in lastSteps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Icon(_stepStatusIcon(step.status),
                    size: 13, color: _stepStatusColor(step.status)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(step.toolName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontFamily: 'monospace',
                          fontSize: 11.5)),
                ),
                Text('${step.elapsed.inMilliseconds} ms',
                    style: const TextStyle(
                        color: GeminiColors.textMuted, fontSize: 10)),
              ]),
            ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFF2A2B30)),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.psychology_outlined,
                size: 15, color: GeminiColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _agent.memorySummary.isEmpty
                    ? 'Hafıza boş — ajan görevleri hatırlamaya başlayacak'
                    : 'Hafıza: ${_agent.memorySummary}',
                style: const TextStyle(
                    color: GeminiColors.textMuted, fontSize: 11.5),
              ),
            ),
            if (_agent.memorySummary.isNotEmpty)
              TextButton(
                key: const ValueKey('clear_memory'),
                onPressed: () async {
                  await _agent.clearMemory();
                  if (mounted) setState(() {});
                },
                child: const Text('sıfırla',
                    style: TextStyle(fontSize: 11, color: Colors.redAccent)),
              ),
          ]),
        ]),
      ),
    );
  }

  IconData _stepStatusIcon(AgentStepStatus status) => switch (status) {
        AgentStepStatus.running => Icons.pending,
        AgentStepStatus.done => Icons.check_circle,
        AgentStepStatus.error => Icons.error_outline,
        AgentStepStatus.denied => Icons.block,
        AgentStepStatus.cancelled => Icons.cancel_outlined,
      };

  Color _stepStatusColor(AgentStepStatus status) => switch (status) {
        AgentStepStatus.running => GeminiColors.geminiCyan,
        AgentStepStatus.done => Colors.greenAccent,
        AgentStepStatus.error => Colors.redAccent,
        AgentStepStatus.denied => Colors.orangeAccent,
        AgentStepStatus.cancelled => Colors.grey,
      };

  Widget _planRow(AgentPlanItem item) {
    final (icon, color) = switch (item.status) {
      'done' => (Icons.check_circle, Colors.greenAccent),
      'in_progress' => (Icons.pending, Colors.amberAccent),
      'failed' => (Icons.error_outline, Colors.redAccent),
      _ => (Icons.radio_button_unchecked, GeminiColors.textMuted),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(item.text,
              style: TextStyle(
                color: item.status == 'done'
                    ? GeminiColors.textMuted
                    : Colors.white,
                fontSize: 13,
                height: 1.35,
                decoration:
                    item.status == 'done' ? TextDecoration.lineThrough : null,
              )),
        ),
      ]),
    );
  }

  Widget _buildTimeline() {
    // Otomatik kaydırma yalnızca ajan çalışırken: bitmiş bir görevde kartı
    // açmak/kapatmak listeyi en alta fırlatmasın.
    if (_agent.isRunning) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
      itemCount: _agent.events.length,
      itemBuilder: (context, index) => _buildEventCard(_agent.events[index]),
    );
  }

  void _scrollToEnd() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Widget _buildEmptyState() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.smart_toy_outlined,
                size: 46, color: GeminiColors.geminiCyan),
            const SizedBox(height: 14),
            const Text('Görevi ver, ajan yürütsün',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Ajan plan çıkarır, dosya yazar/taşır, kabukta ve Termux\'ta komut '
              'çalıştırır, uygulamaları açar, sonucu kendi doğrular ve bir '
              'sonraki görev için hatırlar.\n\n'
              'Çalışma alanı: ${_agent.workspaceRoot.isEmpty ? 'hazırlanıyor…' : _agent.workspaceRoot}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: GeminiColors.textMuted, height: 1.5, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _suggestion(
                      'Kurulu uygulamalarımı listele ve WhatsApp\'ı aç'),
                  _suggestion(
                      'Çalışma alanında notlar klasörü oluştur, içine yapılacaklar dosyası yaz ve doğrula'),
                  _suggestion(
                      'Termux kurulu mu bak, kuruluysa python sürümünü söyle'),
                  _suggestion('Cihaz bilgilerini topla ve bir dosyaya kaydet'),
                ]),
          ]),
        ),
      );

  Widget _suggestion(String text) => ActionChip(
        backgroundColor: const Color(0xFF1B1C20),
        side: BorderSide(color: Colors.white.withValues(alpha: .1)),
        label: Text(
          text.length > 46 ? '${text.substring(0, 46)}…' : text,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        onPressed: () {
          _taskController.text = text;
          _startTask();
        },
      );

  Widget _buildEventCard(AgentEvent event) {
    switch (event.type) {
      case AgentEventType.task:
        return _card(
          icon: Icons.flag_outlined,
          color: GeminiColors.geminiCyan,
          title: 'GÖREV',
          child: Text(event.message ?? '',
              style: const TextStyle(color: Colors.white, height: 1.4)),
        );
      case AgentEventType.modelText:
        return _card(
          icon: Icons.psychology_outlined,
          color: GeminiColors.textMuted,
          title: 'AJAN',
          child: Text(event.message ?? '',
              style: const TextStyle(
                  color: Colors.white70, height: 1.45, fontSize: 13.5)),
        );
      case AgentEventType.step:
        return _buildStepCard(event.step!);
      case AgentEventType.done:
        return _buildFinalCard(event);
      case AgentEventType.error:
        return _card(
          icon: Icons.error_outline,
          color: Colors.redAccent,
          title: 'HATA',
          borderColor: Colors.redAccent.withValues(alpha: .4),
          child: Text(event.message ?? '',
              style: const TextStyle(color: Colors.redAccent, height: 1.4)),
        );
      case AgentEventType.plan:
        // Plan artık sağ üstteki panelde gösteriliyor.
        return const SizedBox.shrink();
    }
  }

  /// Görevin tek sonuç kartı. Modelin son tur metni ayrıca "AJAN" kartı olarak
  /// yayınlanmıyor; böylece aynı içerik iki kez görünmüyor.
  Widget _buildFinalCard(AgentEvent event) {
    final cancelled = event.cancelled;
    final accent = cancelled ? Colors.orangeAccent : Colors.greenAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1C20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: .35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(cancelled ? Icons.stop_circle_outlined : Icons.verified_outlined,
              size: 17, color: accent),
          const SizedBox(width: 8),
          Text(cancelled ? 'İPTAL EDİLDİ' : 'SONUÇ',
              style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: .6)),
          const Spacer(),
          if (_agent.lastResult != null)
            Text(
              '${_agent.lastResult!.modelCalls} tur · '
              '${(_agent.lastResult!.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} sn · '
              '${_agent.lastResult!.totalTokens} token',
              style: const TextStyle(
                  color: GeminiColors.textMuted, fontSize: 10.5),
            ),
        ]),
        const SizedBox(height: 10),
        MarkdownBody(
          data: event.message ?? '',
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(color: Colors.white, height: 1.5, fontSize: 14),
            code: const TextStyle(
                color: Colors.greenAccent,
                fontFamily: 'monospace',
                backgroundColor: Color(0xFF101318),
                fontSize: 12.5),
            codeblockDecoration: BoxDecoration(
              color: const Color(0xFF101318),
              borderRadius: BorderRadius.circular(8),
            ),
            listBullet: const TextStyle(color: Colors.white, fontSize: 14),
            h1: const TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
            h2: const TextStyle(
                color: Colors.white,
                fontSize: 15.5,
                fontWeight: FontWeight.w700),
            h3: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }

  Widget _buildStepCard(AgentStep step) {
    final expanded = _expandedSteps.contains(step.index);
    final (icon, color) = _toolVisual(step.toolName);
    final statusColor = _stepStatusColor(step.status);
    final statusLabel = switch (step.status) {
      AgentStepStatus.running => 'çalışıyor',
      AgentStepStatus.done => '${step.elapsed.inMilliseconds} ms',
      AgentStepStatus.error => 'hata',
      AgentStepStatus.denied => 'reddedildi',
      AgentStepStatus.cancelled => 'iptal',
    };

    final args = _clipBlock(step.argsSummary, maxChars: 220, maxLines: 6);
    final result = _clipBlock(step.result, maxChars: 320, maxLines: 10);

    // Kartın TAMAMINA dokununca küçülür/açılır. SelectableText kullanmıyoruz:
    // metin seçme hareketi dokunuşu yutup kartın açılmasını engelliyordu.
    return GestureDetector(
      key: ValueKey('step_card_${step.index}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        if (expanded) {
          _expandedSteps.remove(step.index);
        } else {
          _expandedSteps.add(step.index);
        }
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF15171B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: .07)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Text(step.toolName,
                style: TextStyle(
                    color: color,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5)),
            const SizedBox(width: 8),
            if (step.status == AgentStepStatus.running && _agent.isRunning)
              const SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 1.6))
            else
              Text('#${step.index}',
                  style: const TextStyle(
                      color: GeminiColors.textMuted, fontSize: 10.5)),
            const Spacer(),
            Text(statusLabel,
                style: TextStyle(
                    color: statusColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Icon(expanded ? Icons.unfold_less : Icons.unfold_more,
                key: ValueKey('expand_icon_${step.index}'),
                size: 17,
                color: GeminiColors.textMuted),
          ]),
          if (args.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              expanded ? step.argsSummary : args.text,
              style: const TextStyle(
                  color: Colors.white60,
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  height: 1.35),
            ),
          ],
          if (result.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFF101318),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                expanded ? step.result : result.text,
                style: TextStyle(
                    color: step.status == AgentStepStatus.error ||
                            step.status == AgentStepStatus.denied
                        ? Colors.redAccent.shade100
                        : Colors.greenAccent.shade100,
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.35),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  /// Uzun blokları hem karakter hem satır sayısıyla kısaltır. Kartın
  /// viewport'tan taşması dokunma davranışını bozduğu için satır sınırı da var.
  _ClippedText _clipBlock(String value,
      {required int maxChars, required int maxLines}) {
    if (value.isEmpty) return const _ClippedText('', false);
    final lines = value.split('\n');
    var text = value;
    var clipped = false;
    if (lines.length > maxLines) {
      text = lines.take(maxLines).join('\n');
      clipped = true;
    }
    if (text.length > maxChars) {
      text = text.substring(0, maxChars);
      clipped = true;
    }
    if (clipped) {
      final hiddenLines = lines.length - text.split('\n').length;
      final hiddenChars = value.length - text.length;
      text = '$text\n… ${hiddenLines > 0 ? '$hiddenLines satır, ' : ''}'
          '$hiddenChars karakter daha';
    }
    return _ClippedText(text, clipped);
  }

  (IconData, Color) _toolVisual(String tool) => switch (tool) {
        'update_plan' => (Icons.checklist_rounded, GeminiColors.geminiCyan),
        'memory' => (Icons.psychology_outlined, Colors.deepPurpleAccent),
        'shell' => (Icons.terminal, Colors.greenAccent),
        'termux' => (Icons.settings_ethernet, Colors.greenAccent),
        'run_code' => (Icons.play_circle_outline, Colors.lightBlueAccent),
        'read_file' => (Icons.description_outlined, Colors.white70),
        'write_file' => (Icons.edit_note, Colors.amberAccent),
        'edit_file' => (Icons.difference_outlined, Colors.amberAccent),
        'move_file' => (Icons.drive_file_move_outlined, Colors.orangeAccent),
        'list_dir' => (Icons.folder_outlined, Colors.white70),
        'search_files' => (Icons.search, Colors.white70),
        'web' => (Icons.public, Colors.lightBlueAccent),
        'music' => (Icons.music_note, Colors.pinkAccent),
        'phone' => (Icons.phone_android, Colors.tealAccent),
        'device' => (Icons.apps_outlined, Colors.cyanAccent),
        'remote_terminal' => (Icons.dns_outlined, Colors.deepPurpleAccent),
        _ => (Icons.build_outlined, Colors.white70),
      };

  Widget _card({
    required IconData icon,
    required Color color,
    required String title,
    required Widget child,
    Color? borderColor,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1C20),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: borderColor ?? Colors.white.withValues(alpha: .08)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: .6)),
          ]),
          const SizedBox(height: 9),
          child,
        ]),
      );

  Widget _buildComposer() => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1C20),
          border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: .08))),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: _taskController,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _startTask(),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Görev yaz: "uygulamaları listele, X\'i aç, not al"',
                hintStyle:
                    TextStyle(color: GeminiColors.textMuted, fontSize: 13.5),
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (_agent.isRunning)
            IconButton.filledTonal(
              style: IconButton.styleFrom(
                  backgroundColor: Colors.redAccent.withValues(alpha: .18)),
              icon: const Icon(Icons.stop_rounded, color: Colors.redAccent),
              tooltip: 'Durdur',
              onPressed: () {
                _agent.cancel();
                HapticFeedback.lightImpact();
              },
            )
          else
            IconButton.filled(
              icon: const Icon(Icons.arrow_upward),
              tooltip: 'Ajanı başlat',
              onPressed: _startTask,
            ),
        ]),
      );
}

class _ClippedText {
  final String text;
  final bool clipped;
  const _ClippedText(this.text, this.clipped);
}
