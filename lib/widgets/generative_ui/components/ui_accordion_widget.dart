import 'package:flutter/material.dart';
import '../../../models/generative_ui/ui_component_model.dart';
import '../../../theme/gemini_colors.dart';

class UiAccordionWidget extends StatefulWidget {
  final UiComponent component;

  const UiAccordionWidget({
    super.key,
    required this.component,
  });

  @override
  State<UiAccordionWidget> createState() => _UiAccordionWidgetState();
}

class _UiAccordionWidgetState extends State<UiAccordionWidget> {
  final Set<int> _expandedIndices = {};

  @override
  Widget build(BuildContext context) {
    final data = widget.component.data;
    final items = (data['items'] is List)
        ? (data['items'] as List).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

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
          if (widget.component.title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.list_alt_rounded, size: 18, color: GeminiColors.geminiCyan),
                  const SizedBox(width: 8),
                  Text(
                    widget.component.title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
          ...List.generate(items.length, (idx) {
            final item = items[idx];
            final title = (item['title'] ?? item['header'] ?? item['question'] ?? 'Detay ${idx + 1}').toString();
            final content = (item['content'] ?? item['body'] ?? item['answer'] ?? item['description'] ?? '').toString();
            final isExpanded = _expandedIndices.contains(idx);

            return Column(
              children: [
                if (idx > 0)
                  Divider(
                    color: Colors.white.withValues(alpha: 0.06),
                    height: 1,
                  ),
                InkWell(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedIndices.remove(idx);
                      } else {
                        _expandedIndices.add(idx);
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: isExpanded ? GeminiColors.geminiCyan : Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Text(
                      content,
                      style: const TextStyle(
                        color: Color(0xFFCCCCCC),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                  crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
