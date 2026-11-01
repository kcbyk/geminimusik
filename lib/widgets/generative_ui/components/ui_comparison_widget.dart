import 'package:flutter/material.dart';
import '../../../models/generative_ui/ui_action_model.dart';
import '../../../models/generative_ui/ui_component_model.dart';
import '../../../theme/gemini_colors.dart';
import 'ui_buttons_widget.dart';

class UiComparisonWidget extends StatelessWidget {
  final UiComponent component;
  final void Function(UiAction action)? onAction;

  const UiComparisonWidget({
    super.key,
    required this.component,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final data = component.data;
    final items = (data['items'] is List)
        ? (data['items'] as List).whereType<Map<String, dynamic>>().toList()
        : (data['options'] is List)
            ? (data['options'] as List).whereType<Map<String, dynamic>>().toList()
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
          if (component.title != null) ...[
            Row(
              children: [
                const Icon(Icons.compare_arrows_rounded, size: 20, color: GeminiColors.geminiCyan),
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
            if (component.description != null) ...[
              const SizedBox(height: 4),
              Text(
                component.description!,
                style: const TextStyle(color: GeminiColors.textMuted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: items.map((it) => _buildComparisonCard(context, it)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonCard(BuildContext context, Map<String, dynamic> item) {
    final title = (item['title'] ?? item['name'] ?? 'Seçenek').toString();
    final subtitle = item['subtitle']?.toString();
    final price = item['price']?.toString();
    final isRecommended = item['recommended'] == true || item['isPopular'] == true;
    final badge = item['badge']?.toString() ?? (isRecommended ? 'Önerilen' : null);

    final features = (item['features'] is List)
        ? (item['features'] as List).map((f) => f.toString()).toList()
        : <String>[];
    final pros = (item['pros'] is List)
        ? (item['pros'] as List).map((p) => p.toString()).toList()
        : <String>[];
    final cons = (item['cons'] is List)
        ? (item['cons'] as List).map((c) => c.toString()).toList()
        : <String>[];

    final actions = <UiAction>[];
    if (item['actions'] is List) {
      for (final a in item['actions']) {
        if (a is Map<String, dynamic>) actions.add(UiAction.fromJson(a));
      }
    } else if (item['action'] is Map<String, dynamic>) {
      actions.add(UiAction.fromJson(item['action']));
    } else {
      actions.add(UiAction(
        type: 'prompt',
        label: '$title Seç',
        value: '$title seçeneğini tercih ediyorum, bu tasarımla devam edelim.',
      ));
    }

    return Container(
      width: 240,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isRecommended ? const Color(0xFF192433) : const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRecommended
              ? GeminiColors.geminiBlue
              : Colors.white.withValues(alpha: 0.08),
          width: isRecommended ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (badge != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isRecommended
                      ? GeminiColors.geminiBlue
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(color: GeminiColors.textMuted, fontSize: 11),
            ),
          ],
          if (price != null) ...[
            const SizedBox(height: 8),
            Text(
              price,
              style: const TextStyle(
                color: GeminiColors.geminiCyan,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
          const SizedBox(height: 10),
          if (features.isNotEmpty) ...[
            ...features.map((f) => _buildCheckItem(f, Icons.check, Colors.greenAccent)),
            const SizedBox(height: 6),
          ],
          if (pros.isNotEmpty) ...[
            ...pros.map((p) => _buildCheckItem(p, Icons.add, GeminiColors.geminiCyan)),
            const SizedBox(height: 6),
          ],
          if (cons.isNotEmpty) ...[
            ...cons.map((c) => _buildCheckItem(c, Icons.remove, Colors.redAccent)),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 10),
          UiButtonsWidget(actions: actions, onAction: onAction),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String text, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Color(0xFFDDDDDD), fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}
