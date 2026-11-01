import 'package:flutter/material.dart';
import '../../../models/generative_ui/ui_action_model.dart';
import '../../../models/generative_ui/ui_component_model.dart';
import '../../../theme/gemini_colors.dart';
import 'ui_buttons_widget.dart';

class UiProductCardWidget extends StatelessWidget {
  final UiComponent component;
  final void Function(UiAction action)? onAction;

  const UiProductCardWidget({
    super.key,
    required this.component,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final data = component.data;
    // Check if component represents multiple products
    if (data['products'] is List) {
      final list = (data['products'] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      return _buildProductList(context, list);
    }

    return _buildSingleCard(context, data, component.title, component.description, component.actions);
  }

  Widget _buildProductList(BuildContext context, List<Map<String, dynamic>> products) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (component.title != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Row(
              children: [
                const Icon(Icons.shopping_bag_outlined, size: 18, color: GeminiColors.geminiCyan),
                const SizedBox(width: 8),
                Text(
                  component.title!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: products.map((p) {
              final actions = <UiAction>[];
              if (p['actions'] is List) {
                for (final a in p['actions']) {
                  if (a is Map<String, dynamic>) actions.add(UiAction.fromJson(a));
                }
              } else if (p['action'] is Map<String, dynamic>) {
                actions.add(UiAction.fromJson(p['action']));
              } else {
                actions.add(UiAction(
                  type: 'prompt',
                  label: 'İncele',
                  value: '${p['title'] ?? 'Ürün'} hakkında detaylı bilgi ver',
                ));
              }

              return Container(
                width: 250,
                margin: const EdgeInsets.only(right: 12, bottom: 8),
                child: _buildSingleCard(
                  context,
                  p,
                  p['title']?.toString(),
                  p['description']?.toString(),
                  actions,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSingleCard(
    BuildContext context,
    Map<String, dynamic> data,
    String? title,
    String? description,
    List<UiAction> actions,
  ) {
    final image = (data['image'] ?? data['imageUrl'])?.toString();
    final price = (data['price'] ?? data['currentPrice'])?.toString();
    final oldPrice = (data['oldPrice'] ?? data['originalPrice'])?.toString();
    final currency = (data['currency'] ?? '₺').toString();
    final rating = (data['rating'] is num) ? (data['rating'] as num).toDouble() : null;
    final reviews = data['reviews']?.toString();
    final badge = (data['badge'] ?? data['tag'])?.toString();
    final features = (data['features'] is List)
        ? (data['features'] as List).map((e) => e.toString()).toList()
        : <String>[];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ürün Görseli & İndirim Rozeti
          Stack(
            children: [
              SizedBox(
                height: 140,
                width: double.infinity,
                child: _buildProductImage(image),
              ),
              if (badge != null && badge.isNotEmpty)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null && title.isNotEmpty)
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const SizedBox(height: 4),
                if (rating != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                      const SizedBox(width: 3),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (reviews != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          '($reviews)',
                          style: const TextStyle(
                            color: GeminiColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                if (description != null && description.isNotEmpty)
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: GeminiColors.textSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                if (features.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...features.take(3).map((f) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Row(
                          children: [
                            const Icon(Icons.check, size: 12, color: GeminiColors.geminiCyan),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                f,
                                style: const TextStyle(
                                  color: Color(0xFFCCCCCC),
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
                const SizedBox(height: 8),
                if (price != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$price $currency',
                        style: const TextStyle(
                          color: GeminiColors.geminiCyan,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (oldPrice != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '$oldPrice $currency',
                          style: const TextStyle(
                            color: GeminiColors.textMuted,
                            fontSize: 11,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (actions.isNotEmpty)
                  UiButtonsWidget(actions: actions, onAction: onAction),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductImage(String? url) {
    if (url != null && (url.startsWith('http://') || url.startsWith('https://'))) {
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
      color: const Color(0xFF141414),
      child: Center(
        child: Icon(
          Icons.shopping_bag_outlined,
          size: 38,
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
