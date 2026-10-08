import 'dart:async';
import 'dart:convert';

import 'turn_model.dart';

/// Bir araç adımının yaşam döngüsü.
enum AgentStepStatus { running, done, error, denied, cancelled }

enum AgentEventType {
  /// Kullanıcının verdiği görev (timeline'a düşer).
  task,

  /// Ajanın planı (todo listesi) güncellendi.
  plan,

  /// Bir araç adımı eklendi/güncellendi.
  step,

  /// Model ara metin üretti ("şimdi şunu kontrol ediyorum…").
  modelText,

  /// Tur bitti: final yanıt hazır.
  done,

  /// Döngü hata verdi ya da kullanıcı iptal etti.
  error,
}

/// Timeline'da gösterilen tek bir araç adımı.
class AgentStep {
  final int index;
  final String toolName;
  final Map<String, dynamic> args;
  final AgentStepStatus status;
  final String result;
  final Duration elapsed;
  final String? note;

  const AgentStep({
    required this.index,
    required this.toolName,
    required this.args,
    this.status = AgentStepStatus.running,
    this.result = '',
    this.elapsed = Duration.zero,
    this.note,
  });

  bool get isFinished => status != AgentStepStatus.running;

  /// Aynı aracın aynı argümanlarla tekrar tekrar çağrılmasını yakalamak için.
  String get signature => '$toolName::${jsonEncode(args)}';

  String get argsSummary {
    if (args.isEmpty) return '';
    try {
      return const JsonEncoder.withIndent('  ').convert(args);
    } catch (_) {
      return args.toString();
    }
  }

  AgentStep copyWith({
    AgentStepStatus? status,
    String? result,
    Duration? elapsed,
    String? note,
  }) =>
      AgentStep(
        index: index,
        toolName: toolName,
        args: args,
        status: status ?? this.status,
        result: result ?? this.result,
        elapsed: elapsed ?? this.elapsed,
        note: note ?? this.note,
      );
}

/// Plan maddesi (A'dan Z'ye yapılacaklar).
class AgentPlanItem {
  final String id;
  final String text;
  final String status; // pending | in_progress | done | failed

  const AgentPlanItem({
    required this.id,
    required this.text,
    this.status = 'pending',
  });

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'status': status};

  factory AgentPlanItem.fromJson(Map<dynamic, dynamic> json) => AgentPlanItem(
        id: json['id']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        status: json['status']?.toString() ?? 'pending',
      );
}

/// Ajan olayı: UI yalnızca bunu dinler, ajan çekirdeği Flutter bilmez.
class AgentEvent {
  final AgentEventType type;
  final AgentStep? step;
  final List<AgentPlanItem>? plan;
  final String? message;
  final bool cancelled;

  const AgentEvent({
    required this.type,
    this.step,
    this.plan,
    this.message,
    this.cancelled = false,
  });
}

/// Araçların ortak arayüzü.
class ToolResult {
  final bool ok;
  final String output;

  const ToolResult(this.output, {this.ok = true});
  factory ToolResult.error(String output) => ToolResult(output, ok: false);
}

abstract class AgentTool {
  /// Modelin göreceği fonksiyon adı (snake_case).
  String get name;

  /// Modelin bu aracı ne zaman seçeceğini anlatan Türkçe açıklama.
  String get description;

  /// JSON Schema (`parameters`).
  Map<String, dynamic> get parameters;

  /// Onay istenmeden çalıştırılabilir mi?
  bool get requiresApproval => false;

  /// Seste okunabilir kısa özet üretir (Jarvis yolu için).
  bool get speaksResult => false;

  Future<ToolResult> invoke(Map<String, dynamic> args);

  Map<String, dynamic> get declaration => {
        'name': name,
        'description': description,
        'parameters': parameters,
      };
}

/// Araç kayıt defteri.
class AgentToolRegistry {
  final Map<String, AgentTool> _tools = {};

  void register(AgentTool tool) => _tools[tool.name] = tool;

  void registerAll(Iterable<AgentTool> tools) {
    for (final tool in tools) {
      register(tool);
    }
  }

  AgentTool? operator [](String name) => _tools[name];

  bool get isEmpty => _tools.isEmpty;
  int get length => _tools.length;
  List<AgentTool> get tools => _tools.values.toList();

  List<Map<String, dynamic>> get schemas =>
      _tools.values.map((t) => t.declaration).toList();

  /// Modele "elimde hangi araçlar var" bilgisini metin olarak da veririz;
  /// bazı modeller açıklama dışında ipucu istediğinde daha doğru seçiyor.
  String describeForPrompt() {
    if (_tools.isEmpty) return '';
    final buffer = StringBuffer();
    for (final tool in _tools.values) {
      final required = (tool.parameters['required'] as List?)?.join(', ') ?? '';
      buffer.writeln('- ${tool.name}: ${tool.description}'
          '${required.isEmpty ? '' : ' (zorunlu: $required)'}');
    }
    return buffer.toString().trim();
  }
}

/// Plan deposu: UI ile ajan çekirdeği arasındaki tek bağlantı.
class AgentPlanStore {
  AgentPlanStore._();
  static final AgentPlanStore instance = AgentPlanStore._();

  final List<AgentPlanItem> _items = [];
  final StreamController<List<AgentPlanItem>> _controller =
      StreamController<List<AgentPlanItem>>.broadcast();

  List<AgentPlanItem> get items => List.unmodifiable(_items);
  Stream<List<AgentPlanItem>> get onChange => _controller.stream;
  bool get isEmpty => _items.isEmpty;

  int get doneCount => _items.where((i) => i.status == 'done').length;

  void replace(List<AgentPlanItem> items) {
    _items
      ..clear()
      ..addAll(items);
    _controller.add(this.items);
  }

  /// Madde bulunup güncellendiyse true döner.
  bool update(String id, String status) {
    final index = _items.indexWhere((i) => i.id == id);
    if (index < 0) return false;
    _items[index] = AgentPlanItem(
      id: _items[index].id,
      text: _items[index].text,
      status: status,
    );
    _controller.add(items);
    return true;
  }

  void clear() {
    _items.clear();
    _controller.add(const []);
  }
}

/// Araç çıktısını modele geri gönderilecek biçime sokar.
String wrapToolResponse(String output, {bool ok = true}) {
  final trimmed = truncateToolOutput(output.trim());
  return trimmed.isEmpty
      ? (ok ? 'Tamamlandı (araç çıktı üretmedi).' : 'Araç çıktı üretmedi.')
      : trimmed;
}
