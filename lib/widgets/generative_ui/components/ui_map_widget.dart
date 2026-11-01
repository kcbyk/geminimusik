import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/generative_ui/ui_component_model.dart';
import '../../../theme/gemini_colors.dart';

class UiMapWidget extends StatelessWidget {
  final UiComponent component;

  const UiMapWidget({
    super.key,
    required this.component,
  });

  Future<void> _openExternalMap(double? lat, double? lng, String? query) async {
    Uri url;
    if (lat != null && lng != null) {
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    } else {
      final q = Uri.encodeComponent(query ?? 'Konum');
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    }
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = component.data;
    final title = (data['title'] ?? component.title ?? 'Konum').toString();
    final address = (data['address'] ?? component.subtitle ?? component.description ?? '').toString();
    final lat = (data['lat'] is num) ? (data['lat'] as num).toDouble() : null;
    final lng = (data['lng'] is num) ? (data['lng'] as num).toDouble() : null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Map Stylized Preview Box
          Container(
            height: 140,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A2634), Color(0xFF16202C), Color(0xFF111822)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                // Simulated grid streets
                Positioned.fill(
                  child: CustomPaint(
                    painter: _MapGridPainter(),
                  ),
                ),
                // Center Map Pin
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.redAccent.withValues(alpha: 0.5),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.location_on, size: 20, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Details & Button
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (address.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          address,
                          style: const TextStyle(
                            color: GeminiColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (lat != null && lng != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '$lat, $lng',
                          style: const TextStyle(
                            color: GeminiColors.geminiCyan,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ElevatedButton.styleFrom(
                  backgroundColor: GeminiColors.geminiBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ).let(
                  (style) => ElevatedButton.icon(
                    style: style,
                    icon: const Icon(Icons.directions, size: 16),
                    label: const Text('Haritada Aç', style: TextStyle(fontSize: 12)),
                    onPressed: () => _openExternalMap(lat, lng, address.isNotEmpty ? address : title),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    // Draw grid lines
    for (double x = 0; x < size.width; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

extension _LetExt<T> on T {
  R let<R>(R Function(T it) block) => block(this);
}
