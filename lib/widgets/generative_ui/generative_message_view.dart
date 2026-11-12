import 'package:flutter/material.dart';

import '../../services/generative_ui/generative_ui_parser.dart';
import '../../theme/chat_ui.dart';
import '../chat/chat_markdown.dart';
import 'generative_ui_renderer.dart';

/// Bir asistan yanıtını iki katmanda çizer:
/// 1. Markdown metni → [ChatMarkdown] (görsel kolajı, kod bloğu başlığı,
///    ChatGPT tipografisi)
/// 2. ```ui``` blokları → Generative UI bileşenleri
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

    final children = <Widget>[];

    for (final seg in segments) {
      if (seg is GenerativeUiSegment) {
        if (children.isNotEmpty) {
          children.add(const SizedBox(height: ChatUi.blockGap));
        }
        children.add(
          GenerativeUiRenderer(
            component: seg.component,
            onActionPrompt: onActionPrompt,
            onActionCopy: onActionCopy,
            onActionUrl: onActionUrl,
            onFormSubmit: onFormSubmit,
          ),
        );
      } else if (seg is TextSegment) {
        final text = seg.text;
        if (text.trim().isEmpty) continue;
        if (children.isNotEmpty) {
          children.add(const SizedBox(height: ChatUi.blockGap));
        }
        children.add(
          ChatMarkdown(
            data: text,
            onTapLink: onActionUrl,
          ),
        );
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  /// Metin içindeki özel işaretleri görsel simgelere çevirir.
  /// (flutter_markdown checklist sözdizimini desteklemediği için)
  static String preprocess(String input) {
    var text = input;
    text = text.replaceAll(
        RegExp(r'^[ \t]*-[ \t]+\[ \][ \t]+', multiLine: true), '☐ ');
    text = text.replaceAll(
        RegExp(r'^[ \t]*-[ \t]+\[[xX]\][ \t]+', multiLine: true), '☑ ');
    return text;
  }
}
