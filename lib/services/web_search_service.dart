import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

class WebSearchResult {
  final String title;
  final String url;
  final String snippet;
  final String? pageText;

  WebSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
    this.pageText,
  });
}

class WebImagePreview {
  final String thumbnailUrl;
  final String imageUrl;
  final String title;
  final String sourceUrl;
  final String sourceName;
  final String? photographer;
  final int? width;
  final int? height;
  const WebImagePreview(
      {required this.thumbnailUrl,
      required this.imageUrl,
      required this.title,
      required this.sourceUrl,
      required this.sourceName,
      this.photographer,
      this.width,
      this.height});
  Map<String, dynamic> toGalleryJson() => {
        'thumbnail_url': thumbnailUrl,
        'image_url': imageUrl,
        'title': title,
        'source_url': sourceUrl,
        'source_name': sourceName,
        if (photographer != null) 'photographer': photographer,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      };
}

class WebSearchService {
  static final WebSearchService instance = WebSearchService._();
  WebSearchService._();

  static const String _baseUrl = 'https://mp3-apisi.onrender.com';
  static const String _apiKey = 'sk-2b70a1771b2d8f8528f8810c';
  // Pinterest görsel araması için API sağlayıcısının uygulama anahtarı.
  static const String _pinterestApiKey = 'sk-5cd9869e8aa51831e7f5c696';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 45),
      receiveTimeout: const Duration(seconds: 45),
    ),
  );

  bool _isWarmingUp = false;
  final Map<String, List<WebImagePreview>> _imagePreviewCache = {};

  /// Render backend'i uyandırmak için arka planda hafif bir ping atar
  void warmup() async {
    if (_isWarmingUp) return;
    _isWarmingUp = true;
    try {
      await _dio.get(
        '/api/v1/web',
        queryParameters: {
          'q': 'ping',
          'limit': 1,
          'key': _apiKey,
        },
      );
    } catch (_) {}
  }

  /// Web araması yapar. limit=5 sonuç çeker (Google AI Modu gibi çoklu kaynak listesi için).
  Future<List<WebSearchResult>> search(
    String query, {
    int limit = 5,
    bool includeDetail = false,
  }) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _dio.get(
          '/api/v1/web',
          queryParameters: {
            'q': query,
            'limit': limit,
            if (includeDetail) 'detay': 1,
            'key': _apiKey,
          },
        );

        if (response.statusCode == 200 && response.data != null) {
          final data = response.data;
          if (data is Map<String, dynamic> && data['ok'] == true) {
            final list = data['sonuclar'] as List?;
            if (list != null) {
              return list.map((item) {
                final m = item as Map<String, dynamic>;
                return WebSearchResult(
                  title: m['baslik']?.toString() ?? '',
                  url: m['url']?.toString() ?? '',
                  snippet: m['ozet']?.toString() ?? '',
                  pageText: m['metin']?.toString(),
                );
              }).toList();
            }
          }
        }
        return [];
      } catch (e) {
        debugPrint('Web arama hatası (deneme ${attempt + 1}): $e');
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    return [];
  }

  /// Mevcut arama sağlayıcısından dönen sayfa metnindeki gerçek Open Graph /
  /// Twitter Card görsellerini kullanır. Sağlayıcı HTML ya da görsel URL
  /// vermiyorsa boş döner; asla tahmini bir resim URL'si üretmez.
  Future<List<WebImagePreview>> searchImagePreviews(String query,
      {int limit = 10}) async {
    final cacheKey = query.trim().toLowerCase();
    if (_imagePreviewCache.containsKey(cacheKey)) {
      return _imagePreviewCache[cacheKey]!;
    }
    final results =
        await search(query, limit: limit.clamp(1, 12), includeDetail: true);
    final previews = <WebImagePreview>[];
    for (final result in results) {
      final imageUrl = _extractPageImage(result.pageText);
      if (imageUrl == null) continue;
      final uri = Uri.tryParse(result.url);
      if (uri == null || uri.scheme != 'https') continue;
      previews.add(WebImagePreview(
        thumbnailUrl: imageUrl,
        imageUrl: imageUrl,
        title: result.title,
        sourceUrl: result.url,
        sourceName: uri.host.replaceFirst(RegExp(r'^www\\.'), ''),
      ));
    }
    _imagePreviewCache[cacheKey] = previews;
    return previews;
  }

  /// Mevcut backend'in Pinterest arama çıktısını normal galeri verisine çevirir.
  /// Sadece HTTPS görsel ve kaynak bağlantıları kabul edilir.
  Future<List<WebImagePreview>> searchPinterestImages(String query,
      {int limit = 10}) async {
    final cacheKey = 'pinterest:${query.trim().toLowerCase()}';
    if (_imagePreviewCache.containsKey(cacheKey)) {
      return _imagePreviewCache[cacheKey]!;
    }
    try {
      final response = await _dio.get('/api/v1/pinterest', queryParameters: {
        'q': query,
        'limit': limit.clamp(1, 12),
        'key': _pinterestApiKey,
      });
      final data = response.data;
      final rawImages = data is Map ? data['gorseller'] : null;
      if (rawImages is! List) return const [];
      final previews = rawImages
          .whereType<Map>()
          .map((item) {
            String secure(dynamic value) {
              final valueString = value?.toString() ?? '';
              return Uri.tryParse(valueString)?.scheme == 'https'
                  ? valueString
                  : '';
            }

            return WebImagePreview(
              thumbnailUrl: secure(item['kucuk']),
              imageUrl: secure(item['gorsel']),
              title: (item['baslik'] ?? item['ozet'] ?? query).toString(),
              sourceUrl: secure(item['site']),
              sourceName: (item['site_domain'] ?? item['kaynak'] ?? 'Pinterest')
                  .toString(),
              photographer: item['fotografci']?.toString(),
              width: (item['genislik'] as num?)?.toInt(),
              height: (item['yukseklik'] as num?)?.toInt(),
            );
          })
          .where((image) =>
              image.thumbnailUrl.isNotEmpty &&
              image.imageUrl.isNotEmpty &&
              image.sourceUrl.isNotEmpty)
          .toList();
      _imagePreviewCache[cacheKey] = previews;
      return previews;
    } catch (error) {
      debugPrint('Pinterest görsel arama hatası: $error');
      return const [];
    }
  }

  String? _extractPageImage(String? content) {
    if (content == null || content.isEmpty) return null;
    final patterns = [
      RegExp(
          r'''<meta[^>]+(?:property|name)=["'](?:og:image|twitter:image)["'][^>]+content=["'](https://[^"']+)["']''',
          caseSensitive: false),
      RegExp(
          r'''<meta[^>]+content=["'](https://[^"']+)["'][^>]+(?:property|name)=["'](?:og:image|twitter:image)["']''',
          caseSensitive: false),
      RegExp(r'''https://[^\s"']+\.(?:jpg|jpeg|png|webp)(?:\?[^\s"']*)?''',
          caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(content);
      final url = match?.group(1) ?? match?.group(0);
      if (url != null && Uri.tryParse(url)?.scheme == 'https') return url;
    }
    return null;
  }

  /// Verilen URL içeriğini temiz metin olarak okur
  Future<String?> readPage(String url, {int karakter = 3000}) async {
    try {
      final response = await _dio.get(
        '/api/v1/oku',
        queryParameters: {
          'url': url,
          'karakter': karakter,
          'key': _apiKey,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data is Map<String, dynamic> && data['ok'] == true) {
          return data['metin']?.toString();
        }
      }
      return null;
    } catch (e) {
      debugPrint('Web sayfa okuma hatası: $e');
      return null;
    }
  }

  /// Gemini için web sonuçlarını prompt context formatına çevirir
  String formatForPrompt(List<WebSearchResult> results, String query) {
    if (results.isEmpty) return '';
    final sb = StringBuffer();
    sb.writeln('[WEB_ARAMA_SONUCLARI]');
    sb.writeln('=== GÜNCEL İNTERNET ARAMA VERİLERİ (Sorgu: "$query") ===');
    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      sb.writeln('\n[KAYNAK ${i + 1}]: ${r.title}');
      sb.writeln('URL: ${r.url}');
      if (r.pageText != null && r.pageText!.isNotEmpty) {
        final clean = r.pageText!.length > 3500
            ? '${r.pageText!.substring(0, 3500)}...'
            : r.pageText!;
        sb.writeln('İçerik/Metin:\n$clean');
      } else if (r.snippet.isNotEmpty) {
        sb.writeln('Özet: ${r.snippet}');
      }
    }
    sb.writeln('\n=== İNTERNET BİLGİLERİNİN SONU ===');
    sb.writeln(
        'Talimat: Yukarıdaki güncel web verilerini kullanarak kullanıcının sorusuna doğrudan, en güncel ve net yanıtı ver. Özellikle döviz ve altın gibi finansal verilerde sayfadaki "Önceki Kapanış", "Alış", "Satış" ve "Anlık Piyasa" değerlerini birbirine karıştırma; gerekiyorsa bunları açıkça adlandırarak (Örn: Anlık: 56,41 TL, Önceki Kapanış: 56,36 TL) tutarlı şekilde açıkla. Asla tekrar [ACTION:SEARCH] üretme!');
    sb.writeln('[/WEB_ARAMA_SONUCLARI]');
    return sb.toString();
  }
}
