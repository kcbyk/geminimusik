/// Markdown gövdesine görsel ekleme yardımcıları.
///
/// Sohbet yanıtındaki görselleri ChatGPT tarzı kolaj olarak ilk paragrafın
/// hemen altına yerleştirir; kod bloklarının içine dokunmaz.
library;

/// [urls] görsellerini [content] içine ekler.
///
/// * Yanıtta zaten 2+ görsel varsa hiçbir şey eklenmez.
/// * 1 görsel varsa tek görsel eklenir (toplam 2).
/// * Hiç yoksa en fazla 3 görsel eklenir.
String insertImagesIntoMarkdown(String content, List<String> urls) {
  final images = urls
      .map((url) => url.trim())
      .where((url) => url.startsWith('https://') || url.startsWith('http://'))
      .toList();
  if (images.isEmpty) return content;

  final existing =
      RegExp(r'!\[[^\]]*\]\([^)]+\)').allMatches(content).length;
  if (existing >= 2) return content;

  final block = images
      .take(existing == 0 ? 3 : 1)
      .map((url) => '![görsel]($url)')
      .join('\n');

  final insertAt = firstParagraphBoundary(content);
  if (insertAt == null) return '${content.trim()}\n\n$block';
  final head = content.substring(0, insertAt).trimRight();
  final tail = content.substring(insertAt).trimLeft();
  if (head.isEmpty) return '$block\n\n$tail';
  return '$head\n\n$block\n\n$tail';
}

/// Kod bloğu dışındaki ilk paragraf sonunun konumu (yoksa `null`).
///
/// Başlık satırının hemen ardına görsel yığmamak için en az 60 karakter
/// metin geçmesini bekler.
int? firstParagraphBoundary(String content) {
  var inFence = false;
  var scanned = 0;
  for (final line in content.split('\n')) {
    final lineStart = scanned;
    scanned += line.length + 1;
    if (line.trimLeft().startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    if (line.trim().isEmpty && lineStart > 60) return lineStart;
  }
  return null;
}
