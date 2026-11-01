import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/generative_ui/ui_component_model.dart';
import '../../../theme/gemini_colors.dart';

class UiCodeBlockWidget extends StatefulWidget {
  final UiComponent component;

  const UiCodeBlockWidget({
    super.key,
    required this.component,
  });

  @override
  State<UiCodeBlockWidget> createState() => _UiCodeBlockWidgetState();
}

class _UiCodeBlockWidgetState extends State<UiCodeBlockWidget> {
  bool _copied = false;

  void _copyToClipboard(String code) {
    Clipboard.setData(ClipboardData(text: code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.component.data;
    final code = (data['code'] ?? widget.component.description ?? '').toString();
    final language = (data['language'] ?? data['lang'] ?? 'code').toString().toUpperCase();
    final filename = data['filename']?.toString();
    final lines = code.split('\n');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1012),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: const Color(0xFF18191B),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: GeminiColors.geminiBlue.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        language,
                        style: const TextStyle(
                          color: GeminiColors.geminiCyan,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (filename != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        filename,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
                InkWell(
                  onTap: () => _copyToClipboard(code),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          _copied ? Icons.check_rounded : Icons.copy_rounded,
                          size: 14,
                          color: _copied ? Colors.greenAccent : Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? 'Kopyalandı' : 'Kopyala',
                          style: TextStyle(
                            color: _copied ? Colors.greenAccent : Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Code lines
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Line numbers
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(lines.length, (idx) {
                      return Text(
                        '${idx + 1}',
                        style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(width: 14),
                  // Code content
                  SelectableText(
                    code,
                    style: const TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontSize: 12.5,
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
