import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../agent_models.dart';
import '../agent_paths.dart';

/// [ShellTool.runRaw] sonucu. Politika kontrolü yapmadan çalışan ham çıktı.
class ShellRunResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final Duration elapsed;

  const ShellRunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
    required this.elapsed,
  });

  bool get ok => !timedOut && exitCode == 0;
}

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
      'Telefonun kendi kabuğunda (Android: /system/bin/sh, toybox) komut çalıştırır. '
      'ls, cat, mkdir, cp, mv, rm, grep, wc, du, df, ps, getprop, id, date, sleep gibi '
      'komutlar kullanılabilir. command: çalıştırılacak komut satırı. '
      'timeout: saniye (1-300). working_dir: çalışma klasörü.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'command': {
            'type': 'STRING',
            'description':
                'Kabuk komutu. Zincirleme için && veya ; kullanabilirsin.',
          },
          'timeout': {
            'type': 'NUMBER',
            'description': 'Zaman aşımı (saniye). Varsayılan 60.',
          },
          'working_dir': {
            'type': 'STRING',
            'description': 'Çalışma klasörü. Varsayılan ajan çalışma alanı.',
          },
        },
        'required': ['command'],
      };

  /// Politika kontrolü yapmadan komut çalıştıran düşük seviye yardımcı.
  /// `device` ve `termux` araçları bunu kullanır; kullanıcı onayı ve risk
  /// analizi [AgentLoop] tarafında zaten uygulanıyor.
  static Future<ShellRunResult> runRaw(
    String command, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final stopwatch = Stopwatch()..start();
    final process = await Process.start(
      shellBinary,
      ['-c', command],
      workingDirectory: workingDirectory,
      environment: environment ?? const {},
      includeParentEnvironment: true,
      runInShell: false,
    );

    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();

    var exitCode = -1;
    var timedOut = false;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      try {
        exitCode = await process.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        exitCode = -1;
      }
    }
    stopwatch.stop();

    return ShellRunResult(
      exitCode: exitCode,
      stdout: await stdoutFuture,
      stderr: await stderrFuture,
      timedOut: timedOut,
      elapsed: stopwatch.elapsed,
    );
  }

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final command = (args['command'] as String?)?.trim() ?? '';
    if (command.isEmpty) {
      return ToolResult.error('`command` alanı boş olamaz.');
    }

    final timeout = _parseTimeout(args['timeout'] ?? args['timeout_seconds']);
    final workDir = _resolveWorkDir(args['working_dir'] as String?);

    const analyzer = CommandRiskAnalyzer();
    final verdict = analyzer.analyze(command);
    if (verdict.isBlocked) {
      return ToolResult.error('Bu komut cihazda engellendi: ${verdict.reason}');
    }

    final run = await runRaw(
      command,
      workingDirectory: workDir.path,
      environment: _environment(),
      timeout: timeout,
    );
    final timedOut = run.timedOut;
    final exitCode = run.exitCode;

    final out = _clip(run.stdout);
    final err = _clip(run.stderr);

    final buffer = StringBuffer()
      ..writeln('cwd: ${workDir.path}')
      ..writeln('exit_code: $exitCode')
      ..writeln('süre: ${run.elapsed.inMilliseconds} ms');
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

  Duration _parseTimeout(Object? raw) {
    final parsed = raw is num
        ? raw.toInt()
        : int.tryParse('${raw ?? ''}'.trim()) ?? _defaultTimeout.inSeconds;
    final seconds = parsed.clamp(1, 300);
    return Duration(seconds: seconds);
  }

  Directory _resolveWorkDir(String? requested) {
    if (requested == null || requested.trim().isEmpty) {
      final root = AgentPathPolicy.instance.effectiveRoot;
      final dir = Directory(root);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    }
    final path = AgentPathPolicy.instance.resolve(requested.trim());
    final dir = Directory(path);
    if (!dir.existsSync()) {
      throw PathPolicyException('Çalışma klasörü yok: ${dir.path}');
    }
    return dir;
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
