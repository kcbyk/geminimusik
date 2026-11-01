import 'package:flutter/material.dart';
import '../../../models/generative_ui/ui_action_model.dart';
import '../../../models/generative_ui/ui_component_model.dart';
import '../../../theme/gemini_colors.dart';
import 'ui_buttons_widget.dart';
import 'ui_chart_widget.dart';

class UiDashboardWidget extends StatelessWidget {
  final UiComponent component;
  final void Function(UiAction action)? onAction;

  const UiDashboardWidget({
    super.key,
    required this.component,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final data = component.data;
    final title = (data['title'] ?? component.title ?? 'Yönetim Paneli').toString();
    final subtitle = data['subtitle']?.toString() ?? component.subtitle;

    final stats = (data['stats'] is List)
        ? (data['stats'] as List).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    final activities = (data['activities'] is List)
        ? (data['activities'] as List).whereType<Map<String, dynamic>>().toList()
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
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: GeminiColors.geminiBlue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.dashboard_rounded, size: 18, color: GeminiColors.geminiCyan),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subtitle != null) ...[
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: GeminiColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Stats Grid
          if (stats.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: stats.map((s) => _buildStatTile(s)).toList(),
            ),
            const SizedBox(height: 14),
          ],

          // Chart if data exists
          if (data['chart'] is Map<String, dynamic>) ...[
            UiChartWidget(
              component: UiComponent.fromJson(data['chart'] as Map<String, dynamic>),
            ),
            const SizedBox(height: 14),
          ],

          // Recent Activities / Logs
          if (activities.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Son Aktiviteler',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...activities.map((act) {
                    final text = (act['text'] ?? act['title'] ?? '').toString();
                    final time = (act['time'] ?? '').toString();

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(Icons.circle, size: 6, color: GeminiColors.geminiCyan),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    text,
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (time.isNotEmpty) ...[
                            Text(
                              time,
                              style: const TextStyle(color: GeminiColors.textMuted, fontSize: 10),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Action buttons
          if (component.actions.isNotEmpty)
            UiButtonsWidget(actions: component.actions, onAction: onAction),
        ],
      ),
    );
  }

  Widget _buildStatTile(Map<String, dynamic> s) {
    final label = (s['label'] ?? s['name'] ?? '').toString();
    final value = (s['value'] ?? '').toString();
    final change = s['change']?.toString();
    final isPos = change != null && !change.startsWith('-');

    return Container(
      width: 140,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: GeminiColors.textMuted, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          if (change != null) ...[
            const SizedBox(height: 2),
            Text(
              change,
              style: TextStyle(
                color: isPos ? Colors.greenAccent : Colors.redAccent,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
