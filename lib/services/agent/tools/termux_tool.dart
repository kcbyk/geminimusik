import 'dart:io';

import '../agent_models.dart';
import '../agent_native.dart';
import 'shell_tool.dart';

/// Termux köprüsü.
///
/// Android'de bir uygulama başka uygulamanın `/data/data` klasörünü okuyamaz.
/// Bu yüzden Termux'a erişmenin **desteklenen** yolu Termux'un kendi
/// `RUN_COMMAND` intent'idir. Sıra şöyle:
///
/// 1. `run`  — native kanaldan `RUN_COMMAND` ile komutu Termux'a devreder ve
///    çıktıyı geri toplar (python/git/node dahil her şey çalışır).
/// 2. yedek — Termux ikilileri doğrudan çalıştırılabiliyorsa (bazı cihazlarda
///    mümkündür) komut bu uygulamanın sürecinde çalıştırılır.
/// 3. `probe`/`setup` — neyin mümkün olduğunu dürüstçe raporlar; Termux
///    `allow-external-apps=true` istiyorsa tek seferlik kurulumu adım adım
///    kullanıcıya gösterir.
class TermuxTool extends AgentTool {
  static const String termuxHome = '/data/data/com.termux/files/home';
  static const String termuxPrefix = '/data/data/com.termux/files/usr';
  static const String termuxPackage = 'com.termux';

  @override
  String get name => 'termux';

  @override
  String get description =>
      'Termux üzerinden gerçek Linux araçlarına erişir (python, node, git, ffmpeg…). '
      'action=probe: Termux kurulu mu, dışarıdan komut kabul ediyor mu, hangi yol '
      "çalışıyor. action=run: komutu Termux'ta çalıştır ve çıktıyı al. "
      'action=send: komutu Termux penceresine devret. '
      'action=setup: kullanıcının yapması gereken tek seferlik ayarı aç/göster. '
      'Ağır işler (derleme, paket kurma, python) için shell yerine bunu kullan.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'action': {
            'type': 'STRING',
            'enum': ['probe', 'run', 'send', 'setup'],
          },
          'command': {'type': 'STRING', 'description': 'run/send için komut.'},
          'timeout_seconds': {
            'type': 'INTEGER',
            'description': 'run için saniye (varsayılan 60, en fazla 300).',
          },
          'background': {
            'type': 'BOOLEAN',
            'description': 'send için: true ise çıktı beklenmez.',
          },
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
    if (action == 'setup') return _setup();

    final command = (args['command'] as String?)?.trim() ?? '';
    if (command.isEmpty) {
      return ToolResult.error('$action için command gerekli.');
    }
    if (command.length > 4000) {
      return ToolResult.error('Komut en fazla 4000 karakter olabilir.');
    }

    if (action == 'send') {
      return _send(command, background: args['background'] == true);
    }

    final timeoutSeconds =
        ((args['timeout_seconds'] as num?)?.toInt() ?? 60).clamp(1, 300);
    return _run(command, timeoutSeconds: timeoutSeconds);
  }

  // --------------------------------------------------------------------- run

  Future<ToolResult> _run(String command, {required int timeoutSeconds}) async {
    // 1) Native RUN_COMMAND: Termux'un tam ortamı (apt ile kurulan her şey).
    final info = await AgentNative.termuxInfo();
    if (info != null && info['installed'] == true) {
      final native = await AgentNative.runInTermux(
        command: command,
        timeoutSeconds: timeoutSeconds,
        workdir: termuxHome,
      );
      if (native != null) {
        return _formatNative(native, info);
      }
      if (info['externalAppsAllowed'] != true) {
        return ToolResult.error(_setupText(info));
      }
    }

    // 2) Yedek: Termux ikililerini doğrudan çalıştırmayı dene.
    final run = await ShellTool.runRaw(
      command,
      workingDirectory: Directory.current.path,
      environment: _termuxEnvironment(),
      timeout: Duration(seconds: timeoutSeconds),
    );

    final buffer = StringBuffer()
      ..writeln('exit_code: ${run.exitCode}')
      ..writeln('süre: ${run.elapsed.inMilliseconds} ms');
    if (run.timedOut) {
      buffer.writeln(
          'UYARI: komut $timeoutSeconds saniyede bitmedi, durduruldu.');
    }
    buffer.writeln('--- stdout ---');
    buffer.writeln(run.stdout.trim().isEmpty ? '(boş)' : _clip(run.stdout));
    if (run.stderr.trim().isNotEmpty) {
      buffer.writeln('--- stderr ---');
      buffer.writeln(_clip(run.stderr));
    }

    if (!run.ok) {
      buffer.writeln('\n${_blockedHint(info)}');
    }
    return ToolResult(buffer.toString().trim(), ok: run.ok);
  }

  ToolResult _formatNative(
      Map<String, dynamic> native, Map<String, dynamic> info) {
    final ok = native['ok'] == true;
    final buffer = StringBuffer()
      ..writeln('exit_code: ${native['exitCode']}')
      ..writeln('süre: ${native['elapsedMs']} ms')
      ..writeln('yol: termux RUN_COMMAND');
    if (native['timedOut'] == true) {
      buffer.writeln('UYARI: Termux sonuç döndürmedi (zaman aşımı). '
          '${native['hint'] ?? ''}');
    }
    buffer.writeln('--- stdout ---');
    final stdout = (native['stdout'] as String?)?.trim() ?? '';
    buffer.writeln(stdout.isEmpty ? '(boş)' : _clip(stdout));
    final stderr = (native['stderr'] as String?)?.trim() ?? '';
    if (stderr.isNotEmpty) {
      buffer.writeln('--- stderr ---');
      buffer.writeln(_clip(stderr));
    }
    // Termux'un kendi iç hatası (ör. izin kapalı, geçersiz extra): kabuk
    // hatasından farklıdır ve kurulum adımını gerektirir.
    final termuxErr = (native['termuxErr'] as num?)?.toInt() ?? 0;
    final errmsg = (native['termuxErrmsg'] as String?)?.trim() ?? '';
    if (termuxErr != 0 || errmsg.isNotEmpty) {
      buffer.writeln('--- termux hatası ($termuxErr) ---');
      buffer.writeln(errmsg.isEmpty ? '(açıklama yok)' : errmsg);
    }
    if (!ok && (termuxErr != 0 || info['externalAppsAllowed'] != true)) {
      buffer.writeln('\n${_setupText(info)}');
    }
    return ToolResult(buffer.toString().trim(), ok: ok);
  }

  // -------------------------------------------------------------------- send

  Future<ToolResult> _send(String command, {required bool background}) async {
    final native = await AgentNative.runInTermux(
      command: command,
      background: background,
      workdir: termuxHome,
      timeoutSeconds: 5,
    );
    if (native != null) {
      return native['ok'] == true
          ? ToolResult("Komut Termux'a gönderildi. "
              '${background ? 'Arka planda çalışıyor.' : 'Çıktı Termux penceresinde.'}')
          : ToolResult.error(
              "Komut Termux'a gönderilemedi: ${native['error']}\n"
              '${native['hint'] ?? ''}');
    }

    final run = await ShellTool.runRaw(
      'am broadcast --user 0 -n $termuxPackage/.app.RunCommandService '
      '-a $termuxPackage.RUN_COMMAND '
      '--es $termuxPackage.RUN_COMMAND_PATH ${_quote('/bin/bash')} '
      '--esa $termuxPackage.RUN_COMMAND_ARGUMENTS ${_quote('-c,$command')} '
      '--es $termuxPackage.RUN_COMMAND_WORKDIR ${_quote(termuxHome)} '
      '--ez $termuxPackage.RUN_COMMAND_BACKGROUND $background',
      timeout: const Duration(seconds: 20),
    );
    final output = '${run.stdout}\n${run.stderr}'.trim();
    if (!run.ok || output.contains('Error') || output.contains('Exception')) {
      return ToolResult.error(
          "Komut Termux'a gönderilemedi. Termux kurulu olmalı ve "
          '`allow-external-apps=true` ayarı yapılmış olmalı.\nÇıktı: $output');
    }
    return ToolResult("Komut Termux'a gönderildi ve orada çalışıyor.\n"
        'Çıktıyı Termux penceresinde görebilirsin.\nam çıktısı: $output');
  }

  // ------------------------------------------------------------------- probe

  Future<ToolResult> _probe() async {
    final buffer = StringBuffer('Termux durumu:');

    final info = await AgentNative.termuxInfo();
    if (info != null) {
      final installed = info['installed'] == true;
      buffer
        ..writeln('- kurulu: ${installed ? 'evet' : 'hayır'}')
        ..writeln('- dışarıdan komut kabul ediyor: '
            '${info['externalAppsAllowed'] == true ? 'evet' : 'hayır'}')
        ..writeln('- RUN_COMMAND izni: '
            '${info['runCommandPermission'] == true ? 'verilmiş' : 'verilmemiş'}')
        ..writeln('- doğrudan ikili çalıştırma: '
            '${info['prefixExists'] == true ? 'dosyalar görünüyor' : 'görünmüyor (Android kısıtlıyor)'}')
        ..writeln('- ölçüm: ${info['message']}');
      if (!installed) {
        buffer.writeln(
            '\nTermux kurulu değil. python/git/node gerekiyorsa tek yol Termux '
            'kurmak: device(action="install_app", query="com.termux").');
        return ToolResult(buffer.toString().trim());
      }
      if (info['externalAppsAllowed'] != true) {
        buffer.writeln('\n${_setupText(info)}');
      }
      return ToolResult(buffer.toString().trim());
    }

    // --- native katman yok: kabukla ölç ---
    final installed = await ShellTool.runRaw('pm list packages $termuxPackage');
    final isInstalled = installed.stdout.contains(termuxPackage);
    buffer.writeln('- kurulu: ${isInstalled ? 'evet' : 'hayır'}');

    final bashExists = File('$termuxPrefix/bin/bash').existsSync();
    buffer.writeln(
        '- bash dosyası: ${bashExists ? 'var' : 'görünmüyor (izin/root gerekir)'}');

    final probeRun = await ShellTool.runRaw(
      'echo TERMUX_OK && uname -a',
      environment: _termuxEnvironment(),
      timeout: const Duration(seconds: 15),
    );
    final canRun = probeRun.ok && probeRun.stdout.contains('TERMUX_OK');
    buffer.writeln(
        '- doğrudan çalıştırma: ${canRun ? 'ÇALIŞIYOR' : 'çalışmıyor'}');
    if (canRun) {
      buffer.writeln('- uname: ${probeRun.stdout.split('\n').last.trim()}');
    }
    buffer.writeln('- native RUN_COMMAND kanalı: bu sürümde yok');
    if (!isInstalled) {
      buffer.writeln(
          '\nTermux kurulu değil. Kullanıcıya F-Droid sürümünü kurmasını söyle '
          '(Play Store sürümü güncel değil).');
    } else {
      buffer.writeln('\n${_blockedHint(null)}');
    }
    return ToolResult(buffer.toString().trim());
  }

  // ------------------------------------------------------------------- setup

  Future<ToolResult> _setup() async {
    final info = await AgentNative.termuxInfo();
    if (info == null) {
      return ToolResult.error(
          'Termux kurulum ekranı bu sürümde açılamıyor (native katman yok). '
          'Kullanıcıya adımları elle göster.');
    }
    if (info['installed'] != true) {
      final opened = await AgentNative.termuxOpenStore();
      return opened?['ok'] == true
          ? ToolResult(
              'Termux kurulu değil — mağaza sayfası açıldı. Kurulumu kullanıcı onaylayacak.')
          : ToolResult.error('Termux kurulu değil ve mağaza açılamadı.');
    }
    if (info['externalAppsAllowed'] == true) {
      return ToolResult('Zaten hazır: Termux dışarıdan komut kabul ediyor.');
    }
    return ToolResult(_setupText(info));
  }

  // ----------------------------------------------------------------- helpers

  String _setupText(Map<String, dynamic> info) {
    final buffer = StringBuffer()
      ..writeln('TERMUX TEK SEFERLİK AYAR (kullanıcıya aynen göster):');
    final steps = (info['setupSteps'] as List?) ?? const <String>[];
    for (var i = 0; i < steps.length; i++) {
      buffer.writeln('${i + 1}. ${steps[i]}');
    }
    buffer.writeln(
        "Bu ayar yapılmadan Termux'ta komut çalıştırılamaz; python/git/node "
        'gibi araçlara erişilemez.');
    return buffer.toString().trim();
  }

  String _blockedHint(Map<String, dynamic>? info) {
    if (info != null && info['installed'] == true) {
      return 'Termux kurulu ama komut kabul etmiyor. action=setup ile tek seferlik '
          'ayarı kullanıcıya göster (allow-external-apps=true).';
    }
    return 'Termux ikilileri bu uygulamanın kullanıcısına kapalı. Termux kuruluysa '
        'action=setup ile tek seferlik `allow-external-apps=true` ayarını yaptır; '
        'kurulu değilse önce Termux kurulmalı.';
  }

  Map<String, String> _termuxEnvironment() => {
        'PREFIX': termuxPrefix,
        'HOME': termuxHome,
        'TMPDIR': '$termuxPrefix/tmp',
        'LD_LIBRARY_PATH': '$termuxPrefix/lib',
        'PATH':
            '$termuxPrefix/bin:/system/bin:/vendor/bin:/system/bin/app_process',
        'LANG': 'en_US.UTF-8',
        'SHELL': '$termuxPrefix/bin/bash',
      };

  static String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";

  static String _clip(String value) => value.length > 12000
      ? '${value.substring(0, 12000)}\n… kısaltıldı'
      : value;
}
