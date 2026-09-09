enum VoiceActionType {
  play,
  pause,
  resume,
  next,
  stop,
  unknown,
}

class ParsedVoiceCommand {
  final VoiceActionType type;
  final String? songQuery;
  final String rawText;

  const ParsedVoiceCommand({
    required this.type,
    this.songQuery,
    required this.rawText,
  });

  @override
  String toString() => 'ParsedVoiceCommand(type: $type, songQuery: $songQuery, rawText: "$rawText")';
}

class VoiceCommandParser {
  /// Gelen sesli metni inceler ve komut tipini + parametreleri çıkarır
  static ParsedVoiceCommand parse(String input) {
    final clean = input.trim();
    if (clean.isEmpty) {
      return const ParsedVoiceCommand(type: VoiceActionType.unknown, rawText: '');
    }

    final lower = clean.toLowerCase();

    // 1. Duraklatma / Pause Komutları
    if (_matchesAny(lower, [
      'duraklat',
      'şarkıyı duraklat',
      'müziği duraklat',
      'durdur',
      'şarkıyı durdur',
      'müziği durdur',
      'beklet',
      'pause',
      'pause music',
    ])) {
      return ParsedVoiceCommand(type: VoiceActionType.pause, rawText: clean);
    }

    // 2. Devam Etme / Resume Komutları
    if (_matchesAny(lower, [
      'devam et',
      'çalmaya devam et',
      'sürdür',
      'müziğe devam',
      'resume',
      'continue',
    ])) {
      return ParsedVoiceCommand(type: VoiceActionType.resume, rawText: clean);
    }

    // 3. Sonraki Şarkı / Next Komutları
    if (_matchesAny(lower, [
      'sonraki şarkı',
      'sonraki',
      'diğer şarkı',
      'diğerine geç',
      'atla',
      'şarkıyı atla',
      'next',
      'next song',
      'skip',
    ])) {
      return ParsedVoiceCommand(type: VoiceActionType.next, rawText: clean);
    }

    // 4. Kapatma / Stop Komutları
    if (_matchesAny(lower, [
      'kapat',
      'müziği kapat',
      'şarkıyı kapat',
      'sonlandır',
      'stop',
      'stop music',
    ])) {
      return ParsedVoiceCommand(type: VoiceActionType.stop, rawText: clean);
    }

    // 5. Çalma Komutları: "X şarkısını çal", "X çal", "play X", "X aç"
    final playPatterns = [
      RegExp(r'^(?:lütfen\s+)?(.+?)\s+şarkısını\s+(?:çal|aç|oynat)$', caseSensitive: false),
      RegExp(r'^(?:lütfen\s+)?(.+?)\s+adlı\s+şarkıyı\s+(?:çal|aç|oynat)$', caseSensitive: false),
      RegExp(r'^(?:lütfen\s+)?(.+?)\s+(?:şarkısını|parçasını)\s+dinlet$', caseSensitive: false),
      RegExp(r'^(?:lütfen\s+)?(.+?)\s+(?:çal|aç|oynat)$', caseSensitive: false),
      RegExp(r'^(?:bana\s+)?(.+?)\s+çal(?:abilir\s+misin)?$', caseSensitive: false),
      RegExp(r'^play\s+(.+)$', caseSensitive: false),
      RegExp(r'^listen\s+to\s+(.+)$', caseSensitive: false),
    ];

    for (final pattern in playPatterns) {
      final match = pattern.firstMatch(lower);
      if (match != null && match.groupCount >= 1) {
        final query = match.group(1)?.trim();
        if (query != null && query.isNotEmpty && query.length > 1) {
          // İstenmeyen kelimeleri temizle (örn: 'merhaba', 'hey', 'lütfen')
          final cleanedQuery = _cleanQueryPrefixes(query);
          if (cleanedQuery.isNotEmpty) {
            return ParsedVoiceCommand(
              type: VoiceActionType.play,
              songQuery: cleanedQuery,
              rawText: clean,
            );
          }
        }
      }
    }

    // Eğer direkt bir eylem kelimesi içermiyorsa ancak 2 kelimeden fazlaysa veya açık bir isimse
    // Örn: "Duman Haberin Yok Ölüyorum"
    if (lower.length > 2) {
      final cleanedQuery = _cleanQueryPrefixes(clean);
      return ParsedVoiceCommand(
        type: VoiceActionType.play,
        songQuery: cleanedQuery,
        rawText: clean,
      );
    }

    return ParsedVoiceCommand(type: VoiceActionType.unknown, rawText: clean);
  }

  static bool _matchesAny(String text, List<String> triggers) {
    for (final t in triggers) {
      if (text == t || text.endsWith(t) || text.startsWith(t)) {
        return true;
      }
    }
    return false;
  }

  static String _cleanQueryPrefixes(String q) {
    var result = q.trim();
    final prefixes = [
      'merhaba',
      'selam',
      'hey',
      'lütfen',
      'bana',
      'bize',
      'hemen',
      'hadi',
    ];
    for (final p in prefixes) {
      if (result.toLowerCase().startsWith('$p ')) {
        result = result.substring(p.length + 1).trim();
      }
    }
    return result;
  }
}
