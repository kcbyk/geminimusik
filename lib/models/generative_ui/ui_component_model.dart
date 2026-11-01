import 'ui_action_model.dart';

/// Dinamik Generative UI bileşen modeli.
/// AI modelinden gelen yapılandırılmış JSON verisini doğrular ve tipleştirir.
class UiComponent {
  final String type;
  final String? id;
  final String? title;
  final String? subtitle;
  final String? description;
  final Map<String, dynamic> data;
  final List<UiAction> actions;
  final List<UiComponent> children;

  const UiComponent({
    required this.type,
    this.id,
    this.title,
    this.subtitle,
    this.description,
    this.data = const {},
    this.actions = const [],
    this.children = const [],
  });

  factory UiComponent.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] ?? json['component'] ?? 'card').toString().toLowerCase();

    // normalize type alias
    final type = _normalizeType(rawType);

    final actionsList = <UiAction>[];
    if (json['actions'] is List) {
      for (final a in json['actions'] as List) {
        if (a is Map<String, dynamic>) {
          actionsList.add(UiAction.fromJson(a));
        }
      }
    } else if (json['action'] is Map<String, dynamic>) {
      actionsList.add(UiAction.fromJson(json['action'] as Map<String, dynamic>));
    } else if (json['buttons'] is List) {
      for (final b in json['buttons'] as List) {
        if (b is Map<String, dynamic>) {
          actionsList.add(UiAction.fromJson(b));
        }
      }
    }

    final childrenList = <UiComponent>[];
    if (json['children'] is List) {
      for (final c in json['children'] as List) {
        if (c is Map<String, dynamic>) {
          childrenList.add(UiComponent.fromJson(c));
        }
      }
    } else if (json['items'] is List && (type == 'column' || type == 'row' || type == 'container')) {
      for (final c in json['items'] as List) {
        if (c is Map<String, dynamic>) {
          childrenList.add(UiComponent.fromJson(c));
        }
      }
    }

    return UiComponent(
      type: type,
      id: json['id']?.toString(),
      title: json['title']?.toString(),
      subtitle: json['subtitle']?.toString(),
      description: json['description']?.toString() ?? json['text']?.toString(),
      data: Map<String, dynamic>.from(json),
      actions: actionsList,
      children: childrenList,
    );
  }

  static String _normalizeType(String raw) {
    switch (raw) {
      case 'mediacard':
      case 'media_card':
      case 'rich_card':
        return 'card';
      case 'carousel':
      case 'image_gallery':
      case 'images':
        return 'gallery';
      case 'product':
      case 'product_grid':
      case 'products':
        return 'product_card';
      case 'mockup':
      case 'app_design':
      case 'app_preview':
      case 'mobile_app':
        return 'app_mockup';
      case 'stat':
      case 'stats':
      case 'stat_panel':
      case 'bar_chart':
      case 'metrics':
        return 'chart';
      case 'data_table':
      case 'grid':
        return 'table';
      case 'stepper':
      case 'timeline':
      case 'step_indicator':
        return 'progress';
      case 'button':
      case 'button_group':
      case 'actions':
        return 'buttons';
      case 'expandable':
      case 'collapse':
      case 'faq':
        return 'accordion';
      case 'input':
      case 'inputs':
      case 'form_group':
        return 'form';
      case 'palette':
      case 'colors':
      case 'theme_palette':
        return 'color_palette';
      case 'compare':
      case 'comparison_table':
      case 'versus':
        return 'comparison';
      case 'location':
      case 'map_card':
        return 'map';
      case 'code':
      case 'snippet':
        return 'code_block';
      default:
        return raw;
    }
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (id != null) 'id': id,
        if (title != null) 'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        if (description != null) 'description': description,
        'data': data,
        'actions': actions.map((a) => a.toJson()).toList(),
        'children': children.map((c) => c.toJson()).toList(),
      };
}
