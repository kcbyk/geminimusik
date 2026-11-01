import 'package:flutter/material.dart';
import '../../../models/generative_ui/ui_component_model.dart';
import '../../../theme/gemini_colors.dart';

class UiChartWidget extends StatelessWidget {
  final UiComponent component;

  const UiChartWidget({
    super.key,
    required this.component,
  });

  @override
  Widget build(BuildContext context) {
    final data = component.data;

    final metrics = (data['metrics'] is List)
        ? (data['metrics'] as List).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    final series = (data['series'] is List)
        ? (data['series'] as List).whereType<Map<String, dynamic>>().toList()
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
          // Başlık
          if (component.title != null) ...[
            Row(
              children: [
                const Icon(Icons.bar_chart_rounded, size: 20, color: GeminiColors.geminiCyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    component.title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (component.subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                component.subtitle!,
                style: const TextStyle(
                  color: GeminiColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 14),
          ],

          // Metrik Sayaç Kartları (Varsa)
          if (metrics.isNotEmpty) ...[
            _buildMetricsRow(metrics),
            const SizedBox(height: 16),
          ],

          // Grafik Görünümü
          if (series.isNotEmpty || data['data'] is List)
            _buildBarChart(series.isNotEmpty
                ? series
                : (data['data'] as List).whereType<Map<String, dynamic>>().toList()),
        ],
      ),
    );
  }

  Widget _buildMetricsRow(List<Map<String, dynamic>> metrics) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: metrics.map((m) {
        final label = (m['label'] ?? m['name'] ?? '').toString();
        final value = (m['value'] ?? '').toString();
        final change = m['change']?.toString();
        final isPositive = change != null && !change.startsWith('-');

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: GeminiColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (change != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isPositive ? Colors.green : Colors.redAccent).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                            size: 10,
                            color: isPositive ? Colors.greenAccent : Colors.redAccent,
                          ),
                          Text(
                            change,
                            style: TextStyle(
                              color: isPositive ? Colors.greenAccent : Colors.redAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBarChart(List<Map<String, dynamic>> dataPoints) {
    if (dataPoints.isEmpty) return const SizedBox.shrink();

    // En yüksek değeri bul
    double maxValue = 1.0;
    for (final p in dataPoints) {
      final val = (p['value'] is num) ? (p['value'] as num).toDouble() : 0.0;
      if (val > maxValue) maxValue = val;
    }

    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: dataPoints.map((item) {
          final label = (item['label'] ?? item['name'] ?? '').toString();
          final rawVal = (item['value'] is num) ? (item['value'] as num).toDouble() : 0.0;
          final heightRatio = (rawVal / maxValue).clamp(0.05, 1.0);
          final barColor = (item['color'] != null)
              ? _parseColor(item['color'].toString()) ?? GeminiColors.geminiBlue
              : GeminiColors.geminiBlue;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    rawVal >= 1000 ? '${(rawVal / 1000).toStringAsFixed(1)}k' : rawVal.toStringAsFixed(0),
                    style: const TextStyle(
                      color: GeminiColors.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: heightRatio,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [barColor, barColor.withValues(alpha: 0.6)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            boxShadow: [
                              BoxShadow(
                                color: barColor.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
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
