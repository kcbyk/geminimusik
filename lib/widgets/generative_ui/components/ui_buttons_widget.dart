import 'package:flutter/material.dart';
import '../../../models/generative_ui/ui_action_model.dart';
import '../../../theme/gemini_colors.dart';

class UiButtonsWidget extends StatelessWidget {
  final List<UiAction> actions;
  final void Function(UiAction action)? onAction;

  const UiButtonsWidget({
    super.key,
    required this.actions,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: actions.map((act) => _buildButton(context, act)).toList(),
    );
  }

  Widget _buildButton(BuildContext context, UiAction action) {
    final style = action.style ?? 'primary';
    final isDestructive = style == 'destructive';
    final isOutline = style == 'outline';
    final isSecondary = style == 'secondary';

    Color bgColor;
    Color fgColor;
    BorderSide border;

    if (isDestructive) {
      bgColor = Colors.redAccent.withValues(alpha: 0.15);
      fgColor = Colors.redAccent;
      border = const BorderSide(color: Colors.redAccent, width: 1);
    } else if (isOutline) {
      bgColor = Colors.transparent;
      fgColor = GeminiColors.geminiCyan;
      border = BorderSide(color: GeminiColors.geminiCyan.withValues(alpha: 0.6), width: 1);
    } else if (isSecondary) {
      bgColor = const Color(0xFF282A2C);
      fgColor = Colors.white;
      border = BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1);
    } else {
      // primary
      bgColor = GeminiColors.geminiBlue;
      fgColor = Colors.white;
      border = BorderSide.none;
    }

    IconData? iconData;
    if (action.icon != null) {
      iconData = _parseIcon(action.icon!);
    } else if (action.type == 'url') {
      iconData = Icons.open_in_new_rounded;
    } else if (action.type == 'copy') {
      iconData = Icons.copy_rounded;
    } else if (action.type == 'prompt') {
      iconData = Icons.chat_bubble_outline_rounded;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onAction?.call(action),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            border: border != BorderSide.none ? Border.fromBorderSide(border) : null,
            boxShadow: style == 'primary'
                ? [
                    BoxShadow(
                      color: GeminiColors.geminiBlue.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (iconData != null) ...[
                Icon(iconData, size: 15, color: fgColor),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fgColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData? _parseIcon(String name) {
    switch (name.toLowerCase()) {
      case 'arrow_forward':
      case 'next':
        return Icons.arrow_forward_rounded;
      case 'check':
      case 'done':
        return Icons.check_circle_outline_rounded;
      case 'refresh':
        return Icons.refresh_rounded;
      case 'star':
        return Icons.star_rounded;
      case 'add':
        return Icons.add_rounded;
      case 'share':
        return Icons.share_rounded;
      case 'download':
        return Icons.download_rounded;
      case 'play':
        return Icons.play_arrow_rounded;
      case 'launch':
      case 'link':
        return Icons.launch_rounded;
      case 'color_lens':
      case 'palette':
        return Icons.color_lens_outlined;
      case 'tune':
      case 'filter':
        return Icons.tune_rounded;
      default:
        return null;
    }
  }
}
