import 'package:flutter/material.dart';
import '../../../models/generative_ui/ui_action_model.dart';
import '../../../models/generative_ui/ui_component_model.dart';

/// Radio (tek seçim) grubu bileşeni.
/// AI çıktısındaki "radio_group" tipine karşılık gelir.
class UiRadioGroupWidget extends StatefulWidget {
  final UiComponent component;
  final void Function(UiAction action)? onAction;

  const UiRadioGroupWidget({
    super.key,
    required this.component,
    this.onAction,
  });

  @override
  State<UiRadioGroupWidget> createState() => _UiRadioGroupWidgetState();
}

class _UiRadioGroupWidgetState extends State<UiRadioGroupWidget> {
  String? _selected;

  List<String> get _options {
    final raw = widget.component.data['options'];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return [];
  }

  String get _question =>
      widget.component.data['question']?.toString() ??
      widget.component.title ??
      'Bir seçenek belirleyin';

  String get _submitLabel =>
      widget.component.data['submit_label']?.toString() ?? 'Devam et';

  void _submit() {
    if (_selected == null) return;
    final prompt = '${_question.trimRight()} → $_selected';
    widget.onAction?.call(
      UiAction(type: 'prompt', label: _selected!, value: prompt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;

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
          // Soru başlığı
          Text(
            _question,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          // Seçenekler
          ...options.map((opt) => _RadioOption(
                label: opt,
                selected: _selected == opt,
                onTap: () => setState(() => _selected = opt),
              )),
          const SizedBox(height: 14),
          // Gönder butonu
          SizedBox(
            width: double.infinity,
            child: AnimatedOpacity(
              opacity: _selected != null ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: ElevatedButton(
                onPressed: _selected != null ? _submit : null,
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
      ),
    );
  }
}

class _RadioOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RadioOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1A3A5C) : const Color(0xFF2D2F30),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF8AB4F8) : const Color(0xFF3C3F41),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? const Color(0xFF8AB4F8) : const Color(0xFF5F6368),
                  width: selected ? 5 : 2,
                ),
                color: selected ? const Color(0xFF8AB4F8) : Colors.transparent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFFBDC1C6),
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
