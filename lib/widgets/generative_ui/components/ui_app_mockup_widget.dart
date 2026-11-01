import 'package:flutter/material.dart';

import '../../../models/generative_ui/ui_action_model.dart';
import '../../../models/generative_ui/ui_component_model.dart';
import 'ui_buttons_widget.dart';

/// Konuya göre içerik alan, sabit sektör veya sahte veri taşımayan uygulama önizlemesi.
class UiAppMockupWidget extends StatelessWidget {
  final UiComponent component;
  final void Function(UiAction action)? onAction;

  const UiAppMockupWidget({
    super.key,
    required this.component,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final data = component.data;
    final name =
        (data['app_name'] ?? data['appName'] ?? component.title ?? 'Uygulama')
            .toString();
    final category = (data['category'] ??
            data['app_type'] ??
            data['appType'] ??
            'Arayüz önizlemesi')
        .toString();
    final greeting =
        (data['greeting'] ?? 'Bugün ne yapmak istersin?').toString();
    final headline = (data['headline'] ??
            data['primary_value'] ??
            data['primaryValue'] ??
            '')
        .toString();
    final headlineLabel = (data['headline_label'] ??
            data['primary_label'] ??
            data['primaryLabel'] ??
            '')
        .toString();
    final accent = _color(data['accent_color'] ?? data['accentColor']) ??
        const Color(0xFF9AA7FF);
    final surface = _color(data['surface_color'] ?? data['surfaceColor']) ??
        const Color(0xFF151515);
    final sections = _items(data['sections'] ?? data['items']);
    final actions = _items(data['quick_actions'] ?? data['quickActions']);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x55000000), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Icon(Icons.auto_awesome_rounded, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: Color(0xFFF5F5F5),
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(category,
                        style: const TextStyle(
                            color: Color(0xFFABABAB), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.menu_rounded,
                        size: 18, color: Color(0xFFD9D9D9)),
                    const Spacer(),
                    Icon(Icons.notifications_none_rounded,
                        size: 18, color: Colors.white.withValues(alpha: 0.72)),
                  ],
                ),
                const SizedBox(height: 24),
                Text(greeting,
                    style: const TextStyle(
                        color: Color(0xFFC8C8C8), fontSize: 13)),
                if (headline.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(headline,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          height: 1.08,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4)),
                ],
                if (headlineLabel.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(headlineLabel,
                      style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: actions
                        .take(4)
                        .map((item) => _ActionChip(
                            label: item['label'] ?? item['title'] ?? '',
                            accent: accent))
                        .toList(),
                  ),
                ],
                if (sections.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  ...sections.take(3).map((item) => _PreviewRow(
                        title: (item['title'] ?? '').toString(),
                        subtitle:
                            (item['subtitle'] ?? item['description'] ?? '')
                                .toString(),
                        accent: accent,
                      )),
                ],
              ],
            ),
          ),
          if (component.actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            UiButtonsWidget(actions: component.actions, onAction: onAction),
          ],
        ],
      ),
    );
  }

  static List<Map<String, dynamic>> _items(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : const [];

  static Color? _color(dynamic value) {
    final hex = value?.toString().replaceFirst('#', '') ?? '';
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
    return Color(int.parse('FF$hex', radix: 16));
  }
}

class _ActionChip extends StatelessWidget {
  final dynamic label;
  final Color accent;
  const _ActionChip({required this.label, required this.accent});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8)),
        child: Text(label.toString(),
            style: TextStyle(
                color: accent, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

class _PreviewRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;
  const _PreviewRow(
      {required this.title, required this.subtitle, required this.accent});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(
              width: 6,
              height: 32,
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFFEAEAEA),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFF9C9C9C), fontSize: 11)),
              ])),
          Icon(Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.45), size: 18),
        ]),
      );
}
