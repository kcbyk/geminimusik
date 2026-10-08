import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../agent_models.dart';
import '../agent_paths.dart';

/// Telefonda **gerçek** kabuk. Android'de `/system/bin/sh` (toybox) her zaman
/// vardır; Termux kurulmuşsa `$PREFIX/bin` ve `python`/`node` gibi araçlar da
/// PATH'e eklenir. Uygulama kendi veri klasörüne ve (izin verildiyse)
/// /sdcard'a yazabilir.
class ShellTool extends AgentTool {
  ShellTool({Duration defaultTimeout = const Duration(seconds: 60)})
      : _defaultTimeout = defaultTimeout;

  final Duration _defaultTimeout;
  static const _maxOutput = 16000;

  /// Android'de toybox her zaman `/system/bin/sh` adresindedir; masaüstü/Linux
  /// test ortamında `/bin/sh` kullanılır.
  static String get shellBinary =>
      Platform.isAndroid ? '/system/bin/sh' : '/bin/sh';

  @override
  String get name => 'shell';

  @override
  String get description =>
      'Telefonda gerçek kabuk komutu çalıştırır (sh). Dosya listeleme, taşıma, '
      'kopyalama, arama, indirme, script çalıştırma ve test etme için kullanılır. '
      'Çıktı (stdout+stderr) ve exit code döner. Uzun süren işler için timeout_seconds ver.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'command': {
            'type': 'STRING',
            'description':
                'Çalıştırılacak kabuk komutu. Birden çok komutu && veya ; ile birleştirebilirsin.',
          },
          'cwd': {
            'type': 'STRING',
            'description':
                'Çalışma dizini (boş bırakılırsa ajan çalışma alanı).',
          },
          'timeout_seconds': {
            'type': 'INTEGER',
            'description':
                'En fazla kaç saniye beklensin (varsayılan 60, en çok 300).',
          },
        },
        'required': ['command'],
      };

  @override
  bool get requiresApproval => false; // Karar CommandRiskAnalyzer'a bırakıldı.

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final command = (args['command'] as String?)?.trim() ?? '';
    if (command.isEmpty) {
      return ToolResult.error('Komut boş olamaz.');
    }
    if (command.length > 4000) {
      return ToolResult.error('Komut en fazla 4000 karakter olabilir.');
    }

    final verdict = const CommandRiskAnalyzer().analyze(command);
    if (verdict.isBlocked) {
      return ToolResult.error(verdict.reason);
    }

    final policy = AgentPathPolicy.instance;
    final Directory workDir;
    try {
      final cwdArg = args['cwd'] as String?;
      workDir = Directory(policy.resolve(
          cwdArg == null || cwdArg.isEmpty ? policy.effectiveRoot : cwdArg));
      if (!workDir.existsSync()) {
        return ToolResult.error('Çalışma dizini yok: ${workDir.path}');
      }
    } on PathPolicyException catch (error) {
      return ToolResult.error(error.message);
    }

    final timeoutSeconds =
        (args['timeout_seconds'] as num?)?.toInt() ?? _defaultTimeout.inSeconds;
    final timeout = Duration(seconds: timeoutSeconds.clamp(1, 300));

    final stopwatch = Stopwatch()..start();
    final process = await Process.start(
      shellBinary,
      ['-c', command],
      workingDirectory: workDir.path,
      environment: _environment(),
      includeParentEnvironment: true,
      runInShell: false,
    );

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    var timedOut = false;

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .listen(stdoutBuffer.write)
        .asFuture<void>();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write)
        .asFuture<void>();

    try {
      await process.exitCode.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    await Future.wait([stdoutDone, stderrDone]).timeout(
      const Duration(seconds: 5),
      onTimeout: () => <void>[],
    );
    stopwatch.stop();

    final exitCode = timedOut ? -1 : await process.exitCode;
    final out = _clip(stdoutBuffer.toString());
    final err = _clip(stderrBuffer.toString());

    final buffer = StringBuffer()
      ..writeln('cwd: ${workDir.path}')
      ..writeln('exit_code: $exitCode')
      ..writeln('süre: ${stopwatch.elapsedMilliseconds} ms');
    if (timedOut) {
      buffer.writeln(
          'UYARI: komut ${timeout.inSeconds} saniyede bitmedi, durduruldu.');
    }
    buffer.writeln('--- stdout ---');
    buffer.writeln(out.isEmpty ? '(boş)' : out);
    if (err.trim().isNotEmpty) {
      buffer.writeln('--- stderr ---');
      buffer.writeln(err);
    }
    if (verdict.needsApproval) {
      buffer.writeln('(not: ${verdict.reason})');
    }

    final ok = !timedOut && exitCode == 0;
    return ToolResult(buffer.toString().trim(), ok: ok);
  }

  Map<String, String> _environment() {
    final root = AgentPathPolicy.instance.effectiveRoot;
    // PATH'i tamamen ezersek wc/sleep/grep gibi temel komutlar bulunamaz
    // (exit 127). Bu yüzden sistemin PATH'i sona eklenir.
    final systemPath = Platform.environment['PATH'] ??
        (Platform.isAndroid ? '/system/bin:/vendor/bin' : '/usr/bin:/bin');
    final extraPath = [
      '$root/bin',
      '/data/data/com.termux/files/usr/bin',
      if (Platform.isAndroid) '/system/bin',
      if (Platform.isAndroid) '/vendor/bin',
      systemPath,
    ].join(':');
    return {
      'HOME': root,
      'TMPDIR': '$root/tmp',
      'PATH': extraPath,
      'AGENT_WORKSPACE': root,
      'LANG': 'C.UTF-8',
    };
  }

  static String _clip(String value) {
    if (value.length <= _maxOutput) return value;
    return '${value.substring(0, _maxOutput)}\n… [${value.length - _maxOutput} karakter kısaltıldı]';
  }
}

/// Cihazdaki kod çalıştırma/test yeteneklerini keşfeder. Ajan "test et"
/// dediğinde önce burada ne var ona bakar; olmayan bir şeyi varmış gibi
/// söylemesin diye sonuç açıkça raporlanır.
class RunTestTool extends AgentTool {
  @override
  String get name => 'run_code';

  @override
  String get description =>
      'Cihazda kurulu yorumlayıcıyla kod çalıştırır veya test komutunu koşar. '
      'language: python | dart | sh | node. Önce probe ile ne kurulu öğrenebilirsin.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'action': {
            'type': 'STRING',
            'enum': ['probe', 'run_file', 'inline'],
            'description':
                'probe: hangi yorumlayıcılar kurulu; run_file: dosyayı çalıştır; inline: verdiğin kodu geçici dosyaya yazıp çalıştır.',
          },
          'language': {
            'type': 'STRING',
            'enum': ['python', 'dart', 'sh', 'node'],
          },
          'path': {
            'type': 'STRING',
            'description': 'run_file için dosya yolu.'
          },
          'code': {'type': 'STRING', 'description': 'inline için kaynak kod.'},
          'args': {
            'type': 'STRING',
            'description': 'Ek komut satırı argümanları.'
          },
        },
        'required': ['action'],
      };

  static Map<String, List<String>> get _candidates => {
        'python': [
          'python3',
          'python',
          '/data/data/com.termux/files/usr/bin/python',
        ],
        'dart': ['dart', '/data/data/com.termux/files/usr/bin/dart'],
        'node': ['node', '/data/data/com.termux/files/usr/bin/node'],
        'sh': [ShellTool.shellBinary],
      };

  /// Cihazda kod çalıştırmak kalıcı sonuç doğurabilir: kullanıcıya sorulur.
  @override
  bool get requiresApproval => true;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final action = args['action'] as String? ?? 'probe';

    if (action == 'probe') {
      final report = StringBuffer('Cihazda bulunan yorumlayıcılar:');
      for (final entry in _candidates.entries) {
        final found = await _which(entry.value);
        report.writeln('- ${entry.key}: ${found ?? 'YOK (kurulu değil)'}');
      }
      report.writeln(
          'Not: Flutter testlerini cihazda koşmak için ayrı bir test runner gerekir; '
          'dart dosyalarını `dart dosya.dart` ile doğrulayabilirsin.');
      return ToolResult(report.toString().trim());
    }

    final language = (args['language'] as String?) ?? 'sh';
    final binary = await _which(_candidates[language] ?? const ['sh']);
    if (binary == null) {
      return ToolResult.error(
          '$language cihazda kurulu değil. Önce `run_code` ile probe yapıp '
          'kullanılabilir yorumlayıcıyı seç.');
    }

    final shell = ShellTool();
    final extra = (args['args'] as String?)?.trim() ?? '';

    if (action == 'run_file') {
      final path =
          AgentPathPolicy.instance.resolve((args['path'] as String?) ?? '');
      return shell.invoke({
        'command': '${_quote(binary)} ${_quote(path)} $extra',
      });
    }

    final code = args['code'] as String? ?? '';
    if (code.trim().isEmpty) {
      return ToolResult.error('inline için `code` alanı zorunlu.');
    }
    final ext = switch (language) {
      'python' => 'py',
      'dart' => 'dart',
      'node' => 'js',
      _ => 'sh',
    };
    final root = AgentPathPolicy.instance.effectiveRoot;
    final file = File(
        '$root/.agent_scratch/run_${DateTime.now().millisecondsSinceEpoch}.$ext');
    file.parent.createSync(recursive: true);
    await file.writeAsString(code);
    return shell.invoke({
      'command': '${_quote(binary)} ${_quote(file.path)} $extra',
    });
  }

  static String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";

  static Future<String?> _which(List<String> candidates) async {
    for (final candidate in candidates) {
      try {
        if (candidate.contains('/')) {
          if (await File(candidate).exists()) return candidate;
          continue;
        }
        final result = await Process.run(ShellTool.shellBinary,
            ['-c', 'command -v ${jsonEncode(candidate)} 2>/dev/null || true']);
        final out = (result.stdout as String).trim();
        if (out.isNotEmpty) return out.split('\n').first.trim();
      } catch (_) {}
    }
    return null;
  }
}
