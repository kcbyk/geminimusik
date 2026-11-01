import 'package:flutter/material.dart';
import '../../../models/generative_ui/ui_component_model.dart';
import '../../../theme/gemini_colors.dart';

class UiFormWidget extends StatefulWidget {
  final UiComponent component;
  final void Function(Map<String, dynamic> formData, String promptText)? onSubmit;

  const UiFormWidget({
    super.key,
    required this.component,
    this.onSubmit,
  });

  @override
  State<UiFormWidget> createState() => _UiFormWidgetState();
}

class _UiFormWidgetState extends State<UiFormWidget> {
  final Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _initFields();
  }

  void _initFields() {
    final fields = _getFields();
    for (final f in fields) {
      final key = f['name']?.toString() ?? f['id']?.toString() ?? f['label']?.toString() ?? 'field';
      final initialVal = f['initialValue'] ?? f['default'];
      final type = (f['type'] ?? 'text').toString().toLowerCase();

      if (type == 'text' || type == 'textarea' || type == 'email' || type == 'number') {
        _controllers[key] = TextEditingController(text: initialVal?.toString() ?? '');
      } else if (type == 'checkbox') {
        _values[key] = initialVal == true;
      } else if (type == 'select' || type == 'radio') {
        final options = (f['options'] is List) ? (f['options'] as List) : [];
        if (options.isNotEmpty) {
          _values[key] = initialVal?.toString() ?? options.first.toString();
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> _getFields() {
    final data = widget.component.data;
    if (data['fields'] is List) {
      return (data['fields'] as List).whereType<Map<String, dynamic>>().toList();
    } else if (data['inputs'] is List) {
      return (data['inputs'] as List).whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  void _submit() {
    final collected = Map<String, dynamic>.from(_values);
    for (final entry in _controllers.entries) {
      collected[entry.key] = entry.value.text.trim();
    }

    final submitPrompt = StringBuffer();
    submitPrompt.writeln('Form Yanıtları (${widget.component.title ?? 'Form'}):');
    for (final entry in collected.entries) {
      submitPrompt.writeln('- ${entry.key}: ${entry.value}');
    }

    widget.onSubmit?.call(collected, submitPrompt.toString().trim());
  }

  @override
  Widget build(BuildContext context) {
    final fields = _getFields();
    final submitButtonText = widget.component.data['submitText']?.toString() ?? 'Gönder';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.component.title != null) ...[
            Row(
              children: [
                const Icon(Icons.dynamic_form_outlined, size: 18, color: GeminiColors.geminiCyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.component.title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (widget.component.description != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.component.description!,
                style: const TextStyle(color: GeminiColors.textMuted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
          ],
          ...fields.map((f) => _buildField(f)),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: GeminiColors.geminiBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _submit,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.send_rounded, size: 16),
                const SizedBox(width: 8),
                Text(
                  submitButtonText,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(Map<String, dynamic> f) {
    final key = f['name']?.toString() ?? f['id']?.toString() ?? f['label']?.toString() ?? 'field';
    final label = (f['label'] ?? f['title'] ?? key).toString();
    final type = (f['type'] ?? 'text').toString().toLowerCase();
    final hint = f['placeholder']?.toString() ?? '';

    if (type == 'checkbox') {
      final isChecked = _values[key] == true;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
          value: isChecked,
          activeColor: GeminiColors.geminiBlue,
          onChanged: (val) {
            setState(() => _values[key] = val == true);
          },
        ),
      );
    }

    if (type == 'select') {
      final options = (f['options'] is List)
          ? (f['options'] as List).map((e) => e.toString()).toList()
          : <String>[];
      final current = _values[key]?.toString() ?? (options.isNotEmpty ? options.first : '');

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: options.contains(current) ? current : null,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E1F20),
                  items: options.map((opt) {
                    return DropdownMenuItem<String>(
                      value: opt,
                      child: Text(opt, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _values[key] = val);
                  },
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (type == 'radio') {
      final options = (f['options'] is List)
          ? (f['options'] as List).map((e) => e.toString()).toList()
          : <String>[];
      final current = _values[key]?.toString() ?? '';

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((opt) {
                final isSelected = opt == current;
                return ChoiceChip(
                  label: Text(opt),
                  selected: isSelected,
                  selectedColor: GeminiColors.geminiBlue,
                  backgroundColor: const Color(0xFF141414),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 12,
                  ),
                  onSelected: (selected) {
                    if (selected) setState(() => _values[key] = opt);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      );
    }

    // Default: text, textarea, email, number
    final isMultiline = type == 'textarea';
    final controller = _controllers[key] ?? TextEditingController();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: isMultiline ? 3 : 1,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF141414),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: GeminiColors.geminiBlue),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
