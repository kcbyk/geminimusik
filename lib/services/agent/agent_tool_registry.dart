import 'agent_models.dart';
import 'tools/file_tools.dart';
import 'tools/music_tool.dart';
import 'tools/phone_tool.dart';
import 'tools/remote_terminal_tool.dart';
import 'tools/shell_tool.dart';
import 'tools/todo_tool.dart';
import 'tools/web_tool.dart';

/// Varsayılan araç setlerini kuran fabrika.
class AgentToolRegistryBuilder {
  const AgentToolRegistryBuilder._();

  /// Tam set: plan + dosya + kabuk + kod + web + müzik + telefon.
  static AgentToolRegistry full() {
    final registry = AgentToolRegistry();
    registry.registerAll([
      TodoTool(),
      ListDirTool(),
      ReadFileTool(),
      WriteFileTool(),
      EditFileTool(),
      MoveFileTool(),
      SearchFilesTool(),
      ShellTool(),
      RunTestTool(),
      WebTool(),
      MusicTool(),
      PhoneTool(),
      if (RemoteTerminalTool.isAvailable) RemoteTerminalTool(),
    ]);
    return registry;
  }

  /// Sesli asistan (Jarvis) seti: hızlı, cihaz odaklı, dosya/kabuk yok.
  static AgentToolRegistry voice() {
    final registry = AgentToolRegistry();
    registry.registerAll([
      MusicTool(),
      PhoneTool(),
      WebTool(),
    ]);
    return registry;
  }

  /// Sadece dosya/kabuk: geliştirici modu.
  static AgentToolRegistry developer() {
    final registry = AgentToolRegistry();
    registry.registerAll([
      TodoTool(),
      ListDirTool(),
      ReadFileTool(),
      WriteFileTool(),
      EditFileTool(),
      MoveFileTool(),
      SearchFilesTool(),
      ShellTool(),
      RunTestTool(),
      if (RemoteTerminalTool.isAvailable) RemoteTerminalTool(),
    ]);
    return registry;
  }
}
