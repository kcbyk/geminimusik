import '../../web_search_service.dart';
import '../agent_models.dart';

/// Web araması ve sayfa okuma.
class WebTool extends AgentTool {
  WebTool({WebSearchService? search})
      : _search = search ?? WebSearchService.instance;

  final WebSearchService _search;

  @override
  String get name => 'web';

  @override
  String get description =>
      'İnternete çıkar. action=search: güncel arama sonuçları (başlık, URL, özet). '
      'action=read: bir URL\'nin metnini okur. Güncel bilgi gerekiyorsa tahmin ETME, ara.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'action': {
            'type': 'STRING',
            'enum': ['search', 'read']
          },
          'query': {
            'type': 'STRING',
            'description': 'search için arama sorgusu.'
          },
          'url': {'type': 'STRING', 'description': 'read için sayfa adresi.'},
          'limit': {
            'type': 'INTEGER',
            'description': 'search için kaç sonuç (varsayılan 5).'
          },
        },
        'required': ['action'],
      };

  @override
  bool get speaksResult => true;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final action = args['action'] as String? ?? 'search';
    if (action == 'read') {
      final url = (args['url'] as String?)?.trim() ?? '';
      if (url.isEmpty) return ToolResult.error('read için url gerekli.');
      final text = await _search.readPage(url, karakter: 6000);
      if (text == null || text.trim().isEmpty) {
        return ToolResult.error('Sayfa okunamadı: $url');
      }
      return ToolResult('URL: $url\n$text');
    }

    final query = (args['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) return ToolResult.error('search için query gerekli.');
    final limit = ((args['limit'] as num?)?.toInt() ?? 5).clamp(1, 10);
    final results = await _search.search(query, limit: limit);
    if (results.isEmpty) return ToolResult('"$query" için sonuç bulunamadı.');
    final buffer = StringBuffer();
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('[${i + 1}] ${r.title}');
      buffer.writeln('    ${r.url}');
      if (r.snippet.isNotEmpty) buffer.writeln('    ${r.snippet}');
    }
    return ToolResult(buffer.toString().trim());
  }
}
