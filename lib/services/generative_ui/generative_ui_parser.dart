import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models/generative_ui/ui_component_model.dart';

abstract class ParsedMessageSegment {
  const ParsedMessageSegment();
}

class TextSegment extends ParsedMessageSegment {
  final String text;
  const TextSegment(this.text);
}

class GenerativeUiSegment extends ParsedMessageSegment {
  final UiComponent component;
  const GenerativeUiSegment(this.component);
}

class GenerativeUiParser {
  /// Desteklenen UI kod bloğu dilleri
  static final RegExp _uiBlockRegex = RegExp(
    r'```(?:ui|generative_ui|json:ui)\s*([\s\S]*?)```',
    caseSensitive: false,
  );

  /// Bir mesaj metnini hem metin parçalarına hem de UI bileşenlerine ayrıştırır.
  static List<ParsedMessageSegment> parse(String content) {
    if (content.trim().isEmpty) {
      return const [];
    }

    final trimmed = content.trim();

    // 1. Durum: Mesajın tamamı saf JSON olarak UI bileşeni ise
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic> && _isPotentialUiJson(decoded)) {
          return [GenerativeUiSegment(UiComponent.fromJson(decoded))];
        } else if (decoded is List) {
          final items = <UiComponent>[];
          for (final item in decoded) {
            if (item is Map<String, dynamic> && _isPotentialUiJson(item)) {
              items.add(UiComponent.fromJson(item));
            }
          }
          if (items.isNotEmpty) {
            return [
              GenerativeUiSegment(UiComponent(
                type: 'column',
                children: items,
              ))
            ];
          }
        }
      } catch (_) {
        // Saf JSON değilse normal parse akışına devam et
      }
    }

    // 2. Durum: ```ui ... ``` veya ```generative_ui ... ``` blokları aranır
    final matches = _uiBlockRegex.allMatches(content).toList();
    if (matches.isEmpty) {
      return [TextSegment(content)];
    }

    final segments = <ParsedMessageSegment>[];
    int lastEnd = 0;

    for (final match in matches) {
      // Bloktan önceki metin
      if (match.start > lastEnd) {
        final textBefore = content.substring(lastEnd, match.start).trim();
        if (textBefore.isNotEmpty) {
          segments.add(TextSegment(textBefore));
        }
      }

      final jsonStr = match.group(1)?.trim() ?? '';
      if (jsonStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(jsonStr);
          if (decoded is Map<String, dynamic>) {
            segments.add(GenerativeUiSegment(UiComponent.fromJson(decoded)));
          } else if (decoded is List) {
            for (final item in decoded) {
              if (item is Map<String, dynamic>) {
                segments.add(GenerativeUiSegment(UiComponent.fromJson(item)));
              }
            }
          }
        } catch (e) {
          debugPrint('Generative UI JSON parse hatası: $e');
          // JSON bozuksa güvenli şekilde kod bloğu metni olarak bırak
          segments.add(TextSegment('```json\n$jsonStr\n```'));
        }
      }

      lastEnd = match.end;
    }

    // Son bloktan sonra kalan metin
    if (lastEnd < content.length) {
      final textAfter = content.substring(lastEnd).trim();
      if (textAfter.isNotEmpty) {
        segments.add(TextSegment(textAfter));
      }
    }

    return segments;
  }

  static bool _isPotentialUiJson(Map<String, dynamic> json) {
    return json.containsKey('type') ||
        json.containsKey('component') ||
        json.containsKey('layout') ||
        json.containsKey('dashboard');
  }

  /// Mesajın Generative UI içerip içermediğini hızlıca kontrol eder
  static bool hasUi(String content) {
    if (_uiBlockRegex.hasMatch(content)) return true;
    final trimmed = content.trim();
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          return _isPotentialUiJson(decoded);
        }
      } catch (_) {}
    }
    return false;
  }
}
