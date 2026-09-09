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

class WebSearchService {
  static final WebSearchService instance = WebSearchService._();
  WebSearchService._();

  static const String _baseUrl = 'https://mp3-apisi.onrender.com';
  static const String _apiKey = 'sk-2b70a1771b2d8f8528f8810c';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 45),
      receiveTimeout: const Duration(seconds: 45),
    ),
  );

  bool _isWarmingUp = false;

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
    sb.writeln('Talimat: Yukarıdaki güncel web verilerini kullanarak kullanıcının sorusuna doğrudan, en güncel ve net yanıtı ver. Özellikle döviz ve altın gibi finansal verilerde sayfadaki "Önceki Kapanış", "Alış", "Satış" ve "Anlık Piyasa" değerlerini birbirine karıştırma; gerekiyorsa bunları açıkça adlandırarak (Örn: Anlık: 56,41 TL, Önceki Kapanış: 56,36 TL) tutarlı şekilde açıkla. Asla tekrar [ACTION:SEARCH] üretme!');
    sb.writeln('[/WEB_ARAMA_SONUCLARI]');
    return sb.toString();
  }
}
