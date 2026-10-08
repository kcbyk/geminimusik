import 'dart:io';

import '../agent_models.dart';
import 'shell_tool.dart';

/// Termux köprüsü.
///
/// Android'de bir uygulama başka uygulamanın `/data/data` klasörünü okuyamaz,
/// ama Termux'un paketleri `/data/data/com.termux/files/usr` altında durur ve
/// **çalıştırılabilir** olduklarında doğrudan çağrılabilir. Bu araç üç yol dener
/// ve hangisinin çalıştığını dürüstçe raporlar:
///
/// 1. `run`   — Termux ortamını (PREFIX, LD_LIBRARY_PATH, PATH) kurup komutu
///    doğrudan çalıştırır. Termux kuruluysa çoğu cihazda çalışır.
/// 2. `send`  — Termux'un resmî `RUN_COMMAND` intent'i ile komutu Termux'a
///    devreder (Termux'ta `allow-external-apps=true` gerekir).
/// 3. `probe` — neyin mümkün olduğunu önceden söyler; ajan olmayan bir şeyi
///    varmış gibi kullanmasın diye.
class TermuxTool extends AgentTool {
  static const String termuxHome = '/data/data/com.termux/files/home';
  static const String termuxPrefix = '/data/data/com.termux/files/usr';
  static const String termuxPackage = 'com.termux';

  @override
  String get name => 'termux';

  @override
  String get description =>
      'Termux üzerinden gerçek Linux araçlarına erişir (python, node, git, ffmpeg…). '
      'action=probe: Termux kurulu mu ve hangi yol çalışıyor. action=run: komutu '
      'Termux ortamında çalıştır. action=send: komutu Termux uygulamasına devret. '
      'Ağır işler (derleme, paket kurma) için shell yerine bunu kullan.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'action': {'type': 'STRING', 'enum': ['probe', 'run', 'send']},
          'command': {'type': 'STRING', 'description': 'run/send için komut.'},
          'timeout_seconds': {'type': 'INTEGER', 'description': 'run için süre (varsayılan 60).'},
        },
        'required': ['action'],
      };

  /// Termux'ta komut çalıştırmak cihazda kalıcı etki bırakabilir.
  @override
  bool get requiresApproval => true;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final action = args['action'] as String? ?? 'probe';
    if (action == 'probe') return _probe();

    final command = (args['command'] as String?)?.trim() ?? '';
    if (command.isEmpty) {
      return ToolResult.error('$action için command gerekli.');
    }
    if (command.length > 4000) {
      return ToolResult.error('Komut en fazla 4000 karakter olabilir.');
    }

    if (action == 'send') return _send(command);

    final timeout = Duration(
      seconds: ((args['timeout_seconds'] as num?)?.toInt() ?? 60).clamp(1, 300),
    );
    final run = await ShellTool.runRaw(
      command,
      workingDirectory: Directory.current.path,
      environment: _termuxEnvironment(),
      timeout: timeout,
    );

    final buffer = StringBuffer()
      ..writeln('exit_code: ${run.exitCode}')
      ..writeln('süre: ${run.elapsed.inMilliseconds} ms');
    if (run.timedOut) {
      buffer.writeln('UYARI: komut ${timeout.inSeconds} saniyede bitmedi, durduruldu.');
    }
    buffer.writeln('--- stdout ---');
    buffer.writeln(run.stdout.trim().isEmpty ? '(boş)' : _clip(run.stdout));
    if (run.stderr.trim().isNotEmpty) {
      buffer.writeln('--- stderr ---');
      buffer.writeln(_clip(run.stderr));
    }

    if (!run.ok) {
      buffer.writeln(
          '\nNot: Termux ikilileri bu uygulamanın kullanıcısına kapalı olabilir. '
          'O zaman action=send ile komutu Termux\'a devret ya da Termux içinde '
          '`termux-change-repo` sonrası dosyaları erişilebilir yap.');
    }
    return ToolResult(buffer.toString().trim(), ok: run.ok);
  }

  Future<ToolResult> _probe() async {
    final buffer = StringBuffer('Termux durumu:');

    final installed = await ShellTool.runRaw('pm list packages $termuxPackage');
    final isInstalled = installed.stdout.contains(termuxPackage);
    buffer.writeln('- kurulu: ${isInstalled ? 'evet' : 'hayır'}');

    final bashExists = File('$termuxPrefix/bin/bash').existsSync();
    buffer.writeln('- bash dosyası: ${bashExists ? 'var' : 'görünmüyor (izin/root gerekir)'}');

    // Gerçekten çalıştırabiliyor muyuz?
    final probeRun = await ShellTool.runRaw(
      'echo TERMUX_OK && uname -a',
      environment: _termuxEnvironment(),
      timeout: const Duration(seconds: 15),
    );
    final canRun = probeRun.ok && probeRun.stdout.contains('TERMUX_OK');
    buffer.writeln('- doğrudan çalıştırma: ${canRun ? 'ÇALIŞIYOR' : 'çalışmıyor'}');
    if (canRun) {
      buffer.writeln('- uname: ${probeRun.stdout.split('\n').last.trim()}');
    }

    buffer.writeln('- RUN_COMMAND izni manifest\'te: evet '
        '(Termux > Ayarlar > "Allow external apps" açılmalı)');
    if (!isInstalled) {
      buffer.writeln('\nTermux kurulu değil. Kullanıcıya F-Droid sürümünü kurmasını '
          'söyle (Play Store sürümü güncel değil).');
    }
    return ToolResult(buffer.toString().trim());
  }

  /// Termux'un resmî RUN_COMMAND servisine komut gönderir.
  Future<ToolResult> _send(String command) async {
    final run = await ShellTool.runRaw(
      'am broadcast --user 0 -n $termuxPackage/.app.RunCommandService '
      '-a $termuxPackage.RUN_COMMAND '
      '--es $termuxPackage.RUN_COMMAND_PATH ${_quote('/bin/bash')} '
      '--esa $termuxPackage.RUN_COMMAND_ARGUMENTS ${_quote('-c,$command')} '
      '--es $termuxPackage.RUN_COMMAND_WORKDIR ${_quote(termuxHome)} '
      '--ez $termuxPackage.RUN_COMMAND_BACKGROUND false',
      timeout: const Duration(seconds: 20),
    );
    final output = '${run.stdout}\n${run.stderr}'.trim();
    if (!run.ok || output.contains('Error') || output.contains('Exception')) {
      return ToolResult.error(
          'Komut Termux\'a gönderilemedi. Termux kurulu olmalı ve Ayarlar > '
          '"Allow external apps" açık olmalı.\nÇıktı: $output');
    }
    return ToolResult(
        'Komut Termux\'a gönderildi ve orada çalışıyor.\n'
        'Çıktıyı Termux uygulamasının kendi penceresinde görebilirsin.\n'
        'am çıktısı: $output');
  }

  Map<String, String> _termuxEnvironment() => {
        'PREFIX': termuxPrefix,
        'HOME': termuxHome,
        'TMPDIR': '$termuxPrefix/tmp',
        'LD_LIBRARY_PATH': '$termuxPrefix/lib',
        'PATH': '$termuxPrefix/bin:/system/bin:/vendor/bin:/system/bin/app_process',
        'LANG': 'en_US.UTF-8',
        'SHELL': '$termuxPrefix/bin/bash',
      };

  static String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";

  static String _clip(String value) => value.length > 12000
      ? '${value.substring(0, 12000)}\n… kısaltıldı'
      : value;
}
