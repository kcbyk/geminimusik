import 'package:flutter/material.dart';
import '../../../models/generative_ui/ui_action_model.dart';
import '../../../models/generative_ui/ui_component_model.dart';

/// Bilgi/servis/öneri kartı bileşeni.
/// "info_card", "service_card", "recommendation_card" tiplerine karşılık gelir.
class UiInfoCardWidget extends StatelessWidget {
  final UiComponent component;
  final void Function(UiAction action)? onAction;

  const UiInfoCardWidget({
    super.key,
    required this.component,
    this.onAction,
  });

  static const _iconMap = <String, IconData>{
    'info': Icons.info_outline_rounded,
    'service': Icons.miscellaneous_services_rounded,
    'recommendation': Icons.recommend_rounded,
    'star': Icons.star_rounded,
    'tip': Icons.lightbulb_outline_rounded,
    'warning': Icons.warning_amber_rounded,
    'check': Icons.check_circle_outline_rounded,
    'link': Icons.link_rounded,
    'code': Icons.code_rounded,
    'music': Icons.music_note_rounded,
    'chart': Icons.bar_chart_rounded,
    'lock': Icons.lock_outline_rounded,
    'person': Icons.person_outline_rounded,
    'settings': Icons.settings_outlined,
    'search': Icons.search_rounded,
  };

  IconData _resolveIcon() {
    final iconName = component.data['icon']?.toString().toLowerCase() ?? '';
    if (_iconMap.containsKey(iconName)) return _iconMap[iconName]!;
    switch (component.type) {
      case 'service_card':
        return Icons.miscellaneous_services_rounded;
      case 'recommendation_card':
        return Icons.recommend_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  Color _resolveColor() {
    final colorStr = component.data['color']?.toString() ?? '';
    switch (colorStr) {
      case 'green':
        return const Color(0xFF34A853);
      case 'red':
        return const Color(0xFFEA4335);
      case 'yellow':
        return const Color(0xFFFBBC04);
      case 'purple':
        return const Color(0xFF9C27B0);
      case 'cyan':
        return const Color(0xFF00BCD4);
      default:
        return const Color(0xFF8AB4F8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = component.title ?? component.data['title']?.toString() ?? '';
    final description =
        component.description ?? component.data['body']?.toString() ?? '';
    final linkLabel = component.data['link_label']?.toString();
    final linkUrl = component.data['link_url']?.toString();
    final promptText = component.data['prompt']?.toString();
    final accentColor = _resolveColor();
    final icon = _resolveIcon();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3C3F41)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // İkon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 14),
          // İçerik
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFF9AA0A6),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
                if ((linkLabel != null && linkLabel.isNotEmpty) ||
                    (promptText != null && promptText.isNotEmpty)) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      if (promptText != null && promptText.isNotEmpty) {
                        onAction?.call(UiAction(
                          type: 'prompt',
                          label: linkLabel ?? 'Devam et',
                          value: promptText,
                        ));
                      } else if (linkUrl != null && linkUrl.isNotEmpty) {
                        onAction?.call(UiAction(
                          type: 'url',
                          label: linkLabel ?? 'Aç',
                          value: linkUrl,
                        ));
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          linkLabel ?? 'Devam et',
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: accentColor,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
