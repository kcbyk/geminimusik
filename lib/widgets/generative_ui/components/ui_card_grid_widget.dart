import 'package:flutter/material.dart';
import '../../../models/generative_ui/ui_action_model.dart';
import '../../../models/generative_ui/ui_component_model.dart';

/// Kart Grid bileşeni — 2 sütunlu (mobil) veya 3 sütunlu (tablet/masaüstü) grid.
/// AI çıktısındaki "card_grid" tipine karşılık gelir.
class UiCardGridWidget extends StatelessWidget {
  final UiComponent component;
  final void Function(UiAction action)? onAction;

  const UiCardGridWidget({
    super.key,
    required this.component,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final title = component.title;
    final cards = _parseCards();
    final screenWidth = MediaQuery.of(context).size.width;
    final cols = screenWidth >= 600 ? 3 : 2;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title.isNotEmpty) ...[
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
          ],
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.85,
            ),
            itemCount: cards.length,
            itemBuilder: (ctx, i) => _GridCard(
              card: cards[i],
              onAction: onAction,
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _parseCards() {
    final raw = component.data['cards'];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    // Fallback: children as cards
    return component.children
        .map((c) => c.data)
        .toList();
  }
}

class _GridCard extends StatefulWidget {
  final Map<String, dynamic> card;
  final void Function(UiAction action)? onAction;

  const _GridCard({required this.card, this.onAction});

  @override
  State<_GridCard> createState() => _GridCardState();
}

class _GridCardState extends State<_GridCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.card['title']?.toString() ?? '';
    final description = widget.card['description']?.toString();
    final imageUrl = widget.card['image_url']?.toString();
    final linkUrl = widget.card['link_url']?.toString();
    final category = widget.card['category']?.toString();
    final prompt = widget.card['prompt']?.toString();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          if (prompt != null && prompt.isNotEmpty) {
            widget.onAction?.call(UiAction(type: 'prompt', label: prompt, value: prompt));
          } else if (linkUrl != null && linkUrl.isNotEmpty) {
            widget.onAction?.call(UiAction(type: 'url', label: title, value: linkUrl));
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xFF2D2F30)
                : const Color(0xFF1E1F20),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered
                  ? const Color(0xFF8AB4F8)
                  : const Color(0xFF3C3F41),
              width: _hovered ? 1.5 : 1,
            ),
            boxShadow: _hovered
                ? [
                    const BoxShadow(
                      color: Color(0x448AB4F8),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Görsel veya gradient placeholder
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                child: _CardImage(imageUrl: imageUrl, title: title),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (category != null && category.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A3A5C),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            category,
                            style: const TextStyle(
                              color: Color(0xFF8AB4F8),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: const TextStyle(
                            color: Color(0xFF9AA0A6),
                            fontSize: 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Görsel widget — yükleme sırasında shimmer, hata durumunda gradient placeholder.
class _CardImage extends StatefulWidget {
  final String? imageUrl;
  final String title;

  const _CardImage({required this.imageUrl, required this.title});

  @override
  State<_CardImage> createState() => _CardImageState();
}

class _CardImageState extends State<_CardImage> with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  bool _imageLoaded = false;
  bool _imageError = false;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const imgHeight = 100.0;

    if (widget.imageUrl == null || widget.imageUrl!.isEmpty || _imageError) {
      return _GradientPlaceholder(title: widget.title, height: imgHeight);
    }

    return SizedBox(
      height: imgHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Shimmer arka plan
          if (!_imageLoaded)
            AnimatedBuilder(
              animation: _shimmerController,
              builder: (ctx, _) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF2D2F30),
                      Color.lerp(
                        const Color(0xFF2D2F30),
                        const Color(0xFF3C3F41),
                        _shimmerController.value,
                      )!,
                      const Color(0xFF2D2F30),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
          Image.network(
            widget.imageUrl!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: imgHeight,
            frameBuilder: (ctx, child, frame, _) {
              if (frame != null && !_imageLoaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _imageLoaded = true);
                });
              }
              return AnimatedOpacity(
                opacity: _imageLoaded ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: child,
              );
            },
            errorBuilder: (ctx, _, __) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _imageError = true);
              });
              return _GradientPlaceholder(title: widget.title, height: imgHeight);
            },
          ),
        ],
      ),
    );
  }
}

class _GradientPlaceholder extends StatelessWidget {
  final String title;
  final double height;

  const _GradientPlaceholder({required this.title, required this.height});

  static const List<List<Color>> _gradients = [
    [Color(0xFF1A3A5C), Color(0xFF0D47A1)],
    [Color(0xFF1B5E20), Color(0xFF2E7D32)],
    [Color(0xFF4A148C), Color(0xFF7B1FA2)],
    [Color(0xFF880E4F), Color(0xFFAD1457)],
    [Color(0xFF006064), Color(0xFF00838F)],
    [Color(0xFFBF360C), Color(0xFFE64A19)],
  ];

  @override
  Widget build(BuildContext context) {
    final idx = title.isEmpty ? 0 : title.codeUnitAt(0) % _gradients.length;
    final grad = _gradients[idx];
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: grad,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          title.isNotEmpty ? title[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 36,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
