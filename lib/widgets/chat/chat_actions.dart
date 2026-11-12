import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/chat_ui.dart';

/// Yanıt altındaki aksiyon satırı (ChatGPT'nin ikon şeridi).
///
/// Kopyala, beğen/beğenme, sesli dinle, yeniden üret ve paylaş; hepsi aynı
/// 32 px'lik yumuşak daireler hâlinde. Geri bildirim düğmelerinde seçim
/// durumu kalıcı olarak vurgulanır.
class ChatMessageActions extends StatefulWidget {
  final String rawText;
  final bool? feedback; // true = olumlu, false = olumsuz
  final VoidCallback? onFeedbackChanged;
  final VoidCallback? onRegenerate;
  final VoidCallback? onSpeak;
  final bool isSpeaking;
  final VoidCallback? onShare;

  const ChatMessageActions({
    super.key,
    required this.rawText,
    this.feedback,
    this.onFeedbackChanged,
    this.onRegenerate,
    this.onSpeak,
    this.isSpeaking = false,
    this.onShare,
  });

  @override
  State<ChatMessageActions> createState() => _ChatMessageActionsState();
}

class _ChatMessageActionsState extends State<ChatMessageActions> {
  bool? _feedback;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _feedback = widget.feedback;
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.rawText));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Metin panoya kopyalandı'),
        duration: Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _vote(bool value) {
    setState(() => _feedback = _feedback == value ? null : value);
    widget.onFeedbackChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          _ActionButton(
            icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
            tooltip: _copied ? 'Kopyalandı' : 'Kopyala',
            active: _copied,
            onTap: _copy,
          ),
          _ActionButton(
            icon: _feedback == true
                ? Icons.thumb_up_rounded
                : Icons.thumb_up_alt_outlined,
            tooltip: 'İyi yanıt',
            active: _feedback == true,
            onTap: () => _vote(true),
          ),
          _ActionButton(
            icon: _feedback == false
                ? Icons.thumb_down_rounded
                : Icons.thumb_down_alt_outlined,
            tooltip: 'Kötü yanıt',
            active: _feedback == false,
            onTap: () => _vote(false),
          ),
          if (widget.onSpeak != null)
            _ActionButton(
              icon: widget.isSpeaking
                  ? Icons.volume_up_rounded
                  : Icons.volume_up_outlined,
              tooltip: widget.isSpeaking ? 'Seslendirmeyi durdur' : 'Sesli dinle',
              active: widget.isSpeaking,
              onTap: widget.onSpeak!,
            ),
          if (widget.onRegenerate != null)
            _ActionButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Yeniden üret',
              onTap: widget.onRegenerate!,
            ),
          if (widget.onShare != null)
            _ActionButton(
              icon: Icons.ios_share_rounded,
              tooltip: 'Paylaş',
              onTap: widget.onShare!,
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(right: 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(
              icon,
              size: 17,
              color: active ? ChatUi.accent : ChatUi.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
