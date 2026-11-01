import 'package:flutter/material.dart';
import '../../../models/generative_ui/ui_component_model.dart';
import '../../../theme/gemini_colors.dart';

class UiGalleryWidget extends StatefulWidget {
  final UiComponent component;

  const UiGalleryWidget({
    super.key,
    required this.component,
  });

  @override
  State<UiGalleryWidget> createState() => _UiGalleryWidgetState();
}

class _UiGalleryWidgetState extends State<UiGalleryWidget> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  List<Map<String, String>> _getItems() {
    final data = widget.component.data;
    final items = <Map<String, String>>[];

    if (data['images'] is List) {
      for (final item in data['images'] as List) {
        if (item is Map) {
          items.add({
            'url': (item['thumbnail_url'] ?? item['url'] ?? item['image'] ?? '')
                .toString(),
            'caption': (item['caption'] ?? item['title'] ?? '').toString(),
            'source': (item['source_name'] ?? '').toString(),
            'source_url': (item['source_url'] ?? '').toString(),
          });
        } else if (item is String) {
          items.add({'url': item, 'caption': ''});
        }
      }
    } else if (data['items'] is List) {
      for (final item in data['items'] as List) {
        if (item is Map) {
          items.add({
            'url': (item['thumbnail_url'] ?? item['url'] ?? item['image'] ?? '')
                .toString(),
            'caption': (item['caption'] ?? item['title'] ?? '').toString(),
            'source': (item['source_name'] ?? '').toString(),
            'source_url': (item['source_url'] ?? '').toString(),
          });
        } else if (item is String) {
          items.add({'url': item, 'caption': ''});
        }
      }
    }

    if (items.isEmpty && data['image'] != null) {
      items.add({
        'url': data['image'].toString(),
        'caption': widget.component.title ?? '',
      });
    }

    return items;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _getItems();
    if (items.isEmpty) return const SizedBox.shrink();

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
          if (widget.component.title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.collections_bookmark_outlined,
                      size: 18, color: GeminiColors.geminiCyan),
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
          SizedBox(
            height: 200,
            child: PageView.builder(
              controller: _pageController,
              itemCount: items.length,
              onPageChanged: (idx) => setState(() => _currentIndex = idx),
              itemBuilder: (context, index) {
                final item = items[index];
                return GestureDetector(
                  onTap: () => _openLightbox(context, items, index),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildImage(item['url'] ?? ''),
                      if ((item['caption'] ?? '').isNotEmpty)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.8),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            child: Text(
                              item['caption']!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (items.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(items.length, (idx) {
                  final isActive = idx == _currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isActive ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isActive
                          ? GeminiColors.geminiBlue
                          : Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.photo_size_select_actual_outlined,
          size: 44,
          color: Colors.white.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  void _openLightbox(
      BuildContext context, List<Map<String, String>> items, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) {
          int active = initialIndex;
          return StatefulBuilder(
            builder: (ctx, setLightboxState) {
              return Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(
                  backgroundColor: Colors.black,
                  iconTheme: const IconThemeData(color: Colors.white),
                  title: Text(
                    '${active + 1} / ${items.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                body: PageView.builder(
                  itemCount: items.length,
                  controller: PageController(initialPage: initialIndex),
                  onPageChanged: (i) => setLightboxState(() => active = i),
                  itemBuilder: (ctx, i) {
                    final it = items[i];
                    return Center(
                      child: InteractiveViewer(
                        child: _buildImage(it['url'] ?? ''),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
