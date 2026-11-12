import 'dart:convert';

import 'package:flutter/material.dart';
import '../../theme/chat_ui.dart';

/// Markdown içinden veya Generative UI'dan gelen bir görsel referansı.
class ChatImageRef {
  final String url;
  final String? alt;
  final String? caption;

  const ChatImageRef({required this.url, this.alt, this.caption});

  /// `![alt](url "başlık")` satırını çözer. Görsel değilse null döner.
  static ChatImageRef? tryParseMarkdown(String line) {
    final match = RegExp(
      r'^!\[([^\]]*)\]\(\s*([^)\s]+)(?:\s+"([^"]*)")?\s*\)$',
    ).firstMatch(line.trim());
    if (match == null) return null;
    final url = (match.group(2) ?? '').trim();
    if (!_looksLikeUri(url)) return null;
    return ChatImageRef(url: url, alt: match.group(1), caption: match.group(3));
  }

  /// `<img src="...">` satırını çözer.
  static ChatImageRef? tryParseHtml(String line) {
    final match = RegExp(
      r'''<img[^>]*src=["']([^"']+)["'][^>]*>''',
      caseSensitive: false,
    ).firstMatch(line);
    if (match == null) return null;
    final url = match.group(1)!.trim();
    if (!_looksLikeUri(url)) return null;
    final alt = RegExp(r'''alt=["']([^"']*)["']''').firstMatch(line)?.group(1);
    return ChatImageRef(url: url, alt: alt);
  }

  static bool _looksLikeUri(String url) {
    final lower = url.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return true;
    if (lower.startsWith('data:image/')) return true;
    if (lower.startsWith('file://')) return true;
    return false;
  }
}

/// Görselleri ChatGPT'deki gibi tek bir kompozisyonda gösteren kolaj.
///
/// - 1 görsel  → tam genişlik, yuvarlatılmış tek kare
/// - 2 görsel  → yan yana iki eşit kare
/// - 3 görsel  → solda büyük kare + sağda üst üste iki kare (klasik ChatGPT kolajı)
/// - 4 görsel  → 2x2 ızgara
/// - 5+ görsel → 2x2 ızgara, son karede "+N" sayacı
class ChatImageCollage extends StatelessWidget {
  final List<ChatImageRef> images;
  final void Function(int index)? onImageTap;

  const ChatImageCollage({super.key, required this.images, this.onImageTap});

  @override
  Widget build(BuildContext context) {
    final items = images
        .where((e) => e.url.trim().isNotEmpty)
        .take(5)
        .toList(growable: false);
    if (items.isEmpty) return const SizedBox.shrink();

    final count = images.length;

    void open(int index) {
      if (onImageTap != null) {
        onImageTap!(index);
      } else {
        ChatImageViewer.show(context, images: images, initialIndex: index);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final baseHeight = count == 1
            ? (width * 0.72).clamp(160.0, 420.0)
            : (width * 0.62).clamp(180.0, 380.0);

        if (count == 1) {
          return _clip(
            ChatImageTile(
              image: items.first,
              borderRadius: 0,
              aspectRatio: null,
              onTap: () => open(0),
            ),
          );
        }

        if (count == 2) {
          return _clip(
            SizedBox(
              height: baseHeight,
              child: Row(
                children: [
                  Expanded(
                    child: ChatImageTile(
                      image: items[0],
                      borderRadius: 0,
                      onTap: () => open(0),
                    ),
                  ),
                  const SizedBox(width: ChatUi.collageGap),
                  Expanded(
                    child: ChatImageTile(
                      image: items[1],
                      borderRadius: 0,
                      onTap: () => open(1),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (count == 3) {
          final sideHeight = (baseHeight - ChatUi.collageGap) / 2;
          return _clip(
            SizedBox(
              height: baseHeight,
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: ChatImageTile(
                      image: items[0],
                      borderRadius: 0,
                      onTap: () => open(0),
                    ),
                  ),
                  const SizedBox(width: ChatUi.collageGap),
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        SizedBox(
                          height: sideHeight,
                          child: ChatImageTile(
                            image: items[1],
                            borderRadius: 0,
                            onTap: () => open(1),
                          ),
                        ),
                        const SizedBox(height: ChatUi.collageGap),
                        SizedBox(
                          height: sideHeight,
                          child: ChatImageTile(
                            image: items[2],
                            borderRadius: 0,
                            onTap: () => open(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // 4 ve üzeri: 2x2 ızgara
        final cellHeight = (baseHeight - ChatUi.collageGap) / 2;
        return _clip(
          SizedBox(
            height: baseHeight,
            child: Column(
              children: [
                SizedBox(
                  height: cellHeight,
                  child: Row(
                    children: [
                      Expanded(
                        child: ChatImageTile(
                          image: items[0],
                          borderRadius: 0,
                          onTap: () => open(0),
                        ),
                      ),
                      const SizedBox(width: ChatUi.collageGap),
                      Expanded(
                        child: ChatImageTile(
                          image: items[1],
                          borderRadius: 0,
                          onTap: () => open(1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ChatUi.collageGap),
                SizedBox(
                  height: cellHeight,
                  child: Row(
                    children: [
                      Expanded(
                        child: ChatImageTile(
                          image: items[2],
                          borderRadius: 0,
                          onTap: () => open(2),
                        ),
                      ),
                      const SizedBox(width: ChatUi.collageGap),
                      Expanded(
                        child: ChatImageTile(
                          image: items[3],
                          borderRadius: 0,
                          onTap: () => open(3),
                          extraCount: count > 4 ? count - 4 : 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _clip(Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(ChatUi.imageRadius),
      child: child,
    );
  }
}

/// Tek bir görsel karesi: yükleme iskeleti, hata durumu ve dokunma geri bildirimi.
class ChatImageTile extends StatelessWidget {
  final ChatImageRef image;
  final double borderRadius;
  final double? aspectRatio;
  final VoidCallback? onTap;
  final int extraCount;

  const ChatImageTile({
    super.key,
    required this.image,
    this.borderRadius = ChatUi.imageRadius,
    this.aspectRatio,
    this.onTap,
    this.extraCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = _buildImage(context);

    if (extraCount > 0) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          content,
          Container(
            color: Colors.black.withValues(alpha: 0.55),
            alignment: Alignment.center,
            child: Text(
              '+$extraCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Material(
        color: ChatUi.surfaceRaised,
        child: InkWell(
          onTap: onTap,
          child: aspectRatio != null
              ? AspectRatio(aspectRatio: aspectRatio!, child: content)
              : content,
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    final url = image.url;
    if (url.toLowerCase().startsWith('data:image/')) {
      return _dataImage(url);
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        final expected = progress.expectedTotalBytes;
        final value = expected != null && expected > 0
            ? progress.cumulativeBytesLoaded / expected
            : null;
        return _Placeholder(progress: value);
      },
      errorBuilder: (context, error, stack) => _BrokenImage(alt: image.alt),
    );
  }

  Widget _dataImage(String url) {
    try {
      final payload = url.substring(url.indexOf(',') + 1);
      final bytes = base64Decode(Uri.decodeComponent(payload));
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stack) => _BrokenImage(alt: image.alt),
      );
    } catch (_) {
      return _BrokenImage(alt: image.alt);
    }
  }
}

class _Placeholder extends StatelessWidget {
  final double? progress;

  const _Placeholder({this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ChatUi.surfaceRaised,
      alignment: Alignment.center,
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          value: progress,
          color: ChatUi.textMuted,
        ),
      ),
    );
  }
}

class _BrokenImage extends StatelessWidget {
  final String? alt;

  const _BrokenImage({this.alt});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ChatUi.surfaceRaised,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.image_not_supported_outlined,
              color: ChatUi.textMuted, size: 22),
          if (alt != null && alt!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              alt!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: ChatUi.caption,
            ),
          ],
        ],
      ),
    );
  }
}

/// Tam ekran görsel görüntüleyici: kaydırma, pinch-zoom, sayaç ve indirme.
class ChatImageViewer extends StatefulWidget {
  final List<ChatImageRef> images;
  final int initialIndex;

  const ChatImageViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  static Future<void> show(
    BuildContext context, {
    required List<ChatImageRef> images,
    int initialIndex = 0,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) =>
            ChatImageViewer(images: images, initialIndex: initialIndex),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<ChatImageViewer> createState() => _ChatImageViewerState();
}

class _ChatImageViewerState extends State<ChatImageViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.images.length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: total,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final item = widget.images[i];
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(
                      item.url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: ChatUi.textMuted,
                        size: 42,
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              left: 8,
              child: _ViewerButton(
                icon: Icons.close_rounded,
                label: 'Kapat',
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            if (total > 1)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: ChatUi.border),
                    ),
                    child: Text(
                      '${_index + 1} / $total',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.images[_index].caption != null &&
                widget.images[_index].caption!.trim().isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Text(
                  widget.images[_index].caption!,
                  style: const TextStyle(color: ChatUi.textSecondary, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ViewerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ViewerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 22),
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}
