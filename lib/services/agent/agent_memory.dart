import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ajana tur arası hafıza ekler.
///
/// İki katman var:
/// 1. **Konuşma günlüğü** — son görevlerin görev/sonuç çiftleri. Her yeni
///    görevde modele verilir, böylece "az önce ne yapmıştık" bilinir.
/// 2. **Kalıcı notlar** — `memory` aracıyla yazılan, silinmeyen gerçekler
///    (proje yapısı, kullanıcı tercihleri, cihaz bilgisi).
///
/// Çekirdek Flutter bilmesin diye depo soyutlandı: testler [InMemoryStore]
/// kullanır, uygulama [PrefsStore].
abstract class AgentMemoryStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class InMemoryStore implements AgentMemoryStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}

class PrefsStore implements AgentMemoryStore {
  const PrefsStore();

  @override
  Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }
}

class AgentTurnRecord {
  final DateTime time;
  final String task;
  final String answer;
  final List<String> toolsUsed;

  const AgentTurnRecord({
    required this.time,
    required this.task,
    required this.answer,
    this.toolsUsed = const [],
  });

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'task': task,
        'answer': answer,
        'tools': toolsUsed,
      };

  factory AgentTurnRecord.fromJson(Map<dynamic, dynamic> json) =>
      AgentTurnRecord(
        time: DateTime.tryParse(json['time']?.toString() ?? '') ??
            DateTime.now(),
        task: json['task']?.toString() ?? '',
        answer: json['answer']?.toString() ?? '',
        toolsUsed: (json['tools'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
}

class AgentMemory {
  AgentMemory({AgentMemoryStore? store, this.maxTurns = 25})
      : _store = store ?? const PrefsStore();

  static const String _historyKey = 'agent_history_v1';
  static const String _notesKey = 'agent_notes_v1';

  /// Modelin bağlamını doldurmamak için günlük metninin üst sınırı.
  static const int maxContextChars = 16000;

  /// Tek bir görev sonucu bu kadar karakterden uzunsa kısaltılır.
  static const int maxAnswerChars = 1200;

  final AgentMemoryStore _store;
  final int maxTurns;

  List<AgentTurnRecord> _turns = [];
  String _notes = '';
  bool _loaded = false;

  List<AgentTurnRecord> get turns => List.unmodifiable(_turns);
  String get notes => _notes;
  bool get hasNotes => _notes.trim().isNotEmpty;
  int get turnCount => _turns.length;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final rawHistory = await _store.read(_historyKey);
      if (rawHistory != null && rawHistory.isNotEmpty) {
        final decoded = jsonDecode(rawHistory);
        if (decoded is List) {
          _turns = decoded
              .whereType<Map>()
              .map(AgentTurnRecord.fromJson)
              .toList(growable: true);
        }
      }
      _notes = await _store.read(_notesKey) ?? '';
    } catch (error) {
      debugPrint('[AgentMemory] yüklenemedi: $error');
    }
    _loaded = true;
  }

  /// Görev bittiğinde çağrılır. Kalıcı olduğu için hata yutmayız.
  Future<void> rememberTurn({
    required String task,
    required String answer,
    List<String> toolsUsed = const [],
  }) async {
    await load();
    _turns.add(AgentTurnRecord(
      time: DateTime.now(),
      task: task,
      answer: _clip(answer, maxAnswerChars),
      toolsUsed: toolsUsed.toSet().toList(),
    ));
    if (_turns.length > maxTurns) {
      _turns = _turns.sublist(_turns.length - maxTurns);
    }
    await _persistHistory();
  }

  Future<void> _persistHistory() async {
    try {
      await _store.write(
        _historyKey,
        jsonEncode(_turns.map((t) => t.toJson()).toList()),
      );
    } catch (error) {
      debugPrint('[AgentMemory] geçmiş kaydedilemedi: $error');
    }
  }

  /// `memory` aracı bunu çağırır: kalıcı not ekler.
  Future<void> addNote(String text) async {
    await load();
    final line = text.trim();
    if (line.isEmpty) return;
    final stamp = DateTime.now().toIso8601String().substring(0, 16);
    _notes = _notes.isEmpty ? '- [$stamp] $line' : '$_notes\n- [$stamp] $line';
    await _store.write(_notesKey, _notes);
  }

  Future<void> clearNotes() async {
    _notes = '';
    await _store.write(_notesKey, '');
  }

  Future<void> clearHistory() async {
    _turns = [];
    await _store.write(_historyKey, '[]');
  }

  /// Yeni görevin başında modele verilecek bağlam bloğu.
  String buildContextBlock() {
    final buffer = StringBuffer();

    if (hasNotes) {
      buffer.writeln('[KALICI_HAFIZA_NOTLARIN]');
      buffer.writeln(_clip(_notes, 4000));
      buffer.writeln('[/KALICI_HAFIZA_NOTLARIN]');
      buffer.writeln();
    }

    if (_turns.isNotEmpty) {
      buffer.writeln('[ONCEKI_GOREVLER]');
      // En eski başta, en yeni sonda olsun; sınır aşılırsa eskileri düşür.
      final lines = <String>[];
      for (final turn in _turns) {
        final tools =
            turn.toolsUsed.isEmpty ? '' : ' (araçlar: ${turn.toolsUsed.join(', ')})';
        lines.add('- ${turn.time.toIso8601String().substring(0, 16)} '
            'GÖREV: ${_clip(turn.task, 300)}\n'
            '  SONUÇ: ${_clip(turn.answer, 600)}$tools');
      }
      var joined = lines.join('\n');
      if (joined.length > maxContextChars) {
        joined = '… (daha eski ${lines.length ~/ 3} görev kısaltıldı)\n'
            '${joined.substring(joined.length - maxContextChars)}';
      }
      buffer.writeln(joined);
      buffer.writeln('[/ONCEKI_GOREVLER]');
      buffer.writeln();
    }

    if (buffer.isEmpty) return '';
    buffer.writeln('Talimat: Yukarıdakiler senin kendi geçmişin. Kullanıcı '
        '"az önce", "deminki", "devam et", "o dosya" dediğinde buraya bak ve '
        'oradan devam et. Aynı işi tekrar yapma; yapılmışsa yapıldığını söyle.');
    return buffer.toString();
  }

  static String _clip(String value, int max) {
    final clean = value.trim();
    if (clean.length <= max) return clean;
    return '${clean.substring(0, max)}…';
  }
}
