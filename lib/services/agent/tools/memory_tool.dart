import '../agent_memory.dart';
import '../agent_models.dart';

/// Ajanın kalıcı not defteri. Uygulama kapansa bile silinmez.
class MemoryTool extends AgentTool {
  MemoryTool({AgentMemory? memory}) : _memory = memory ?? AgentMemory();

  final AgentMemory _memory;

  @override
  String get name => 'memory';

  @override
  String get description =>
      'Kalıcı hafıza. action=add: sonraki görevlerde de hatırlaman gereken '
      'gerçeği yaz (kullanıcı tercihi, proje yapısı, cihaz özelliği, verilen söz). '
      'action=list: notları oku. action=clear: notları sil. '
      'Kısa ve tek gerçek yaz; görev özetini buraya yazma, o zaten günlüğe işleniyor.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'action': {
            'type': 'STRING',
            'enum': ['add', 'list', 'clear']
          },
          'text': {
            'type': 'STRING',
            'description': 'add için hatırlanacak tek cümlelik gerçek.',
          },
        },
        'required': ['action'],
      };

  @override
  bool get speaksResult => true;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final action = args['action'] as String? ?? 'list';
    await _memory.load();

    switch (action) {
      case 'add':
        final text = (args['text'] as String?)?.trim() ?? '';
        if (text.isEmpty) {
          return ToolResult.error('add için text gerekli.');
        }
        await _memory.addNote(text);
        return ToolResult('Hatırlandı: $text');
      case 'clear':
        await _memory.clearNotes();
        return ToolResult('Kalıcı notlar silindi.');
      case 'list':
        if (!_memory.hasNotes) {
          return ToolResult('Henüz kalıcı not yok. add ile ekleyebilirsin.');
        }
        return ToolResult(_memory.notes);
      default:
        return ToolResult.error(
            'Bilinmeyen eylem: $action. Kullanılabilecekler: add, list, clear.');
    }
  }
}
