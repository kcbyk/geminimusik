class UiAction {
  final String type; // 'prompt', 'url', 'copy', 'select', 'submit'
  final String label;
  final String? value;
  final String? icon; // icon name e.g. 'arrow_forward', 'check', 'launch'
  final String? style; // 'primary', 'secondary', 'outline', 'destructive'
  final Map<String, dynamic>? payload;

  const UiAction({
    required this.type,
    required this.label,
    this.value,
    this.icon,
    this.style,
    this.payload,
  });

  factory UiAction.fromJson(Map<String, dynamic> json) {
    return UiAction(
      type: (json['type'] ?? json['action'] ?? 'prompt').toString().toLowerCase(),
      label: (json['label'] ?? json['text'] ?? json['title'] ?? 'Seç').toString(),
      value: json['value']?.toString() ?? json['prompt']?.toString() ?? json['url']?.toString(),
      icon: json['icon']?.toString(),
      style: json['style']?.toString().toLowerCase(),
      payload: json['payload'] is Map<String, dynamic>
          ? json['payload'] as Map<String, dynamic>
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'label': label,
        if (value != null) 'value': value,
        if (icon != null) 'icon': icon,
        if (style != null) 'style': style,
        if (payload != null) 'payload': payload,
      };
}
