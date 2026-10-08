import 'dart:io';

/// Dosya yolu politikası + komut risk analizi.
///
/// Telefon kök bir makine değildir: ajan istediği yere yazabilsin istiyoruz ama
/// **sessizce** her şeyi silmesin de istiyoruz. Bu yüzden iki katman var:
/// 1. Yol politikası (varsayılan olarak uygulama çalışma alanı, ayarlardan açılınca sınırsız).
/// 2. Risk analizi (onay sorulacak komutları işaretler, geri döndürülemez olanları engeller).
class AgentPathPolicy {
  AgentPathPolicy._();
  static final AgentPathPolicy instance = AgentPathPolicy._();

  /// `true` ise ajan cihazda her yola dokunabilir.
  bool allowUnrestrictedPaths = false;

  String? _root;
  String? get root => _root;

  /// Uygulama başlarken bir kez çağrılır (path_provider ile).
  void configureRoot(String path) {
    _root = _normalize(path);
  }

  String get effectiveRoot => _root ?? Directory.current.path;

  /// Göreli yolları çalışma alanına bağlar, `..` kaçışlarını kontrol eder.
  /// Kısıtlı modda alan dışına çıkan yollar [PathPolicyException] fırlatır.
  String resolve(String input) {
    final cleaned = input.trim();
    if (cleaned.isEmpty) {
      throw const PathPolicyException('Dosya yolu boş olamaz.');
    }

    var path = cleaned.startsWith('/') || cleaned.startsWith('~')
        ? cleaned
        : '$effectiveRoot/$cleaned';
    path = _normalize(
        path.startsWith('~') ? '$effectiveRoot/${path.substring(1)}' : path);

    if (allowUnrestrictedPaths) return path;

    final root = _normalize(effectiveRoot);
    if (path == root || path.startsWith('$root/')) return path;

    throw PathPolicyException(
      '"$cleaned" ajan çalışma alanının ($root) dışında. '
      'Ayarlar menüsünden "Sınırsız dosya erişimi"ni açarsan cihazın tamamına yazabilirim.',
    );
  }

  /// Bir komutun hedef aldığı yolları kaba kuvvetle çözer (ls/cd argümanları gibi).
  /// Yalnızca bilgilendirme amaçlıdır; güvenlik sınırı `resolve` içindedir.
  bool isInsideWorkspace(String path) {
    final resolved = _normalize(path);
    final root = _normalize(effectiveRoot);
    return resolved == root || resolved.startsWith('$root/');
  }

  static String _normalize(String path) {
    final isAbsolute = path.startsWith('/');
    final segments = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (segments.isNotEmpty) segments.removeLast();
        continue;
      }
      segments.add(part);
    }
    final joined = segments.join('/');
    return isAbsolute ? '/$joined' : joined;
  }
}

class PathPolicyException implements Exception {
  final String message;
  const PathPolicyException(this.message);
  @override
  String toString() => message;
}

enum CommandRisk { safe, needsApproval, blocked }

class CommandRiskVerdict {
  final CommandRisk level;
  final String reason;
  const CommandRiskVerdict(this.level, this.reason);

  bool get isBlocked => level == CommandRisk.blocked;
  bool get needsApproval => level == CommandRisk.needsApproval;
}

/// Kabuk komutunu çalıştırmadan önce tarar.
class CommandRiskAnalyzer {
  const CommandRiskAnalyzer();

  /// Geri döndürülemez hasar veren kalıplar: hiç çalıştırmayız.
  static const List<List<String>> _blockedPatterns = [
    ['rm', '-rf /'],
    ['rm', '-fr /'],
    ['rm', '-rf /*'],
    ['rm', '-rf ~'],
    ['mkfs'],
    ['dd if=', 'of=/dev/'],
    [':(){'],
    ['> /dev/sda'],
    ['chmod', '-R 777 /'],
    ['chown', '-R', '/ '],
    ['wipefs'],
    ['shred /dev/'],
  ];

  /// Riskli ama meşru olabilir: kullanıcıya sorulur.
  static const List<String> _approvalKeywords = [
    'rm -r',
    'rm -f',
    'rm -fr',
    'rmdir',
    'mv ',
    'kill ',
    'killall',
    'chmod',
    'chown',
    'mount',
    'umount',
    'reboot',
    'shutdown',
    'am force-stop',
    'pm uninstall',
    'pm clear',
    'settings put',
    'svc wifi',
    'svc data',
    'input keyevent',
    'curl -o',
    'wget -O',
    'dd ',
    'mkfifo',
    '> /sdcard/',
  ];

  CommandRiskVerdict analyze(String command) {
    final lower = ' ${command.toLowerCase().replaceAll(RegExp(r'\s+'), ' ')} ';

    for (final pattern in _blockedPatterns) {
      var matches = true;
      for (final fragment in pattern) {
        if (!lower.contains(fragment.toLowerCase())) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return CommandRiskVerdict(
          CommandRisk.blocked,
          'Geri döndürülemez hasar verebilecek komut engellendi: "${pattern.join(' ')}".',
        );
      }
    }

    for (final keyword in _approvalKeywords) {
      if (lower.contains(keyword)) {
        return CommandRiskVerdict(
          CommandRisk.needsApproval,
          'Komut cihazda kalıcı değişiklik yapabilir ($keyword).',
        );
      }
    }

    return const CommandRiskVerdict(
        CommandRisk.safe, 'Salt okunur/geri alınabilir komut.');
  }
}
