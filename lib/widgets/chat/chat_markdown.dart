import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/chat_ui.dart';
import 'chat_image.dart';

/// Markdown içeriğini bloklara ayıran yardımcı.
///
/// Neden gerekli: `flutter_markdown` tek bir metin akışı çizer; oysa ChatGPT
/// art arda gelen görselleri tek bir kolaj hâline getiriyor, kod bloklarına
/// başlık + kopyala düğmesi koyuyor. Bu yüzden metni önce bloklara bölüyoruz:
/// düz metin blokları MarkdownBody ile, görsel blokları ChatImageCollage ile
/// çizilir.
enum MdBlockKind { text, images, code }

class MdBlock {
  final MdBlockKind kind;
  final String text;
  final List<ChatImageRef> images;
  final String language;

  const MdBlock._(this.kind, this.text, this.images, this.language);

  const MdBlock.text(String text)
      : this._(MdBlockKind.text, text, const [], '');
  const MdBlock.images(List<ChatImageRef> images)
      : this._(MdBlockKind.images, '', images, '');
  const MdBlock.code(String code, String language)
      : this._(MdBlockKind.code, code, const [], language);
}

class MarkdownBlocks {
  const MarkdownBlocks._();

  static List<MdBlock> parse(String source) {
    final result = <MdBlock>[];
    final buffer = StringBuffer();
    final lines = source.split('\n');

    var i = 0;

    void flush() {
      final text = buffer.toString().trim();
      if (text.isNotEmpty) result.add(MdBlock.text(text));
      buffer.clear();
    }

    ChatImageRef? imageAt(String raw) =>
        ChatImageRef.tryParseMarkdown(raw) ?? ChatImageRef.tryParseHtml(raw);

    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      // --- Kod bloğu ---------------------------------------------------------
      final fenceMatch = RegExp(r'^(```+|~~~+)([A-Za-z0-9#+._-]*)').firstMatch(trimmed);
      if (fenceMatch != null) {
        flush();
        final marker = fenceMatch.group(1)!;
        final language = (fenceMatch.group(2) ?? '').trim();
        final code = <String>[];
        i++;
        while (i < lines.length) {
          final current = lines[i];
          if (current.trim().startsWith(marker)) {
            i++;
            break;
          }
          code.add(current);
          i++;
        }
        result.add(MdBlock.code(code.join('\n'), language));
        continue;
      }

      // --- Görsel bloğu ------------------------------------------------------
      final first = imageAt(trimmed);
      if (first != null) {
        flush();
        final group = <ChatImageRef>[first];
        i++;
        while (i < lines.length) {
          final candidate = lines[i].trim();
          if (candidate.isEmpty) {
            // Araya giren boş satırları atla, ama sadece sonraki satır görsel ise
            var j = i;
            while (j < lines.length && lines[j].trim().isEmpty) {
              j++;
            }
            if (j < lines.length && imageAt(lines[j].trim()) != null) {
              i = j;
              continue;
            }
            break;
          }
          final next = imageAt(candidate);
          if (next == null) break;
          group.add(next);
          i++;
        }
        result.add(MdBlock.images(List.unmodifiable(group)));
        continue;
      }

      buffer.writeln(line);
      i++;
    }

    flush();
    return result;
  }
}

/// ChatGPT kalitesinde markdown görünümü.
///
/// Özellikler:
/// - Art arda gelen görselleri tek kolaj yapar, dokununca tam ekran açar.
/// - Kod bloklarına dil etiketi + kopyala düğmesi ekler.
/// - Tablo, liste, alıntı ve başlıklarda sabit bir görsel ritim uygular.
class ChatMarkdown extends StatelessWidget {
  final String data;
  final void Function(String text)? onTapLink;
  final bool selectable;

  const ChatMarkdown({
    super.key,
    required this.data,
    this.onTapLink,
    this.selectable = true,
  });

  /// Checklist (yapılacaklar) sözdizimini görsel kutuya çevirir.
  static String preprocess(String input) {
    var text = input;
    text = text.replaceAll(
        RegExp(r'^[ \t]*-[ \t]+\[ \][ \t]+', multiLine: true), '☐ ');
    text = text.replaceAll(
        RegExp(r'^[ \t]*-[ \t]+\[[xX]\][ \t]+', multiLine: true), '☑ ');
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final blocks = MarkdownBlocks.parse(preprocess(data));
    if (blocks.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (i > 0) {
        children.add(const SizedBox(height: ChatUi.blockGap));
      }
      switch (block.kind) {
        case MdBlockKind.images:
          children.add(ChatImageCollage(images: block.images));
          break;
        case MdBlockKind.code:
          children.add(
            ChatCodeBlock(
              code: block.text,
              language: block.language.isEmpty ? 'kod' : block.language,
            ),
          );
          break;
        case MdBlockKind.text:
          children.add(
            MarkdownBody(
              data: block.text,
              selectable: selectable,
              listItemCrossAxisAlignment:
                  MarkdownListItemCrossAxisAlignment.start,
              styleSheet: ChatMarkdownStyles.sheet,
              sizedImageBuilder: (config) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ChatImageCollage(
                  images: [
                    ChatImageRef(
                      url: config.uri.toString(),
                      alt: config.alt,
                      caption: config.title,
                    ),
                  ],
                ),
              ),
              onTapLink: (text, href, title) {
                if (href == null) return;
                if (onTapLink != null) {
                  onTapLink!(href);
                  return;
                }
                final uri = Uri.tryParse(href);
                if (uri != null) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          );
          break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

/// Markdown stil sayfası (tek yerden yönetilir).
class ChatMarkdownStyles {
  const ChatMarkdownStyles._();

  static final MarkdownStyleSheet sheet = MarkdownStyleSheet(
    p: ChatUi.body,
    a: ChatUi.link,
    h1: ChatUi.h1,
    h1Padding: EdgeInsets.only(top: 6, bottom: 2),
    h2: ChatUi.h2,
    h2Padding: EdgeInsets.only(top: 6, bottom: 2),
    h3: ChatUi.h3,
    h3Padding: EdgeInsets.only(top: 4, bottom: 2),
    h4: ChatUi.h3,
    h5: ChatUi.h3,
    h6: ChatUi.h3,
    em: TextStyle(fontStyle: FontStyle.italic, color: ChatUi.textPrimary),
    strong: const TextStyle(
      fontWeight: FontWeight.w700,
      color: ChatUi.textPrimary,
    ),
    del: const TextStyle(
      color: ChatUi.textMuted,
      decoration: TextDecoration.lineThrough,
    ),
    blockquote: const TextStyle(
      color: ChatUi.textSecondary,
      fontSize: 15.5,
      height: 1.6,
    ),
    blockquoteDecoration: const BoxDecoration(
      border: Border(left: BorderSide(color: ChatUi.border, width: 3)),
    ),
    blockquotePadding: EdgeInsets.only(left: 14, top: 2, bottom: 2),
    code: const TextStyle(
      backgroundColor: ChatUi.surfaceRaised,
      color: ChatUi.codeText,
      fontSize: 13.5,
      fontFamily: 'monospace',
    ),
    codeblockPadding: EdgeInsets.all(14),
    codeblockDecoration: BoxDecoration(
      color: ChatUi.codeBg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: ChatUi.borderSoft, width: 0.8),
    ),
    listIndent: 22,
    listBullet: ChatUi.listBullet,
    listBulletPadding: const EdgeInsets.only(right: 8),
    tableHead: const TextStyle(
      color: ChatUi.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w700,
    ),
    tableBody: const TextStyle(
      color: ChatUi.textPrimary,
      fontSize: 14,
      height: 1.45,
    ),
    tableBorder: TableBorder.all(color: ChatUi.border, width: 0.8),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    tableColumnWidth: const IntrinsicColumnWidth(),
    tableHeadAlign: TextAlign.left,
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: ChatUi.border, width: 0.8)),
    ),
  );
}

/// Kod bloğu: üstte dil etiketi ve kopyala düğmesi olan kart.
class ChatCodeBlock extends StatefulWidget {
  final String code;
  final String language;

  const ChatCodeBlock({
    super.key,
    required this.code,
    required this.language,
  });

  @override
  State<ChatCodeBlock> createState() => _ChatCodeBlockState();
}

class _ChatCodeBlockState extends State<ChatCodeBlock> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: ChatUi.codeBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ChatUi.borderSoft, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.only(left: 14, right: 6, top: 4, bottom: 4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: ChatUi.borderSoft)),
            ),
            child: Row(
              children: [
                Text(
                  widget.language,
                  style: const TextStyle(
                    color: ChatUi.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _copy,
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 14,
                    color: _copied ? const Color(0xFF6BD69B) : ChatUi.textMuted,
                  ),
                  label: Text(
                    _copied ? 'Kopyalandı' : 'Kopyala',
                    style: TextStyle(
                      fontSize: 11.5,
                      color:
                          _copied ? const Color(0xFF6BD69B) : ChatUi.textMuted,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: SelectableText(
                widget.code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.55,
                  color: ChatUi.codeText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
