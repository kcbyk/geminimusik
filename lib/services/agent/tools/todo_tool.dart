import '../agent_models.dart';

/// Ajanın planı. Model görevin başında planı yazar, her adımda günceller;
/// UI bunu canlı tik listesi olarak gösterir.
class TodoTool extends AgentTool {
  @override
  String get name => 'update_plan';

  @override
  String get description =>
      'Yapılacaklar listesini yönetir. action=set: tüm planı baştan yaz '
      '(items: [{id, text, status}]). action=update: tek maddeyi güncelle. '
      'action=list: mevcut planı gör. Çok adımlı her görevde İLK olarak set ile plan oluştur.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'action': {
            'type': 'STRING',
            'enum': ['set', 'update', 'list', 'clear']
          },
          'items': {
            'type': 'ARRAY',
            'description': 'set için plan maddeleri.',
            'items': {
              'type': 'OBJECT',
              'properties': {
                'id': {
                  'type': 'STRING',
                  'description': 'Kısa ve benzersiz kimlik, ör. "p1".'
                },
                'text': {
                  'type': 'STRING',
                  'description': 'Yapılacak iş, tek satır, Türkçe.'
                },
                'status': {
                  'type': 'STRING',
                  'enum': ['pending', 'in_progress', 'done', 'failed'],
                },
              },
              'required': ['id', 'text'],
            },
          },
          'id': {'type': 'STRING', 'description': 'update için madde kimliği.'},
          'status': {
            'type': 'STRING',
            'description': 'update için yeni durum.'
          },
        },
        'required': ['action'],
      };

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final action = args['action'] as String? ?? 'list';
    final store = AgentPlanStore.instance;

    switch (action) {
      case 'set':
        final raw = args['items'];
        if (raw is! List || raw.isEmpty) {
          return ToolResult.error(
              'set için boş olmayan items listesi gerekli.');
        }
        final items = <AgentPlanItem>[];
        for (var i = 0; i < raw.length; i++) {
          final item = raw[i];
          if (item is! Map) continue;
          items.add(AgentPlanItem.fromJson({
            'id': item['id']?.toString() ?? 'p${i + 1}',
            'text': item['text']?.toString() ?? '',
            'status': item['status']?.toString() ?? 'pending',
          }));
        }
        if (items.isEmpty) return ToolResult.error('Geçerli plan maddesi yok.');
        store.replace(items);
        return ToolResult('Plan oluşturuldu (${items.length} madde). '
            'Her adıma geçerken update ile durumunu güncelle.');
      case 'update':
        final id = args['id']?.toString() ?? '';
        final status = args['status']?.toString() ?? '';
        if (id.isEmpty || status.isEmpty) {
          return ToolResult.error('update için id ve status gerekli.');
        }
        if (!store.update(id, status)) {
          return ToolResult.error('Plan maddesi bulunamadı: $id');
        }
        return ToolResult('Plan güncellendi: $id -> $status '
            '(${store.doneCount}/${store.items.length} tamam).');
      case 'clear':
        store.clear();
        return const ToolResult('Plan temizlendi.');
      case 'list':
      default:
        if (store.isEmpty) {
          return const ToolResult('Plan boş. Önce set ile oluştur.');
        }
        return ToolResult(store.items
            .map((i) => '${i.id} [${i.status}] ${i.text}')
            .join('\n'));
    }
  }
}
