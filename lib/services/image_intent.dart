/// Kullanıcının mesajından "görsel isteği" çıkarımı.
///
/// Sohbet akışı bu modülü kullanır; böylece Türkçe kalıplar tek yerde
/// toplanır ve test edilebilir olur.
library;

/// Görsel isteği kalıbında geçen isimler (uzun olanlar önce denenir).
const List<String> _visualNouns = [
  'görsel',
  'görseli',
  'görselini',
  'görseller',
  'görselleri',
  'görsellerini',
  'foto',
  'fotoğraf',
  'fotoğrafı',
  'fotoğrafını',
  'fotoğraflar',
  'fotoğrafları',
  'fotoğraflarını',
  'resim',
  'resmi',
  'resmini',
  'resimler',
  'resimleri',
  'resimlerini',
  'kapak',
  'kapağı',
  'kapağını',
  'kapakları',
  'kapaklarını',
  'image',
  'images',
  'photo',
  'photos',
  'picture',
  'pictures',
  'artwork',
  'cover',
];

/// Sorgudan atılan dolgu sözcükleri.
final RegExp _filler =
    RegExp(r'\b(bana|lütfen|acil|bir|tane|adet|şimdi|hadi|acaba|peki)\b',
        caseSensitive: false);

/// İyelik/ilgi ekiyle gelen "albümünün", "şarkısının" gibi sözcükler.
final RegExp _trailingKindWord = RegExp(
  r'\s+(?:albüm|album|şarkı|parça|sanatçı|şarkıcı|grup|klip|müzik|'
  r'karakter|karakterler|karakterleri|karakterlerin|kişi|kişiler|kişilerin|'
  r'oyun|oyunu|oyunun|oyunundaki|dizi|dizisi|dizinin|dizisindeki|film|filmi|'
  r'filmin|filmindeki|kadro|kadrosu|kadrosunun)[a-zçğıöşü]*$',
  caseSensitive: false,
);

/// Kullanıcı mesajından görsel araması için varlık adı çıkarır.
///
/// Örnekler:
/// * "Wegh görsellerini göster" → `Wegh`
/// * "curcuna albümünün kapağını göster" → `curcuna`
/// * "görsel bul: kırmızı arabalar" → `kırmızı arabalar`
/// * "Tarkan kimdir" → `Tarkan`
/// * "nasıl yaparım" → `null`
///
/// [content] verilirse ve mesajda varlık adı yoksa yanıtın ilk başlığından
/// türetilmeye çalışılır ("… görsellerini göster" gibi kısa istekler için).
String? imageIntentQuery(String text, {String? content}) {
  final source = text.trim();
  if (source.isEmpty) return null;

  // 1) "görsel bul: X", "resim: X"
  final afterColon = RegExp(
    '(?:$_nounsPattern)s?\\s*(?:bul|ara|getir|göster)?\\s*[:\\-]\\s*(.+)\$',
    caseSensitive: false,
  ).firstMatch(source);
  if (afterColon != null) {
    final entity = cleanImageEntity(afterColon.group(1));
    if (entity != null) return entity;
  }

  // 2) "X görsellerini göster", "X'in fotoğrafları", "X albüm kapağı"
  final beforeNoun = RegExp(
    '^(.{2,70}?)\\s+(?:için\\s+|ait\\s+)?(?:bir\\s+)?(?:adet\\s+)?'
    '(?:$_nounsPattern)\\b',
    caseSensitive: false,
  ).firstMatch(source);
  if (beforeNoun != null) {
    final entity = cleanImageEntity(beforeNoun.group(1));
    if (entity != null) return entity;
  }

  // 3) "X kimdir / X kim / X nereli / X hakkında bilgi ver"
  final personMatch = RegExp(
    r'^(.+?)\s+(?:kimdir|kimdi|kim\b|nereli|hakkında(?:\s+bilgi\s+ver)?)',
    caseSensitive: false,
  ).firstMatch(source);
  if (personMatch != null) {
    final entity = cleanImageEntity(personMatch.group(1));
    if (entity != null && entity.split(RegExp(r'\s+')).length <= 6) {
      return entity;
    }
  }

  // 4) Yalnızca "görsel göster" dendiyse yanıtın başlığından türet.
  final onlyVisual = RegExp(
    '\\b(?:$_nounsPattern)\\b',
    caseSensitive: false,
  ).hasMatch(source);
  if (onlyVisual && content != null) {
    final heading =
        RegExp(r'^#{1,3}\s+(.+)$', multiLine: true).firstMatch(content);
    if (heading != null) return cleanImageEntity(heading.group(1));
    final firstLine = content.trim().split('\n').first;
    if (firstLine.length <= 60) return cleanImageEntity(firstLine);
  }
  return null;
}

/// Arama sorgusundan tırnak, dolgu sözcükleri ve iyelik ekleri temizler.
///
/// İsimleri bozmamak için ek kırpma yalnızca kesme işaretiyle ("Wegh'in") veya
/// ünlüyle biten gövdeye gelen tamlayan ekiyle ("curcunanın") yapılır.
String? cleanImageEntity(String? raw) {
  if (raw == null) return null;
  var value = raw
      .replaceAll(RegExp(r'["“”‘]'), '')
      .replaceAll(_filler, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // "Wegh'in" / "Wegh’in" → "Wegh" (yalnızca kısa iyelik ekleri kırpılır;
  // "Guns N' Roses" gibi adlar bozulmaz).
  value = value
      .replaceAll(
        RegExp(
          r"['’](?:nin|nın|nun|nün|in|ın|un|ün|si|sı|su|sü|ye|ya|den|dan|de|da|i|ı|u|ü)\b",
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  // "curcuna albümünün" / "Geri Ver şarkısının" → "curcuna" / "Geri Ver"
  var previous = '';
  while (previous != value) {
    previous = value;
    value = value.replaceAll(_trailingKindWord, '').trim();
  }

  // "the last of us part 2 deki karakterlerin" → "the last of us part 2"
  value = value.replaceAll(
    RegExp(r'\s+(?:deki|daki|teki|taki|ndeki|ndaki|ın|in)\b'),
    ' ',
  );

  // "curcunanın" → "curcuna" (gövde ünlüyle bitiyorsa)
  for (final suffix in const ['nın', 'nin', 'nun', 'nün']) {
    if (value.endsWith(suffix)) {
      final stem = value.substring(0, value.length - suffix.length);
      if (RegExp('[aeıioöuü]\$').hasMatch(stem)) value = stem;
      break;
    }
  }

  value = value
      .replaceAll(RegExp(r'^[\W_]+'), '')
      .replaceAll(RegExp(r'[\W_]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (value.length < 2) return null;
  if (RegExp('^(?:$_nounsPattern)\$', caseSensitive: false)
      .hasMatch(value)) {
    return null;
  }
  return value;
}

/// Sorgu müzikle ilgili mi (kapak aramasını öne almak için).
bool looksMusical(String text) => RegExp(
      r'(albüm|album|şarkı|parça|sanatçı|şarkıcı|müzik|music|single|cover|kapak|kapağ|klip)',
      caseSensitive: false,
    ).hasMatch(text);

/// Alternatiflerde uzun isimler önce denenir ("görsellerini" > "görsel").
String get _nounsPattern {
  final sorted = [..._visualNouns]
    ..sort((a, b) => b.length.compareTo(a.length));
  return sorted.join('|');
}
