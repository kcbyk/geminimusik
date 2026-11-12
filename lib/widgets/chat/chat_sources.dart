import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/chat_ui.dart';

/// Yanıtın altında görünen kaynak şeridi.
///
/// ChatGPT'nin kaynak davranışı: yanıt biter, hemen altında küçük favicon'lu
/// çipler gelir; dokununca bağlantı açılır. Burada ayrıca "Tümünü gör" ile
/// tam liste açılır.
class ChatSourcesStrip extends StatefulWidget {
  /// [{'title': '...', 'url': '...'}]
  final List<Map<String, String>> sources;
  final bool initiallyExpanded;

  const ChatSourcesStrip({
    super.key,
    required this.sources,
    this.initiallyExpanded = false,
  });

  @override
  State<ChatSourcesStrip> createState() => _ChatSourcesStripState();
}

class _ChatSourcesStripState extends State<ChatSourcesStrip> {
  late bool _expanded = widget.initiallyExpanded;

  static String domainOf(String url) {
    try {
      final uri = Uri.parse(url);
      var host = uri.host;
      if (host.startsWith('www.')) host = host.substring(4);
      return host.isEmpty ? 'web' : host;
    } catch (_) {
      return 'web';
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sources.isEmpty) return const SizedBox.shrink();

    final visible = _expanded ? widget.sources : widget.sources.take(4).toList();
    final hasMore = widget.sources.length > 3 || _expanded;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link_rounded, size: 13, color: ChatUi.textMuted),
              const SizedBox(width: 6),
              Text(
                widget.sources.length == 1
                    ? 'Kaynak'
                    : '${widget.sources.length} kaynak',
                style: const TextStyle(
                  fontSize: 12,
                  color: ChatUi.textMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
              if (widget.sources.length > 3)
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      _expanded ? 'Daralt' : 'Tümü',
                      style: const TextStyle(
                        fontSize: 12,
                        color: ChatUi.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final src in visible)
                _SourceChip(
                  title: (src['title'] ?? '').trim(),
                  domain: domainOf(src['url'] ?? ''),
                  onTap: () => _open(src['url'] ?? ''),
                ),
              if (!_expanded && hasMore && widget.sources.length > 4)
                _SourceChip(
                  title: '+${widget.sources.length - 4}',
                  domain: '',
                  onTap: () => setState(() => _expanded = true),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  final String title;
  final String domain;
  final VoidCallback onTap;

  const _SourceChip({
    required this.title,
    required this.domain,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = title.isNotEmpty ? title : domain;
    return Material(
      color: ChatUi.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ChatUi.borderSoft, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (domain.isNotEmpty) ...[
                _Favicon(domain: domain),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: ChatUi.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (domain.isNotEmpty && title.isNotEmpty)
                      Text(
                        domain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: ChatUi.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Favicon extends StatelessWidget {
  final String domain;

  const _Favicon({required this.domain});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        'https://www.google.com/s2/favicons?domain=$domain&sz=64',
        width: 16,
        height: 16,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.public_rounded,
          size: 15,
          color: ChatUi.textMuted,
        ),
      ),
    );
  }
}
