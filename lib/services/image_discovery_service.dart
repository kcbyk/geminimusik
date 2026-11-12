import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'music_catalog_service.dart';
import 'web_search_service.dart';

/// Keşfedilmiş tek bir görsel.
class DiscoveredImage {
  final String url;

  /// Küçük/önizleme adresi (varsa). Kolajda bunun yerine [url] kullanılır.
  final String? thumbnailUrl;
  final String? title;
  final String source;
  final String? sourceUrl;

  const DiscoveredImage({
    required this.url,
    this.thumbnailUrl,
    this.title,
    this.source = '',
    this.sourceUrl,
  });

  /// Sohbet arayüzünün galeri/SlideImage formatı.
  Map<String, dynamic> toGalleryJson() => {
        'url': url,
        'small': thumbnailUrl ?? url,
        'title': title ?? '',
        'source': source,
        if (sourceUrl != null) 'page': sourceUrl,
      };
}

/// Kullanıcı "görsel/fotoğraf göster" dediğinde gerçek görselleri bulur.
///
/// Sıra: katalog kapağı (müzik) → Wikipedia (kişi/sanatçı) → Openverse
/// (genel) → mevcut arka uç (Pinterest + sayfa OG görseli).
/// Böylece tek bir kaynak çökse bile sonuç boş kalmıyor.
class ImageDiscoveryService {
  static final ImageDiscoveryService instance = ImageDiscoveryService._();
  ImageDiscoveryService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 14),
      validateStatus: (_) => true,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'GeminiMusik/1.0 (Flutter; +https://github.com/kcbyk/geminimusik)',
      },
    ),
  );

  final Map<String, List<DiscoveredImage>> _cache = {};

  /// [query] için görseller bulur. Sonuç her durumda (hata olsa bile) liste.
  ///
  /// Kaynaklar paralel çalışır: Wikipedia, Wikimedia Commons ve Pinterest
  /// (arka uç). Pinterest oyun/dizi/film karakterleri için en isabetli kaynak
  /// olduğundan sıralamada öne alınır.
  Future<List<DiscoveredImage>> discover(
    String query, {
    int limit = 6,
    bool musicFirst = false,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];

    final cacheKey = '${clean.toLowerCase()}|$musicFirst|$limit';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final collected = <DiscoveredImage>[];
    void addAll(Iterable<DiscoveredImage> images) {
      for (final image in images) {
        if (collected.length >= limit) return;
        if (!isUsableImageUrl(image.url)) continue;
        if (collected.any((existing) => existing.url == image.url)) continue;
        collected.add(image);
      }
    }

    final sources = await Future.wait([
      _wikipedia(clean, timeout: timeout),
      _pinterest(clean, timeout: timeout),
      _commons(clean, timeout: timeout),
      if (musicFirst) _albumCovers(clean),
    ]);

    // Sıra: müzik kapağı → Wikipedia → Pinterest → Commons.
    if (musicFirst) addAll(sources[3]);
    addAll(sources[0]);
    addAll(sources[1]);
    addAll(sources[2]);

    // Hiç sonuç yoksa Openverse (açık lisanslı genel görseller) — yavaş
    // olduğu için yalnızca zorunlu durumda çağrılır.
    if (collected.isEmpty) {
      addAll(await _openverse(clean));
    }

    // Hâlâ boşsa eski yol (sayfa meta görselleri + Pinterest tekrar).
    if (collected.isEmpty) {
      addAll(await _backendImages(clean));
    }

    // Son çare: sorguyu kelimelere bölüp tekrar dene (uzun sorgularda
    // "deki karakterlerin görselleri" gibi fazlalıklar sonucu boşaltabiliyor).
    if (collected.isEmpty && clean.split(RegExp(r'\s+')).length > 2) {
      final simplified = _simplifyQuery(clean);
      if (simplified != null && simplified.toLowerCase() != clean.toLowerCase()) {
        addAll(await _pinterest(simplified, timeout: timeout));
        if (collected.isEmpty) addAll(await _wikipedia(simplified, timeout: timeout));
      }
    }

    final result = collected.take(limit).toList(growable: false);
    _cache[cacheKey] = result;
    return result;
  }

  /// Tek bir görsel adresi (kart/başlık görselleri için hızlı yol).
  ///
  /// Yalnızca en hızlı iki kaynağı (Pinterest + Wikipedia) paralel dener;
  /// yetmezse tam zincire düşer.
  Future<String?> discoverOne(
    String query, {
    Duration timeout = const Duration(seconds: 9),
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return null;

    final cacheKey = 'one:${clean.toLowerCase()}';
    final cached = _cache[cacheKey];
    if (cached != null) return cached.isEmpty ? null : cached.first.url;

    final results = await Future.wait([
      _pinterest(clean, timeout: timeout),
      _wikipedia(clean, timeout: timeout),
    ]);
    for (final list in results) {
      for (final image in list) {
        if (!isUsableImageUrl(image.url)) continue;
        _cache[cacheKey] = <DiscoveredImage>[image];
        return image.url;
      }
    }

    final images = await discover(clean, limit: 1, timeout: timeout);
    _cache[cacheKey] = images;
    return images.isEmpty ? null : images.first.url;
  }

  /// Uzun sorgudan çekirdek varlığı çıkarır: "X deki karakterlerin görselleri"
  /// → "X".
  static String? simplifyQuery(String query) => _simplifyQuery(query);

  static String? _simplifyQuery(String query) {
    var value = query;
    const noise = [
      'görselleri', 'görsel', 'fotoğrafları', 'fotoğraf', 'resimleri', 'resim',
      'karakterleri', 'karakterlerin', 'karakter', 'oyunundaki', 'oyunun',
      'dizisindeki', 'filmindeki', 'deki', 'daki', 'teki', 'taki', 'hakkında',
      'kimdir', 'kapak', 'kapağı',
    ];
    for (final word in noise) {
      value = value.replaceAll(
        RegExp(r'\b' + RegExp.escape(word) + r'\b', caseSensitive: false),
        ' ',
      );
    }
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value.length >= 2 ? value : null;
  }

  /// Arka uç Pinterest araması (oyun/dizi karakterleri için en isabetli).
  Future<List<DiscoveredImage>> _pinterest(
    String query, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final previews = await WebSearchService.instance
          .searchPinterestImages(query, limit: 8, timeout: timeout);
      return [
        for (final preview in previews)
          if (preview.imageUrl.isNotEmpty)
            DiscoveredImage(
              url: preview.imageUrl,
              thumbnailUrl:
                  preview.thumbnailUrl.isEmpty ? null : preview.thumbnailUrl,
              title: preview.title.isEmpty ? null : preview.title,
              source: preview.sourceName.isEmpty
                  ? 'Pinterest'
                  : preview.sourceName,
              sourceUrl: preview.sourceUrl.isEmpty ? null : preview.sourceUrl,
            ),
      ];
    } catch (e) {
      debugPrint('Pinterest görselleri alınamadı: $e');
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Kaynaklar
  // ---------------------------------------------------------------------------

  Future<List<DiscoveredImage>> _albumCovers(String query) async {
    try {
      var albums = await MusicCatalogService.instance.searchAlbums(query, limit: 6);
      // "Albüm Adı Sanatçı" gibi birleşik sorgularda tek sonuç gelebiliyor;
      // parça parça da deneyip koleksiyonu genişletiyoruz.
      if (albums.length < 3) {
        final words = query.trim().split(RegExp(r'\s+'));
        if (words.length > 1) {
          final extra = <String>{
            words.last,
            words.first,
            words.take(words.length - 1).join(' '),
            words.skip(1).join(' '),
          }..removeWhere((word) => word.trim().length < 2);
          for (final term in extra) {
            final found = await MusicCatalogService.instance
                .searchAlbums(term, limit: 4);
            for (final album in found) {
              if (albums.every((existing) => existing.key != album.key)) {
                albums = [...albums, album];
              }
            }
            if (albums.length >= 6) break;
          }
        }
      }
      return [
        for (final album in albums)
          if (album.coverUrl != null)
            DiscoveredImage(
              url: album.coverUrl as String,
              title: <String?>[album.artist, album.title]
                  .whereType<String>()
                  .where((part) => part.trim().isNotEmpty)
                  .join(' · '),
              source: album.source == 'deezer'
                  ? 'Deezer albüm kapağı'
                  : 'Apple Music',
              sourceUrl: album.source == 'deezer'
                  ? 'https://www.deezer.com/album/${album.sourceId}'
                  : (album.collectionId == null
                      ? null
                      : 'https://music.apple.com/album/${album.collectionId}'),
            ),
      ];
    } catch (e) {
      debugPrint('Albüm kapağı araması başarısız: $e');
      return const [];
    }
  }

  Future<List<DiscoveredImage>> _wikipedia(
    String query, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    for (final lang in const ['tr', 'en']) {
      try {
        final response = await _dio.get(
          'https://$lang.wikipedia.org/w/api.php',
          options: Options(
            receiveTimeout: timeout,
            sendTimeout: timeout,
          ),
          queryParameters: {
            'action': 'query',
            'format': 'json',
            'generator': 'search',
            'gsrsearch': query,
            'gsrlimit': 4,
            'prop': 'pageimages',
            'piprop': 'original|thumbnail',
            'pithumbsize': 1200,
            'pilimit': 10,
          },
        );
        if (response.statusCode != 200) continue;
        final images = parseWikipedia(_decode(response.data))
            .where((image) => _isRelevant(image.title, query))
            .toList();
        if (images.isNotEmpty) return images;
      } catch (e) {
        debugPrint('Wikipedia görsel araması başarısız ($lang): $e');
      }
    }
    return const [];
  }

  /// Wikimedia Commons'ta dosya adı araması.
  Future<List<DiscoveredImage>> _commons(
    String query, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final response = await _dio.get(
        'https://commons.wikimedia.org/w/api.php',
        options: Options(
          receiveTimeout: timeout,
          sendTimeout: timeout,
        ),
        queryParameters: {
          'action': 'query',
          'format': 'json',
          'generator': 'search',
          'gsrsearch': 'filetype:bitmap $query',
          'gsrnamespace': 6,
          'gsrlimit': 5,
          'prop': 'imageinfo',
          'iiprop': 'url',
          'iiurlwidth': 1000,
        },
      );
      if (response.statusCode != 200) return const [];
      final images = parseCommons(_decode(response.data))
          .where((image) => _isRelevant(image.title, query))
          .toList();
      // Adı doğrudan sorguyla başlayan görseller öne alınır.
      final wanted = _normalize(query);
      images.sort((a, b) {
        final aStart = _normalize(a.title ?? '').startsWith(wanted) ? 0 : 1;
        final bStart = _normalize(b.title ?? '').startsWith(wanted) ? 0 : 1;
        return aStart.compareTo(bStart);
      });
      return images;
    } catch (e) {
      debugPrint('Commons araması başarısız: $e');
      return const [];
    }
  }

  Future<List<DiscoveredImage>> _openverse(String query) async {
    try {
      final response = await _dio.get(
        'https://api.openverse.org/v1/images/',
        queryParameters: {
          'q': query,
          'page_size': 6,
          'mature': 'false',
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      if (response.statusCode != 200) return const [];
      return parseOpenverse(_decode(response.data))
          .where((image) => _isRelevant(image.title, query))
          .toList();
    } catch (e) {
      debugPrint('Openverse araması başarısız: $e');
      return const [];
    }
  }

  Future<List<DiscoveredImage>> _backendImages(String query) async {
    final images = <DiscoveredImage>[];

    List<DiscoveredImage> convert(List<WebImagePreview> previews) => [
          for (final preview in previews)
            if (preview.imageUrl.isNotEmpty)
              DiscoveredImage(
                url: preview.imageUrl,
                thumbnailUrl: preview.thumbnailUrl.isEmpty
                    ? null
                    : preview.thumbnailUrl,
                title: preview.title.isEmpty ? null : preview.title,
                source: preview.sourceName.isEmpty
                    ? 'Web'
                    : preview.sourceName,
                sourceUrl: preview.sourceUrl.isEmpty ? null : preview.sourceUrl,
              ),
        ];

    // İki arka uç isteğini paralel çalıştır; biri boş dönerse diğeri kalsın.
    final results = await Future.wait([
      WebSearchService.instance
          .searchPinterestImages(query)
          .catchError((Object e) {
        debugPrint('Pinterest görselleri alınamadı: $e');
        return <WebImagePreview>[];
      }),
      WebSearchService.instance
          .searchImagePreviews(query)
          .catchError((Object e) {
        debugPrint('Sayfa görselleri alınamadı: $e');
        return <WebImagePreview>[];
      }),
    ]);
    for (final previews in results) {
      images.addAll(convert(previews));
    }
    return images;
  }

  // ---------------------------------------------------------------------------
  // Yardımcılar
  // ---------------------------------------------------------------------------

  /// Yanıt JSON metni olarak geldiyse çözer.
  static dynamic _decode(dynamic data) {
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    return data;
  }

  /// Görsel başlığı sorguyla gerçekten ilgili mi?
  ///
  /// "Wegh" aramasında "Wall Street" gibi alakasız sayfaları eler.
  static bool _isRelevant(String? title, String query) {
    if (title == null || title.trim().isEmpty) return true;
    final wantedWords = _normalize(query)
        .split(' ')
        .where((word) => word.length > 1)
        .toList();
    if (wantedWords.isEmpty) return true;
    final imageTitle = _normalize(title);
    return wantedWords.every(imageTitle.contains);
  }

  static String _normalize(String value) {
    const map = {
      'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u',
      'â': 'a', 'î': 'i', 'û': 'u',
    };
    var out = value.toLowerCase();
    map.forEach((key, replacement) => out = out.replaceAll(key, replacement));
    return out
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ---------------------------------------------------------------------------
  // Ayrıştırıcılar
  // ---------------------------------------------------------------------------

  /// `prop=pageimages` yanıtı → görseller.
  static List<DiscoveredImage> parseWikipedia(dynamic data) {
    if (data is! Map) return const [];
    final query = data['query'];
    if (query is! Map) return const [];
    final pages = query['pages'];
    if (pages is! Map) return const [];

    final images = <DiscoveredImage>[];
    for (final page in pages.values) {
      if (page is! Map) continue;
      final title = (page['title'] ?? '').toString();
      final original = page['original'];
      final thumbnail = page['thumbnail'];
      String? url;
      String? thumbUrl;
      if (original is Map && original['source'] is String) {
        url = original['source'] as String;
      }
      if (thumbnail is Map && thumbnail['source'] is String) {
        thumbUrl = thumbnail['source'] as String;
      }
      final chosen = url ?? thumbUrl;
      if (chosen == null || chosen.isEmpty) continue;
      images.add(
        DiscoveredImage(
          url: chosen,
          thumbnailUrl: thumbUrl,
          title: title,
          source: 'Wikipedia',
          sourceUrl: title.isEmpty
              ? null
              : 'https://tr.wikipedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}',
        ),
      );
    }
    return images;
  }

  /// `generator=search` + `prop=imageinfo` yanıtı → görseller.
  static List<DiscoveredImage> parseCommons(dynamic data) {
    if (data is! Map) return const [];
    final query = data['query'];
    if (query is! Map) return const [];
    final pages = query['pages'];
    if (pages is! Map) return const [];

    final images = <DiscoveredImage>[];
    for (final page in pages.values) {
      if (page is! Map) continue;
      final info = page['imageinfo'];
      if (info is! List || info.isEmpty) continue;
      final first = info.first;
      if (first is! Map) continue;
      final url = (first['url'] ?? '').toString();
      final thumb = (first['thumburl'] ?? '').toString();
      final chosen = url.isNotEmpty ? url : thumb;
      if (chosen.isEmpty) continue;

      var title = (page['title'] ?? '').toString();
      if (title.startsWith('File:')) title = title.substring(5);
      title = title.replaceAll(RegExp(r'\.(jpe?g|png|gif|webp)$',
              caseSensitive: false), '');

      images.add(
        DiscoveredImage(
          url: chosen,
          thumbnailUrl: thumb.isEmpty ? null : thumb,
          title: title,
          source: 'Wikimedia Commons',
          sourceUrl: (first['descriptionurl'] ?? '').toString().isEmpty
              ? null
              : (first['descriptionurl'] as String),
        ),
      );
    }
    return images;
  }

  static List<DiscoveredImage> parseOpenverse(dynamic data) {
    if (data is! Map) return const [];
    final results = data['results'];
    if (results is! List) return const [];

    final images = <DiscoveredImage>[];
    for (final item in results) {
      if (item is! Map) continue;
      final url = (item['url'] ?? '').toString();
      if (url.isEmpty) continue;
      final title = (item['title'] ?? '').toString().trim();
      final creator = (item['creator'] ?? '').toString().trim();
      images.add(
        DiscoveredImage(
          url: url,
          thumbnailUrl: (item['thumbnail'] ?? '').toString().isEmpty
              ? null
              : (item['thumbnail'] as String),
          title: title.isEmpty ? (creator.isEmpty ? null : creator) : title,
          source: (item['source'] ?? 'Openverse').toString(),
          sourceUrl: (item['foreign_landing_url'] ?? '').toString().isEmpty
              ? null
              : (item['foreign_landing_url'] as String),
        ),
      );
    }
    return images;
  }

  /// İkon/logo/svg gibi sohbet kolajına uygun olmayan adresleri eler.
  static bool isUsableImageUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.scheme != 'https') return false;
    final lower = url.toLowerCase();
    if (lower.endsWith('.svg')) return false;
    const blocked = [
      'logo',
      'favicon',
      'sprite',
      'icon-',
      'placeholder',
      '1x1',
      'spacer',
      'pixel.gif',
    ];
    for (final needle in blocked) {
      if (lower.contains(needle)) return false;
    }
    return true;
  }
}
