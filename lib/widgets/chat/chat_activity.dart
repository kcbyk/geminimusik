import 'package:flutter/material.dart';

import '../../theme/chat_ui.dart';

/// ChatGPT'deki "9s düşündü ⌄" satırının karşılığı.
///
/// Yanıtın üzerinde duran, sakin ve tek satırlık bir özet; dokununca modelin
/// o yanıtı üretirken yaptığı işi (düşünme, web araması, okunan kaynak sayısı)
/// adım adım gösterir.
class ChatActivityRow extends StatefulWidget {
  /// Yanıtın üretilmesi ne kadar sürdü?
  final Duration? thinking;

  /// Kaç web sitesi tarandı?
  final int sourceCount;

  /// Arama sorgusu (varsa).
  final String? searchQuery;

  /// Modele özgü ek adımlar ("İçerik değerlendiriliyor" gibi).
  final List<String> extraSteps;

  const ChatActivityRow({
    super.key,
    this.thinking,
    this.sourceCount = 0,
    this.searchQuery,
    this.extraSteps = const [],
  });

  @override
  State<ChatActivityRow> createState() => _ChatActivityRowState();
}

class _ChatActivityRowState extends State<ChatActivityRow> {
  bool _expanded = false;

  String get _header {
    final parts = <String>[];
    if (widget.thinking != null && widget.thinking!.inSeconds >= 1) {
      parts.add('${widget.thinking!.inSeconds}s düşündü');
    } else if (widget.thinking != null) {
      parts.add('Düşündü');
    }
    if (widget.sourceCount > 0) {
      parts.add('${widget.sourceCount} web sitesi arandı');
    }
    if (parts.isEmpty) return 'Yanıt hazırlandı';
    return parts.join(' · ');
  }

  List<String> get _steps {
    final steps = <String>[...widget.extraSteps];
    if (widget.searchQuery != null && widget.searchQuery!.trim().isNotEmpty) {
      steps.add('Arama: ${widget.searchQuery!.trim()}');
    }
    if (widget.sourceCount > 0) {
      steps.add('${widget.sourceCount} web sitesi tarandı');
    }
    if (widget.thinking != null) {
      steps.add(
        'Yanıt ${(widget.thinking!.inMilliseconds / 1000).toStringAsFixed(1)} saniyede üretildi',
      );
    }
    return steps;
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final canExpand = steps.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: canExpand ? () => setState(() => _expanded = !_expanded) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_awesome_outlined,
                    size: 14,
                    color: ChatUi.textMuted,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      _header,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ChatUi.textMuted,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ),
                  if (canExpand) ...[
                    const SizedBox(width: 3),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: ChatUi.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.only(left: 21, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final step in steps)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: ChatUi.textMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              step,
                              style: const TextStyle(
                                color: ChatUi.textMuted,
                                fontSize: 12.5,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }
}

/// Yanıt üretilirken gösterilen canlı satır: parıldayan "Düşünüyor" + tarama.
class ChatThinkingRow extends StatefulWidget {
  final String label;
  final List<String> scanningDomains;

  const ChatThinkingRow({
    super.key,
    this.label = 'Düşünüyor',
    this.scanningDomains = const [],
  });

  @override
  State<ChatThinkingRow> createState() => _ChatThinkingRowState();
}

class _ChatThinkingRowState extends State<ChatThinkingRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = _controller.value;
                  return ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: const [
                        ChatUi.textMuted,
                        Color(0xFFE8E8E8),
                        ChatUi.textMuted,
                      ],
                      stops: const [0.1, 0.5, 0.9],
                      begin: Alignment(-1 - 2 * (1 - t), 0),
                      end: Alignment(1 - 2 * (1 - t), 0),
                    ).createShader(bounds),
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        color: ChatUi.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: ChatUi.textMuted,
                ),
              ),
            ],
          ),
          if (widget.scanningDomains.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: widget.scanningDomains
                    .map(
                      (domain) => Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: ChatUi.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: ChatUi.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Favicon(domain: domain, size: 13),
                            const SizedBox(width: 6),
                            Text(
                              domain,
                              style: const TextStyle(
                                color: ChatUi.textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Favicon yükleyici (Google favicon servisi, hatada küre ikonu).
class _Favicon extends StatelessWidget {
  final String domain;
  final double size;

  const _Favicon({required this.domain, this.size = 14});

  @override
  Widget build(BuildContext context) {
    if (domain.isEmpty) {
      return Icon(Icons.public_rounded, size: size, color: ChatUi.textMuted);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image.network(
        'https://www.google.com/s2/favicons?domain=$domain&sz=64',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.public_rounded, size: size, color: ChatUi.textMuted),
      ),
    );
  }
}
