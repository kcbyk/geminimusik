import 'package:flutter/material.dart';

import '../services/agent_terminal_service.dart';
import '../services/gemini_service.dart';
import '../theme/gemini_colors.dart';

class AgentScreen extends StatefulWidget {
  final VoidCallback? onOpenSidebar;
  const AgentScreen({super.key, this.onOpenSidebar});

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  final _taskController = TextEditingController();
  final _terminalController = TextEditingController();
  final _gemini = GeminiService();
  final _terminal = AgentTerminalService();
  final List<_AgentEvent> _events = [];
  bool _isThinking = false;
  bool _isRunning = false;
  String? _suggestedCommand;

  @override
  void dispose() {
    _taskController.dispose();
    _terminalController.dispose();
    super.dispose();
  }

  Future<void> _startTask() async {
    final task = _taskController.text.trim();
    if (task.isEmpty || _isThinking) return;
    setState(() {
      _events.add(_AgentEvent('Görev', task, _EventKind.task));
      _isThinking = true;
      _suggestedCommand = null;
      _taskController.clear();
    });
    try {
      const agentSystemPrompt = '''
Sen güvenli bir yazılım ajanısın. Kullanıcının görevini analiz et, uygulanabilir planı ve kontrol adımlarını Türkçe ver.
Terminal gerektiğinde yalnızca bir adet öneri komutunu son satırda [TOOL:TERMINAL:komut] biçiminde yaz. Asla komutu çalıştırdığını iddia etme; kullanıcı komutu inceleyip onaylar. Yıkıcı komutlar (silme, formatlama, kimlik bilgisi gösterme) önermeden önce kullanıcıdan açık onay iste.
''';
      final response = await _gemini.sendMessage(
        prompt: task,
        history: const [],
        model: 'gemini-2.5-flash',
        customSystemPrompt: agentSystemPrompt,
      );
      final match =
          RegExp(r'\[TOOL:TERMINAL:(.+?)\]').firstMatch(response.text);
      final answer =
          response.text.replaceAll(RegExp(r'\[TOOL:TERMINAL:.+?\]'), '').trim();
      if (!mounted) return;
      setState(() {
        _events.add(_AgentEvent('Ajan', answer, _EventKind.agent));
        _suggestedCommand = match?.group(1)?.trim();
        if (_suggestedCommand != null) {
          _terminalController.text = _suggestedCommand!;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _events.add(
          _AgentEvent('Ajan', 'Görev işlenemedi: $error', _EventKind.error)));
    } finally {
      if (mounted) setState(() => _isThinking = false);
    }
  }

  Future<void> _runTerminal() async {
    final command = _terminalController.text.trim();
    if (command.isEmpty || _isRunning) return;
    setState(() {
      _events
          .add(_AgentEvent('\$ $command', 'çalışıyor…', _EventKind.terminal));
      _isRunning = true;
    });
    final output = await _terminal.run(command);
    if (!mounted) return;
    setState(() {
      _events.removeLast();
      _events.add(_AgentEvent('\$ $command', output, _EventKind.terminal));
      _isRunning = false;
    });
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
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: _statusChip()),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _events.isEmpty ? _buildEmptyState() : _buildTimeline(),
            ),
            _buildTerminal(),
            _buildTaskComposer(),
          ],
        ),
      ),
    );
  }

  Widget _statusChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: (_terminal.isConfigured ? Colors.green : Colors.orange)
              .withValues(alpha: .15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _terminal.isConfigured ? 'Terminal bağlı' : 'Plan modu',
          style: TextStyle(
            color: _terminal.isConfigured
                ? Colors.greenAccent
                : Colors.orangeAccent,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _buildEmptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.auto_awesome, size: 46, color: GeminiColors.geminiCyan),
            SizedBox(height: 14),
            Text('Bir görev verin',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text(
                'Ajan planı çıkarır, komut önerir ve yalnızca sizin onayınızla terminal yürütücüsüne gönderir.',
                textAlign: TextAlign.center,
                style: TextStyle(color: GeminiColors.textMuted, height: 1.45)),
          ]),
        ),
      );

  Widget _buildTimeline() => ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: _events.length + (_isThinking ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _events.length) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Row(children: [
                SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Ajan düşünüyor…',
                    style: TextStyle(color: GeminiColors.textMuted))
              ]),
            );
          }
          final event = _events[index];
          final isTerminal = event.kind == _EventKind.terminal;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isTerminal
                  ? const Color(0xFF101318)
                  : const Color(0xFF1B1C20),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: event.kind == _EventKind.error
                      ? Colors.redAccent.withValues(alpha: .5)
                      : Colors.white.withValues(alpha: .08)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(event.title,
                  style: TextStyle(
                      color: isTerminal
                          ? Colors.greenAccent
                          : GeminiColors.geminiCyan,
                      fontFamily: isTerminal ? 'monospace' : null,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
              const SizedBox(height: 7),
              SelectableText(event.body,
                  style: TextStyle(
                      color: event.kind == _EventKind.error
                          ? Colors.redAccent
                          : Colors.white,
                      fontFamily: isTerminal ? 'monospace' : null,
                      height: 1.4)),
            ]),
          );
        },
      );

  Widget _buildTerminal() => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: const Color(0xFF101318),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: .1))),
        child: Row(children: [
          const Text(r'$',
              style: TextStyle(
                  color: Colors.greenAccent,
                  fontFamily: 'monospace',
                  fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: _terminalController,
                  style: const TextStyle(
                      color: Colors.white, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Komut önerisi veya komut girin',
                      hintStyle: TextStyle(color: GeminiColors.textMuted)),
                  onSubmitted: (_) => _runTerminal())),
          IconButton(
              icon: _isRunning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded),
              color: GeminiColors.geminiCyan,
              tooltip: 'Komutu çalıştır',
              onPressed: _isRunning ? null : _runTerminal),
        ]),
      );

  Widget _buildTaskComposer() => Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
            color: const Color(0xFF1B1C20),
            border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: .08)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
              child: TextField(
                  controller: _taskController,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText:
                          'Örn. Bu Flutter hatasını analiz et ve çözüm planı çıkar',
                      hintStyle: TextStyle(color: GeminiColors.textMuted)))),
          IconButton.filled(
              icon: const Icon(Icons.arrow_upward),
              onPressed: _isThinking ? null : _startTask,
              tooltip: 'Ajanı başlat'),
        ]),
      );
}

enum _EventKind { task, agent, terminal, error }

class _AgentEvent {
  final String title;
  final String body;
  final _EventKind kind;
  const _AgentEvent(this.title, this.body, this.kind);
}
