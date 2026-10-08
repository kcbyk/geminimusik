import 'dart:io';

import '../agent_models.dart';
import '../agent_paths.dart';

/// Dosya okuma (satır aralığı destekli).
class ReadFileTool extends AgentTool {
  @override
  String get name => 'read_file';

  @override
  String get description =>
      'Dosya içeriğini okur. Büyük dosyalarda offset/limit ile parça parça oku. '
      'Bir şey yazdığını/düzenlediğini iddia etmeden ÖNCE mutlaka bununla doğrula.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'path': {'type': 'STRING'},
          'offset': {
            'type': 'INTEGER',
            'description': 'Başlangıç satırı (1 tabanlı).'
          },
          'limit': {
            'type': 'INTEGER',
            'description': 'En fazla kaç satır (varsayılan 400).'
          },
        },
        'required': ['path'],
      };

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    try {
      final path =
          AgentPathPolicy.instance.resolve(args['path'] as String? ?? '');
      final file = File(path);
      if (!file.existsSync()) {
        if (Directory(path).existsSync()) {
          return ToolResult.error(
              '"$path" bir klasör. İçeriğini listelemek için list_dir kullan.');
        }
        return ToolResult.error('Dosya bulunamadı: $path');
      }
      final length = file.lengthSync();
      if (length > 4 * 1024 * 1024) {
        return ToolResult.error(
            'Dosya çok büyük (${(length / 1024 / 1024).toStringAsFixed(1)} MB). '
            'shell ile `head`/`grep` kullan.');
      }
      final lines = await file.readAsLines();
      final offset = ((args['offset'] as num?)?.toInt() ?? 1)
          .clamp(1, lines.isEmpty ? 1 : lines.length);
      final limit = ((args['limit'] as num?)?.toInt() ?? 400).clamp(1, 4000);
      final end = (offset - 1 + limit).clamp(0, lines.length);
      final slice = lines.sublist(offset - 1, end);
      final numbered = <String>[];
      for (var i = 0; i < slice.length; i++) {
        numbered.add('${(offset + i).toString().padLeft(5)} | ${slice[i]}');
      }
      final header = '$path — ${lines.length} satır, $length bayt'
          '${end < lines.length ? ' (satır $offset-$end gösterildi)' : ''}';
      return ToolResult('$header\n${numbered.join('\n')}');
    } on PathPolicyException catch (error) {
      return ToolResult.error(error.message);
    } catch (error) {
      return ToolResult.error('Okuma hatası: $error');
    }
  }
}

/// Dosya yazma/oluşturma (klasörleri de oluşturur).
class WriteFileTool extends AgentTool {
  @override
  String get name => 'write_file';

  @override
  String get description =>
      'Dosya oluşturur veya içeriğini tamamen değiştirir. Klasör yoksa oluşturur. '
      'Mevcut dosyayı kısmen değiştireceksen edit_file kullan, bunu değil.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'path': {'type': 'STRING'},
          'content': {'type': 'STRING', 'description': 'Dosyanın TAM içeriği.'},
          'append': {'type': 'BOOLEAN', 'description': 'true ise sona ekler.'},
        },
        'required': ['path', 'content'],
      };

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    try {
      final path =
          AgentPathPolicy.instance.resolve(args['path'] as String? ?? '');
      final content = args['content'] as String? ?? '';
      final append = args['append'] == true;
      final file = File(path);
      final existed = file.existsSync();
      if (existed && Directory(path).existsSync()) {
        return ToolResult.error('"$path" bir klasör, dosya olarak yazılamaz.');
      }
      file.parent.createSync(recursive: true);
      if (append) {
        await file.writeAsString(content, mode: FileMode.append);
      } else {
        await file.writeAsString(content);
      }
      final lines = content.split('\n').length;
      return ToolResult('${existed ? 'Güncellendi' : 'Oluşturuldu'}: $path '
          '(${content.length} bayt, $lines satır, ${append ? 'append' : 'overwrite'}). '
          'Doğrulamak için read_file kullan.');
    } on PathPolicyException catch (error) {
      return ToolResult.error(error.message);
    } catch (error) {
      return ToolResult.error('Yazma hatası: $error');
    }
  }
}

/// İlk eşleşmeyi değiştiren güvenli düzenleyici (fuzzy değil, birebir+boşluk toleranslı).
class EditFileTool extends AgentTool {
  @override
  String get name => 'edit_file';

  @override
  String get description =>
      'Dosyada old_text ile verdiğin ilk bloğu new_text ile değiştirir. '
      'old_text dosyada birebir (girinti farkı tolere edilerek) geçmelidir; '
      'bulunamazsa hata döner, o zaman read_file ile gerçek içeriğe bak.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'path': {'type': 'STRING'},
          'old_text': {'type': 'STRING'},
          'new_text': {'type': 'STRING'},
          'replace_all': {
            'type': 'BOOLEAN',
            'description': 'true ise tüm eşleşmeleri değiştirir.'
          },
        },
        'required': ['path', 'old_text', 'new_text'],
      };

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    try {
      final path =
          AgentPathPolicy.instance.resolve(args['path'] as String? ?? '');
      final oldText = args['old_text'] as String? ?? '';
      final newText = args['new_text'] as String? ?? '';
      final replaceAll = args['replace_all'] == true;
      if (oldText.isEmpty) return ToolResult.error('old_text boş olamaz.');

      final file = File(path);
      if (!file.existsSync()) {
        return ToolResult.error('Dosya bulunamadı: $path');
      }
      final original = await file.readAsString();

      String updated;
      int changes;
      if (original.contains(oldText)) {
        changes = replaceAll ? oldText.allMatches(original).length : 1;
        updated = replaceAll
            ? original.replaceAll(oldText, newText)
            : original.replaceFirst(oldText, newText);
      } else {
        // Girinti/boşluk farkını tolere eden yedek yol.
        final match = _fuzzyFirstMatch(original, oldText);
        if (match == null) {
          return ToolResult.error(
              'old_text dosyada bulunamadı. read_file ile tam içeriği görüp '
              'birebir kopyala (satır sonu ve girintiler dahil).');
        }
        changes = 1;
        updated = original.replaceRange(match.$1, match.$2, newText);
      }

      if (updated == original) {
        return ToolResult.error(
            'Değişiklik üretilmedi: old_text ile new_text aynı.');
      }
      await file.writeAsString(updated);
      return ToolResult('$path güncellendi ($changes değişiklik). '
          'Doğrulamak için read_file kullan.');
    } on PathPolicyException catch (error) {
      return ToolResult.error(error.message);
    } catch (error) {
      return ToolResult.error('Düzenleme hatası: $error');
    }
  }

  /// Satırları normalize ederek (trim) ilk eşleşmenin karakter aralığını bulur.
  static (int, int)? _fuzzyFirstMatch(String source, String needle) {
    final needleLines = needle
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (needleLines.isEmpty) return null;

    final lines = source.split('\n');
    var cursor = 0;
    var charIndex = 0;
    final lineStarts = <int>[];
    for (final line in lines) {
      lineStarts.add(charIndex);
      charIndex += line.length + 1;
    }

    while (cursor < lines.length) {
      if (lines[cursor].trim() == needleLines.first) {
        var matched = 1;
        var probe = cursor + 1;
        var needleIndex = 1;
        while (needleIndex < needleLines.length && probe < lines.length) {
          if (lines[probe].trim().isEmpty) {
            probe++;
            continue;
          }
          if (lines[probe].trim() != needleLines[needleIndex]) break;
          matched++;
          needleIndex++;
          probe++;
        }
        if (needleIndex == needleLines.length) {
          final start = lineStarts[cursor];
          final lastLine = probe - 1;
          final end = lastLine + 1 < lineStarts.length
              ? lineStarts[lastLine + 1]
              : source.length;
          return (start, end);
        }
        cursor += matched;
      } else {
        cursor++;
      }
    }
    return null;
  }
}

/// Taşıma / kopyalama / silme / klasör oluşturma.
class MoveFileTool extends AgentTool {
  @override
  String get name => 'move_file';

  @override
  String get description =>
      'Dosya veya klasörü taşır, kopyalar, siler ya da yeni klasör oluşturur. '
      'Silme işlemi geri alınamaz: hedefi mutlaka tam yol olarak ver.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'action': {
            'type': 'STRING',
            'enum': ['move', 'copy', 'delete', 'mkdir'],
          },
          'source': {
            'type': 'STRING',
            'description': 'Kaynak yol (mkdir için hedef klasör).'
          },
          'destination': {
            'type': 'STRING',
            'description': 'move/copy için hedef yol.'
          },
        },
        'required': ['action', 'source'],
      };

  /// Silme kalıcıdır: kullanıcı onayı istenir.
  @override
  bool get requiresApproval => false;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final policy = AgentPathPolicy.instance;
    final action = args['action'] as String? ?? 'move';
    try {
      final source = policy.resolve(args['source'] as String? ?? '');
      switch (action) {
        case 'mkdir':
          final dir = Directory(source);
          if (dir.existsSync()) return ToolResult('Klasör zaten var: $source');
          dir.createSync(recursive: true);
          return ToolResult('Klasör oluşturuldu: $source');
        case 'delete':
          if (FileSystemEntity.typeSync(source) ==
              FileSystemEntityType.notFound) {
            return ToolResult.error('Silinecek yol yok: $source');
          }
          if (Directory(source).existsSync()) {
            Directory(source).deleteSync(recursive: true);
          } else {
            File(source).deleteSync();
          }
          return ToolResult('Silindi: $source');
        case 'copy':
        case 'move':
          final destination =
              policy.resolve(args['destination'] as String? ?? '');
          if (FileSystemEntity.typeSync(source) ==
              FileSystemEntityType.notFound) {
            return ToolResult.error('Kaynak yok: $source');
          }
          final destDir = Directory(destination).parent;
          if (!destDir.existsSync()) destDir.createSync(recursive: true);
          final isDir = Directory(source).existsSync();
          if (action == 'move') {
            if (isDir) {
              Directory(source).renameSync(destination);
            } else {
              File(source).renameSync(destination);
            }
            return ToolResult('Taşındı: $source -> $destination');
          }
          if (isDir) {
            await _copyDirectory(Directory(source), Directory(destination));
          } else {
            await File(source).copy(destination);
          }
          return ToolResult('Kopyalandı: $source -> $destination');
        default:
          return ToolResult.error('Bilinmeyen işlem: $action');
      }
    } on PathPolicyException catch (error) {
      return ToolResult.error(error.message);
    } catch (error) {
      return ToolResult.error('Dosya işlemi hatası: $error');
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!destination.existsSync()) destination.createSync(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final target = '${destination.path}/${entity.uri.pathSegments.last}';
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        await entity.copy(target);
      }
    }
  }
}

/// Klasör listeleme (ağaç benzeri, boyut bilgisiyle).
class ListDirTool extends AgentTool {
  @override
  String get name => 'list_dir';

  @override
  String get description =>
      'Klasör içeriğini listeler. recursive=true ile alt klasörleri de gezer. '
      'Bir proje üzerinde çalışmaya başlamadan önce buradan yapıyı gör.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'path': {'type': 'STRING'},
          'recursive': {'type': 'BOOLEAN'},
          'limit': {
            'type': 'INTEGER',
            'description': 'En fazla kaç satır (varsayılan 300).'
          },
        },
        'required': ['path'],
      };

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    try {
      final path =
          AgentPathPolicy.instance.resolve(args['path'] as String? ?? '');
      final dir = Directory(path);
      if (!dir.existsSync()) return ToolResult.error('Klasör yok: $path');
      final recursive = args['recursive'] == true;
      final limit = ((args['limit'] as num?)?.toInt() ?? 300).clamp(10, 2000);

      final lines = <String>[];
      var truncated = false;
      await for (final entity
          in dir.list(recursive: recursive, followLinks: false)) {
        if (lines.length >= limit) {
          truncated = true;
          break;
        }
        final relative =
            entity.path.replaceFirst(path, '').replaceFirst('/', '');
        if (entity is Directory) {
          lines.add('$relative/');
        } else if (entity is File) {
          lines.add('$relative  (${entity.lengthSync()} bayt)');
        }
      }
      if (lines.isEmpty) return ToolResult('$path boş.');
      return ToolResult('$path\n${lines.join('\n')}'
          '${truncated ? '\n… ($limit satırda kesildi)' : ''}');
    } on PathPolicyException catch (error) {
      return ToolResult.error(error.message);
    } catch (error) {
      return ToolResult.error('Listeleme hatası: $error');
    }
  }
}

/// Dosya adı veya içerik arama.
class SearchFilesTool extends AgentTool {
  @override
  String get name => 'search_files';

  @override
  String get description =>
      'Dosya adı (name_contains) veya dosya içeriği (text_contains) arar. '
      'Kodda bir sembolü bulmak için bunu kullan, shell grep yerine bunu tercih et.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'path': {'type': 'STRING', 'description': 'Aranacak kök klasör.'},
          'name_contains': {'type': 'STRING'},
          'text_contains': {'type': 'STRING'},
          'limit': {
            'type': 'INTEGER',
            'description': 'En fazla kaç sonuç (varsayılan 40).'
          },
        },
        'required': ['path'],
      };

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    try {
      final path =
          AgentPathPolicy.instance.resolve(args['path'] as String? ?? '');
      final root = Directory(path);
      if (!root.existsSync()) return ToolResult.error('Klasör yok: $path');

      final nameQuery = (args['name_contains'] as String?)?.toLowerCase() ?? '';
      final textQuery = (args['text_contains'] as String?)?.toLowerCase() ?? '';
      if (nameQuery.isEmpty && textQuery.isEmpty) {
        return ToolResult.error(
            'name_contains veya text_contains vermeliysen.');
      }
      final limit = ((args['limit'] as num?)?.toInt() ?? 40).clamp(1, 500);

      final results = <String>[];
      var scanned = 0;
      await for (final entity
          in root.list(recursive: true, followLinks: false)) {
        if (results.length >= limit) break;
        if (entity is! File) continue;
        if (entity.lengthSync() > 2 * 1024 * 1024) continue;
        scanned++;
        final lowerPath = entity.path.toLowerCase();
        if (nameQuery.isNotEmpty && !lowerPath.contains(nameQuery)) continue;
        if (textQuery.isNotEmpty) {
          String content;
          try {
            content = await entity.readAsString();
          } catch (_) {
            continue; // ikili dosya
          }
          final index = content.toLowerCase().indexOf(textQuery);
          if (index < 0) continue;
          final line = content.substring(0, index).split('\n').length;
          final preview = content
              .substring(index, (index + 90).clamp(0, content.length))
              .split('\n')
              .first
              .trim();
          results.add('${entity.path}:$line  $preview');
        } else {
          results.add(entity.path);
        }
      }
      if (results.isEmpty) {
        return ToolResult('Sonuç yok ($scanned dosya tarandı).');
      }
      return ToolResult(results.join('\n'));
    } on PathPolicyException catch (error) {
      return ToolResult.error(error.message);
    } catch (error) {
      return ToolResult.error('Arama hatası: $error');
    }
  }
}
