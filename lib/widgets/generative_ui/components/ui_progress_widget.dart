import 'package:flutter/material.dart';
import '../../../models/generative_ui/ui_component_model.dart';
import '../../../theme/gemini_colors.dart';

class UiProgressWidget extends StatelessWidget {
  final UiComponent component;

  const UiProgressWidget({
    super.key,
    required this.component,
  });

  @override
  Widget build(BuildContext context) {
    final data = component.data;
    final isStepper = data['steps'] is List || data['timeline'] is List;

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
          if (component.title != null) ...[
            Row(
              children: [
                Icon(
                  isStepper ? Icons.timeline_rounded : Icons.pie_chart_outline_rounded,
                  size: 18,
                  color: GeminiColors.geminiCyan,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    component.title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (component.description != null) ...[
              const SizedBox(height: 4),
              Text(
                component.description!,
                style: const TextStyle(
                  color: GeminiColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 14),
          ],
          if (isStepper)
            _buildStepper(data['steps'] ?? data['timeline'])
          else
            _buildLinearProgress(data),
        ],
      ),
    );
  }

  Widget _buildLinearProgress(Map<String, dynamic> data) {
    final value = (data['value'] is num)
        ? (data['value'] as num).toDouble()
        : double.tryParse(data['percent']?.toString().replaceAll('%', '') ?? '50') ?? 50.0;

    final normalized = (value > 1.0) ? (value / 100.0).clamp(0.0, 1.0) : value.clamp(0.0, 1.0);
    final percentText = '${(normalized * 100).toInt()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              data['label']?.toString() ?? 'İlerleme',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              percentText,
              style: const TextStyle(
                color: GeminiColors.geminiCyan,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: normalized,
            minHeight: 10,
            backgroundColor: const Color(0xFF141414),
            valueColor: const AlwaysStoppedAnimation<Color>(GeminiColors.geminiBlue),
          ),
        ),
      ],
    );
  }

  Widget _buildStepper(dynamic rawSteps) {
    if (rawSteps is! List) return const SizedBox.shrink();
    final steps = rawSteps.whereType<Map<String, dynamic>>().toList();

    return Column(
      children: List.generate(steps.length, (idx) {
        final s = steps[idx];
        final title = (s['title'] ?? s['name'] ?? s['label'] ?? 'Adım ${idx + 1}').toString();
        final subtitle = s['description']?.toString() ?? s['subtitle']?.toString();
        final status = (s['status'] ?? (idx == 0 ? 'completed' : 'pending')).toString().toLowerCase();

        final isCompleted = status == 'completed' || status == 'done';
        final isCurrent = status == 'active' || status == 'current' || status == 'in_progress';
        final isLast = idx == steps.length - 1;

        Color circleColor;
        Widget circleChild;

        if (isCompleted) {
          circleColor = Colors.green;
          circleChild = const Icon(Icons.check, size: 14, color: Colors.white);
        } else if (isCurrent) {
          circleColor = GeminiColors.geminiBlue;
          circleChild = Text(
            '${idx + 1}',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          );
        } else {
          circleColor = Colors.white.withValues(alpha: 0.15);
          circleChild = Text(
            '${idx + 1}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: circleColor,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: circleChild,
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: isCompleted ? Colors.green.withValues(alpha: 0.5) : Colors.white12,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isCurrent ? Colors.white : Colors.white70,
                          fontSize: 13,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
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
              ),
            ],
          ),
        );
      }),
    );
  }
}
