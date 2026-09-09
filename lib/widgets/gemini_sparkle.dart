import 'package:flutter/material.dart';
import '../theme/gemini_colors.dart';

class GeminiSparkleIcon extends StatelessWidget {
  final double size;
  const GeminiSparkleIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => GeminiColors.sparkGradient.createShader(bounds),
      child: Icon(
        Icons.auto_awesome,
        size: size,
        color: Colors.white,
      ),
    );
  }
}
