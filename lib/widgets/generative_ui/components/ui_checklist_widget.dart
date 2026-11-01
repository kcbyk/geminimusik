import 'package:flutter/material.dart';
import '../../../models/generative_ui/ui_action_model.dart';
import '../../../models/generative_ui/ui_component_model.dart';

/// İnteraktif checklist bileşeni.
/// AI çıktısındaki "checklist" tipine karşılık gelir.
class UiChecklistWidget extends StatefulWidget {
  final UiComponent component;
  final void Function(UiAction action)? onAction;

  const UiChecklistWidget({
    super.key,
    required this.component,
    this.onAction,
  });

  @override
  State<UiChecklistWidget> createState() => _UiChecklistWidgetState();
}

class _UiChecklistWidgetState extends State<UiChecklistWidget> {
  late List<_CheckItem> _items;

  @override
  void initState() {
    super.initState();
    _items = _parseItems();
  }

  List<_CheckItem> _parseItems() {
    final raw = widget.component.data['items'];
    if (raw is List) {
      return raw.map((e) {
        if (e is Map<String, dynamic>) {
          return _CheckItem(
            label: e['label']?.toString() ?? e['text']?.toString() ?? '',
            checked: e['checked'] == true,
          );
        }
        return _CheckItem(label: e.toString(), checked: false);
      }).toList();
    }

    // Fallback: parse description / options
    final opts = widget.component.data['options'];
    if (opts is List) {
      return opts
          .map((e) => _CheckItem(label: e.toString(), checked: false))
          .toList();
    }
    return [];
  }

  String get _title =>
      widget.component.title ??
      widget.component.data['title']?.toString() ??
      'Kontrol Listesi';

  String get _submitLabel =>
      widget.component.data['submit_label']?.toString() ??
      widget.component.data['button_label']?.toString() ??
      'Gönder';

  void _submit() {
    final checked = _items.where((i) => i.checked).map((i) => i.label).toList();
    if (checked.isEmpty) return;
    final prompt = '${_title.trimRight()}: ${checked.join(', ')}';
    widget.onAction?.call(UiAction(type: 'prompt', label: 'Gönder', value: prompt));
  }

  @override
  Widget build(BuildContext context) {
    final hasChecked = _items.any((i) => i.checked);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3C3F41)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist_rtl_rounded, color: Color(0xFF8AB4F8), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            return _CheckRow(
              item: item,
              onToggle: () => setState(() => _items[i] = item.toggled()),
            );
          }),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: AnimatedOpacity(
                opacity: hasChecked ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 200),
                child: ElevatedButton(
                  onPressed: hasChecked ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8AB4F8),
                    foregroundColor: const Color(0xFF0D0D0D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  child: Text(_submitLabel),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckItem {
  final String label;
  final bool checked;

  const _CheckItem({required this.label, required this.checked});

  _CheckItem toggled() => _CheckItem(label: label, checked: !checked);
}

class _CheckRow extends StatelessWidget {
  final _CheckItem item;
  final VoidCallback onToggle;

  const _CheckRow({required this.item, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: item.checked ? const Color(0xFF1A3A5C) : const Color(0xFF2D2F30),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: item.checked ? const Color(0xFF8AB4F8) : const Color(0xFF3C3F41),
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                color: item.checked ? const Color(0xFF8AB4F8) : Colors.transparent,
                border: Border.all(
                  color: item.checked ? const Color(0xFF8AB4F8) : const Color(0xFF5F6368),
                  width: 1.5,
                ),
              ),
              child: item.checked
                  ? const Icon(Icons.check, size: 14, color: Color(0xFF0D0D0D))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  color: item.checked ? Colors.white : const Color(0xFFBDC1C6),
                  fontSize: 14,
                  decoration: item.checked ? TextDecoration.none : TextDecoration.none,
                  fontWeight: item.checked ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
