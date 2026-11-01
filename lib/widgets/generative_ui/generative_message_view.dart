import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../services/generative_ui/generative_ui_parser.dart';
import '../../theme/gemini_colors.dart';
import 'generative_ui_renderer.dart';

class GenerativeMessageView extends StatelessWidget {
  final String content;
  final void Function(String prompt)? onActionPrompt;
  final void Function(String text)? onActionCopy;
  final void Function(String url)? onActionUrl;
  final void Function(Map<String, dynamic> data, String promptText)? onFormSubmit;

  const GenerativeMessageView({
    super.key,
    required this.content,
    this.onActionPrompt,
    this.onActionCopy,
    this.onActionUrl,
    this.onFormSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final segments = GenerativeUiParser.parse(content);
    if (segments.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: segments.map((seg) {
        if (seg is GenerativeUiSegment) {
          return GenerativeUiRenderer(
            component: seg.component,
            onActionPrompt: onActionPrompt,
            onActionCopy: onActionCopy,
            onActionUrl: onActionUrl,
            onFormSubmit: onFormSubmit,
          );
        } else if (seg is TextSegment) {
          if (seg.text.trim().isEmpty) return const SizedBox.shrink();
          final processedMarkdown = _preprocessMarkdown(seg.text);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: MarkdownBody(
              data: processedMarkdown,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  color: Color(0xFFE8EAED),
                  fontSize: 15.5,
                  height: 1.6,
                ),
                h1: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.5,
                ),
                h2: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                ),
                h3: const TextStyle(
                  color: GeminiColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                code: const TextStyle(
                  backgroundColor: Color(0xFF1E1F20),
                  color: GeminiColors.geminiCyan,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
                codeblockDecoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(10),
                ),
                listBullet: const TextStyle(color: GeminiColors.geminiBlue),
                blockquote: const TextStyle(
                  color: Color(0xFFBDC1C6),
                  fontSize: 14.5,
                  fontStyle: FontStyle.italic,
                ),
                blockquoteDecoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: GeminiColors.geminiBlue, width: 3),
                  ),
                ),
                blockquotePadding: const EdgeInsets.only(left: 14, top: 4, bottom: 4),
                tableBorder: TableBorder.all(
                  color: const Color(0xFF3C3F41),
                  width: 1,
                  borderRadius: BorderRadius.circular(8),
                ),
                tableHead: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                tableBody: const TextStyle(
                  color: Color(0xFFE8EAED),
                  fontSize: 13.5,
                ),
                tableCellsPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                horizontalRuleDecoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: const Color(0xFF3C3F41).withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      }).toList(),
    );
  }

  /// Markdown checklist ve biçimlendirme ön işlemcisi
  static String _preprocessMarkdown(String input) {
    var text = input;
    // - [ ] ve - [x] checklist sözdizimini görsel simgelerle zenginleştir
    text = text.replaceAll(RegExp(r'^[ \t]*-[ \t]+\[ \][ \t]+', multiLine: true), '☐ ');
    text = text.replaceAll(RegExp(r'^[ \t]*-[ \t]+\[[xX]\][ \t]+', multiLine: true), '☑ ');
    return text;
  }
}
