import 'package:flutter/material.dart';
import '../../../models/generative_ui/ui_action_model.dart';
import '../../../models/generative_ui/ui_component_model.dart';
import '../../../theme/gemini_colors.dart';
import 'ui_buttons_widget.dart';

class UiCardWidget extends StatelessWidget {
  final UiComponent component;
  final void Function(UiAction action)? onAction;

  const UiCardWidget({
    super.key,
    required this.component,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final data = component.data;
    final imageUrl = (data['image'] ?? data['imageUrl'] ?? data['banner'])?.toString();
    final badge = (data['badge'] ?? data['tag'] ?? data['category'])?.toString();
    final layout = (data['layout'] ?? 'vertical').toString().toLowerCase();
    final tags = (data['tags'] is List)
        ? (data['tags'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final metadata = (data['metadata'] is Map)
        ? (data['metadata'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
        : <String, String>{};

    final isHorizontal = layout == 'horizontal';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty && !isHorizontal)
            _buildImageBanner(imageUrl, badge),
          Padding(
            padding: const EdgeInsets.all(16),
            child: isHorizontal
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (imageUrl != null && imageUrl.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 100,
                            height: 100,
                            child: _buildNetworkOrFallback(imageUrl),
                          ),
                        ),
                        const SizedBox(width: 14),
                      ],
                      Expanded(
                        child: _buildContent(badge, tags, metadata),
                      ),
                    ],
                  )
                : _buildContent(
                    imageUrl == null || imageUrl.isEmpty ? badge : null,
                    tags,
                    metadata,
                  ),
          ),
          if (component.actions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: UiButtonsWidget(
                actions: component.actions,
                onAction: onAction,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent(
    String? badge,
    List<String> tags,
    Map<String, String> metadata,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (badge != null && badge.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: GeminiColors.geminiBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: GeminiColors.geminiBlue.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: GeminiColors.geminiCyan,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (component.title != null && component.title!.isNotEmpty) ...[
          Text(
            component.title!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 4),
        ],
        if (component.subtitle != null && component.subtitle!.isNotEmpty) ...[
          Text(
            component.subtitle!,
            style: const TextStyle(
              color: GeminiColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (component.description != null && component.description!.isNotEmpty) ...[
          Text(
            component.description!,
            style: const TextStyle(
              color: Color(0xFFE3E3E3),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags.map((t) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#$t',
                  style: const TextStyle(
                    color: GeminiColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
        ],
        if (metadata.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: metadata.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        entry.key,
                        style: const TextStyle(
                          color: GeminiColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        entry.value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildImageBanner(String url, String? badge) {
    return Stack(
      children: [
        SizedBox(
          height: 160,
          width: double.infinity,
          child: _buildNetworkOrFallback(url),
        ),
        if (badge != null && badge.isNotEmpty)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 0.8,
                ),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNetworkOrFallback(String url) {
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
          colors: [Color(0xFF1E3A8A), Color(0xFF4C1D95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 40,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
