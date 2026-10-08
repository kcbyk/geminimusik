import '../../agent_terminal_service.dart';
import '../agent_models.dart';

/// Kullanıcının kendi işlettiği uzak terminal yürütücüsüne komut gönderir.
///
/// Yalnızca uygulama `--dart-define=AGENT_EXECUTOR_URL=...` ile başlatıldığında
/// kaydedilir; telefonda kabuk zaten `shell` aracıyla doğrudan çalışıyor.
/// Uzak yürütücü, ajanın bir geliştirme makinesinde derleme/test yapması
/// gerektiğinde devreye girer.
class RemoteTerminalTool extends AgentTool {
  RemoteTerminalTool({AgentTerminalService? terminal})
      : _terminal = terminal ?? AgentTerminalService();

  final AgentTerminalService _terminal;

  /// Yapılandırma yoksa araç hiç kaydedilmez.
  static bool get isAvailable => AgentTerminalService().isConfigured;

  @override
  String get name => 'remote_terminal';

  @override
  String get description =>
      'Kullanıcının kendi çalıştırdığı uzak yürütücüde komut çalıştırır '
      '(geliştirme makinesi). Telefonda çalıştırmak için shell kullan; bunu '
      'yalnızca derleme/test gibi güçlü makine gerektiren işler için seç.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'command': {
            'type': 'STRING',
            'description': 'Uzak makinede çalıştırılacak komut.',
          },
        },
        'required': ['command'],
      };

  /// Uzak makinede komut çalıştırmak kalıcı etki bırakabilir.
  @override
  bool get requiresApproval => true;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final command = (args['command'] as String?)?.trim() ?? '';
    if (command.isEmpty) {
      return ToolResult.error('Komut boş olamaz.');
    }
    final output = await _terminal.run(command);
    return ToolResult(output, ok: !output.startsWith('Yürütücü'));
  }
}
