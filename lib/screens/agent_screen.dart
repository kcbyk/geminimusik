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

/// Ekran durumu. Testlerin iç durumu (açık adımlar) doğrulayabilmesi için
/// bilerek public; uygulama kodu buna dokunmaz.
@visibleForTesting
class AgentScreenState extends State<AgentScreen> {
  final _taskController = TextEditingController();
  final AgentController _agent = AgentController();
  final _scrollController = ScrollController();
  final Set<int> _expandedSteps = {};
  StreamSubscription<dynamic>? _approvalSub;
  bool _approvalDialogOpen = false;

  /// Test kancası: hangi adımların açıldığını doğrulamak için.
  @visibleForTesting
  Set<int> get debugExpandedSteps => Set.unmodifiable(_expandedSteps);

  /// Test kancası: aç/kapat durumunu setState üzerinden değiştirir.
  @visibleForTesting
  void debugToggleStep(int index) => setState(() {
        if (!_expandedSteps.remove(index)) _expandedSteps.add(index);
      });

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
                    child: SelectableText(
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
                        style:
                            TextStyle(color: Colors.white70, fontSize: 13)),
                    onChanged: (value) =>
                        setLocalState(() => always = value ?? false),
                  ),
                ]),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, ApprovalDecision.deny),
              child:
                  const Text('Reddet', style: TextStyle(color: Colors.redAccent)),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: GeminiColors.geminiCyan),
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
          Center(child: _statusChip()),
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
                  _agent.allowUnrestrictedPaths ? Icons.folder_open : Icons.folder,
                  'Sınırsız dosya erişimi: '
                      '${_agent.allowUnrestrictedPaths ? 'AÇIK' : 'kapalı'}',
                  _agent.allowUnrestrictedPaths,
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: _menuItem(
                    Icons.delete_sweep_outlined, 'Zaman çizelgesini temizle', false),
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
            Expanded(
              child: _agent.events.isEmpty ? _buildEmptyState() : _buildTimeline(),
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
    }
  }

  Widget _statusChip() {
    final running = _agent.isRunning;
    final color = running ? GeminiColors.geminiCyan : Colors.greenAccent;
    final label = running
        ? 'Adım ${_agent.steps.length}/${_agent.maxSteps}'
        : '${_agent.toolCount} araç hazır';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (running)
          const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(strokeWidth: 1.6))
        else
          Icon(Icons.circle, size: 7, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
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
              'Ajan plan çıkarır, dosya yazar/taşır, kabukta komut çalıştırır, '
              'sonucu kendi doğrular. Riskli adımda sana sorar.\n\n'
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
                      'Çalışma alanında notlar klasörü oluştur, içine bugün yapılacaklar dosyası yaz ve doğrula'),
                  _suggestion('Pil durumuna bak, sonra feneri aç ve kapat'),
                  _suggestion('Duman - Bu Akşam Ölürüm şarkısını bul ve indir'),
                  _suggestion(
                      'Bir sh scripti yaz, çalıştır ve çıktısını doğrula'),
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

  Widget _buildTimeline() {
    if (_agent.isRunning || _agent.events.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
      itemCount: _agent.events.length + (_agent.plan.isEmpty ? 0 : 1),
      itemBuilder: (context, index) {
        if (_agent.plan.isNotEmpty && index == 0) return _buildPlanCard();
        final offset = _agent.plan.isEmpty ? 0 : 1;
        return _buildEventCard(_agent.events[index - offset]);
      },
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

  Widget _buildPlanCard() {
    final plan = _agent.plan;
    final done = plan.where((p) => p.status == 'done').length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1C20),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: GeminiColors.geminiCyan.withValues(alpha: .25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.checklist_rounded,
              size: 17, color: GeminiColors.geminiCyan),
          const SizedBox(width: 8),
          const Text('PLAN',
              style: TextStyle(
                  color: GeminiColors.geminiCyan,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: .6)),
          const Spacer(),
          Text('$done/${plan.length}',
              style:
                  const TextStyle(color: GeminiColors.textMuted, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        for (final item in plan) _planRow(item),
      ]),
    );
  }

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
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1C20),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: (event.cancelled
                        ? Colors.orangeAccent
                        : Colors.greenAccent)
                    .withValues(alpha: .35)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(
                  event.cancelled
                      ? Icons.stop_circle_outlined
                      : Icons.verified_outlined,
                  size: 17,
                  color: event.cancelled
                      ? Colors.orangeAccent
                      : Colors.greenAccent),
              const SizedBox(width: 8),
              Text(event.cancelled ? 'İPTAL EDİLDİ' : 'SONUÇ',
                  style: TextStyle(
                      color: event.cancelled
                          ? Colors.orangeAccent
                          : Colors.greenAccent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: .6)),
              const Spacer(),
              if (_agent.lastResult != null)
                Text(
                  '${_agent.lastResult!.modelCalls} model turu · '
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
                p: const TextStyle(
                    color: Colors.white, height: 1.5, fontSize: 14),
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
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700),
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
        // Plan üstteki sabit kartta gösteriliyor.
        return const SizedBox.shrink();
    }
  }

  Widget _buildStepCard(AgentStep step) {
    final expanded = _expandedSteps.contains(step.index);
    final (icon, color) = _toolVisual(step.toolName);
    final statusColor = switch (step.status) {
      AgentStepStatus.running => GeminiColors.geminiCyan,
      AgentStepStatus.done => Colors.greenAccent,
      AgentStepStatus.error => Colors.redAccent,
      AgentStepStatus.denied => Colors.orangeAccent,
      AgentStepStatus.cancelled => Colors.grey,
    };
    final statusLabel = switch (step.status) {
      AgentStepStatus.running => 'çalışıyor',
      AgentStepStatus.done => '${step.elapsed.inMilliseconds} ms',
      AgentStepStatus.error => 'hata',
      AgentStepStatus.denied => 'reddedildi',
      AgentStepStatus.cancelled => 'iptal',
    };

    final args = _clipBlock(step.argsSummary, maxChars: 220, maxLines: 6);
    final result = _clipBlock(step.result, maxChars: 320, maxLines: 10);

    return Container(
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
          if (step.status == AgentStepStatus.running)
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
          if (args.clipped || result.clipped)
            IconButton(
              key: ValueKey('expand_${step.index}'),
              visualDensity: VisualDensity.compact,
              iconSize: 17,
              tooltip: expanded ? 'Kısalt' : 'Tamamını göster',
              // İkona key VERMİYORUZ: sabit key Flutter'ın aynı Icon State'ini
              // yeniden kullanmasına yol açıp düğmenin dokunma davranışını
              // bozuyor.
              icon: Icon(
                expanded ? Icons.unfold_less : Icons.unfold_more,
                color: GeminiColors.textMuted,
              ),
              onPressed: () => setState(() {
                if (expanded) {
                  _expandedSteps.remove(step.index);
                } else {
                  _expandedSteps.add(step.index);
                }
              }),
            ),
        ]),
        if (args.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectableText(
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
            child: SelectableText(
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
    );
  }

  /// Uzun blokları hem karakter hem satır sayısıyla kısaltır. Kartın
  /// viewport'tan taşması Flutter'ın dokunma testini bozduğu için satır
  /// sınırı da koyuyoruz.
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
        'shell' => (Icons.terminal, Colors.greenAccent),
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
          border:
              Border.all(color: borderColor ?? Colors.white.withValues(alpha: .08)),
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
          border:
              Border(top: BorderSide(color: Colors.white.withValues(alpha: .08))),
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
                hintText: 'Görev yaz: "şu klasörü kur, dosyaları taşı, test et"',
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
