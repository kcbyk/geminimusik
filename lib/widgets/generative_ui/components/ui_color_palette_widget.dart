import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/generative_ui/ui_component_model.dart';
import '../../../theme/gemini_colors.dart';

class UiColorPaletteWidget extends StatelessWidget {
  final UiComponent component;

  const UiColorPaletteWidget({
    super.key,
    required this.component,
  });

  @override
  Widget build(BuildContext context) {
    final data = component.data;
    final colors = (data['colors'] is List)
        ? (data['colors'] as List).whereType<Map<String, dynamic>>().toList()
        : (data['palette'] is List)
            ? (data['palette'] as List).whereType<Map<String, dynamic>>().toList()
            : <Map<String, dynamic>>[];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_outlined, size: 18, color: GeminiColors.geminiCyan),
              const SizedBox(width: 8),
              Text(
                component.title ?? 'Renk Paleti',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (component.description != null) ...[
            const SizedBox(height: 4),
            Text(
              component.description!,
              style: const TextStyle(color: GeminiColors.textMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: colors.map((c) => _buildColorSwatch(context, c)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildColorSwatch(BuildContext context, Map<String, dynamic> c) {
    final hex = (c['hex'] ?? c['color'] ?? '#1A73E8').toString();
    final name = (c['name'] ?? c['label'] ?? 'Renk').toString();
    final role = c['role']?.toString();
    final color = _parseColor(hex) ?? GeminiColors.geminiBlue;

    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: hex));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$hex panoya kopyalandı'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 130,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 48,
              width: double.infinity,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  hex.toUpperCase(),
                  style: const TextStyle(
                    color: GeminiColors.geminiCyan,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const Icon(Icons.copy, size: 11, color: Colors.white38),
              ],
            ),
            if (role != null) ...[
              Text(
                role,
                style: const TextStyle(
                  color: GeminiColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color? _parseColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return null;
    }
  }
}
