import 'package:flutter/material.dart';

import '../../../models/generative_ui/ui_component_model.dart';
import '../../../theme/chat_ui.dart';
import '../../chat/chat_image.dart';

/// Generative UI `gallery` bileşeni.
///
/// ChatGPT'nin görsel davranışını izler: görseller karusel yerine tek bir
/// kolaj hâlinde gösterilir (1 büyük, 2 yan yana, 3 büyük + iki küçük, 4+ ızgara).
/// Herhangi bir kareye dokunmak tam ekran, kaydırılabilir ve yakınlaştırılabilir
/// görüntüleyiciyi açar. Görsel sayısı 5'i aşarsa son karede "+N" sayacı görünür.
class UiGalleryWidget extends StatelessWidget {
  final UiComponent component;

  const UiGalleryWidget({super.key, required this.component});

  List<ChatImageRef> _images() {
    final data = component.data;
    final refs = <ChatImageRef>[];

    void addItem(dynamic item) {
      if (item is String) {
        if (item.trim().isEmpty) return;
        refs.add(ChatImageRef(url: item.trim()));
        return;
      }
      if (item is Map) {
        final url = (item['image_url'] ??
                item['url'] ??
                item['thumbnail_url'] ??
                item['image'] ??
                '')
            .toString()
            .trim();
        if (url.isEmpty) return;
        refs.add(
          ChatImageRef(
            url: url,
            alt: (item['title'] ?? '').toString(),
            caption: (item['caption'] ?? item['source_name'] ?? '').toString(),
          ),
        );
      }
    }

    final raw = data['images'] ?? data['items'];
    if (raw is List) {
      for (final item in raw) {
        addItem(item);
      }
    }
    if (refs.isEmpty && data['image'] != null) {
      addItem(data['image']);
    }
    return refs;
  }

  @override
  Widget build(BuildContext context) {
    final images = _images();
    if (images.isEmpty) return const SizedBox.shrink();

    final title = component.title?.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null && title.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.photo_library_outlined,
                    size: 15, color: ChatUi.textMuted),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ChatUi.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (images.length > 1)
                  Text(
                    '${images.length} görsel',
                    style: ChatUi.caption,
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          ChatImageCollage(images: images),
          if (images.length > 1) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => ChatImageViewer.show(
                  context,
                  images: images,
                  initialIndex: 0,
                ),
                icon: const Icon(Icons.fullscreen_rounded,
                    size: 16, color: ChatUi.textMuted),
                label: Text(
                  'Tümünü gör (${images.length})',
                  style: const TextStyle(fontSize: 12.5, color: ChatUi.textMuted),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
