import 'package:flutter/material.dart';

/// Streaming yükleme göstergesi — 3 noktalı animasyonlu bileşen.
/// AI cevabı gelirken gösterilir.
class UiStreamingIndicator extends StatefulWidget {
  final String label;

  const UiStreamingIndicator({
    super.key,
    this.label = 'Yanıt oluşturuluyor',
  });

  @override
  State<UiStreamingIndicator> createState() => _UiStreamingIndicatorState();
}

class _UiStreamingIndicatorState extends State<UiStreamingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  static const int _dotCount = 3;
  static const Duration _delay = Duration(milliseconds: 200);
  static const Duration _duration = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      _dotCount,
      (i) => AnimationController(vsync: this, duration: _duration),
    );
    _animations = _controllers
        .map((c) => Tween<double>(begin: 0.3, end: 1.0).animate(
              CurvedAnimation(parent: c, curve: Curves.easeInOut),
            ))
        .toList();

    for (var i = 0; i < _dotCount; i++) {
      Future.delayed(_delay * i, () {
        if (mounted) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Gemini renk gradyanı ile pulsar ikon
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF8AB4F8), Color(0xFFC58AF9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8AB4F8).withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text(
            widget.label,
            style: const TextStyle(
              color: Color(0xFF9AA0A6),
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 6),
          // Animasyonlu noktalar
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_dotCount, (i) {
              return AnimatedBuilder(
                animation: _animations[i],
                builder: (ctx, _) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(
                      const Color(0xFF5F6368),
                      const Color(0xFF8AB4F8),
                      _animations[i].value,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
