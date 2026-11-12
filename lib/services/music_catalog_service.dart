import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Katalogdan gelen tek bir parça.
class CatalogTrack {
  final String title;
  final String? artist;
  final int? durationMs;

  /// Parçanın kendi kapağı (single'larda farklı olur). Albümlerde genelde
  /// albüm kapağıyla aynıdır.
  final String? artworkUrl;

  const CatalogTrack({
    required this.title,
    this.artist,
    this.durationMs,
    this.artworkUrl,
  });

  /// "2:58" biçiminde süre.
  String? get durationLabel {
    if (durationMs == null || durationMs! <= 0) return null;
    final totalSeconds = durationMs! ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        if (artist != null && artist!.isNotEmpty) 'artist': artist,
        if (durationLabel != null) 'duration': durationLabel,
        if (artworkUrl != null) 'artwork': artworkUrl,
      };
}

/// Albüm meta verisi + parça listesi.
class CatalogAlbum {
  final int? collectionId;
  final String title;
  final String? artist;
  final String? year;
  final String? coverUrl;
  final List<CatalogTrack> tracks;

  /// Katalog kaynağı: `deezer` veya `itunes`.
  final String source;

  /// Kaynağa özgü kimlik (Deezer albüm id'si metin olabilir).
  final String? sourceId;

  const CatalogAlbum({
    required this.title,
    this.collectionId,
    this.artist,
    this.year,
    this.coverUrl,
    this.tracks = const [],
    this.source = 'itunes',
    this.sourceId,
  });

  /// Aynı albümü işaret eden benzersiz anahtar.
  String get key => '$source:${sourceId ?? collectionId ?? title.toLowerCase()}';
}

/// Şarkı/albüm kapaklarını ve parça listelerini **API anahtarı gerektirmeyen**
/// iTunes Search API'sinden çeker.
///
/// Neden iTunes: model albüm kapağı veya parça süresi uydurmak zorunda kalmasın;
/// gerçek kapak URL'si (artworkUrl100 → 600x600), parça adları, sıraları ve
/// süreleri tek istekte geliyor. Türkçe içerik de katalogda mevcut.
class MusicCatalogService {
  static final MusicCatalogService instance = MusicCatalogService._();
  MusicCatalogService._();

  static const String _host = 'https://itunes.apple.com';
  static const String _deezerHost = 'https://api.deezer.com';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (_) => true,
      headers: const {'Accept': 'application/json'},
    ),
  );

  final Map<String, CatalogAlbum?> _albumCache = {};
  final Map<String, CatalogTrack?> _trackCache = {};

  // ---------------------------------------------------------------------------
  // Genel API
  // ---------------------------------------------------------------------------

  /// Başlık (+ varsa sanatçı) ile albümü bulur, parça listesini de getirir.
  ///
  /// Emin olamazsa `null` döner: yanlış albüm kapağı göstermektense kapağı boş
  /// bırakmak daha doğru.
  Future<CatalogAlbum?> findAlbum(String title, {String? artist}) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return null;

    final cacheKey = '${cleanTitle.toLowerCase()}|${(artist ?? '').toLowerCase()}';
    if (_albumCache.containsKey(cacheKey)) return _albumCache[cacheKey];

    final candidates = <CatalogAlbum>[];
    void merge(List<CatalogAlbum> albums) {
      for (final album in albums) {
        if (album.collectionId != null &&
            candidates.any((c) => c.collectionId == album.collectionId)) {
          continue;
        }
        candidates.add(album);
      }
    }

    // Deezer Türkçe kataloğu daha geniş; önce orada arıyoruz.
    merge(await _searchDeezerAlbums(
      artist != null && artist.trim().isNotEmpty
          ? '$artist $cleanTitle'
          : cleanTitle,
    ));
    merge(await _searchDeezerAlbums(cleanTitle));

    // iTunes: albüm adıyla ara (sanatçıyla birleştirmek iTunes'ta alakasız
    // sonuç verdiği için ayrı ayrı arıyoruz).
    if (candidates.length < 6) {
      merge(await _searchAlbumsRaw(cleanTitle, country: 'TR'));
    }
    if (candidates.length < 4 &&
        artist != null &&
        artist.trim().isNotEmpty) {
      merge(await _searchAlbumsRaw(artist.trim(), country: 'TR', limit: 25));
    }
    // Hiç sonuç yoksa ülke filtresiz dene.
    if (candidates.isEmpty) {
      merge(await _searchAlbumsRaw(cleanTitle, country: null));
      if (artist != null && artist.trim().isNotEmpty) {
        merge(await _searchAlbumsRaw(artist.trim(), country: null, limit: 25));
      }
    }

    final best = _bestAlbumMatch(candidates, cleanTitle, artist);
    if (best == null) {
      _albumCache[cacheKey] = null;
      return null;
    }

    // Parça listesini ayrıntılandır.
    var detailed = best;
    CatalogAlbum? withTracks;
    if (best.source == 'deezer' && best.sourceId != null) {
      withTracks = await deezerAlbum(best.sourceId!);
    } else if (best.collectionId != null) {
      withTracks = await lookupAlbum(best.collectionId!);
    }
    if (withTracks != null && withTracks.tracks.isNotEmpty) {
      detailed = CatalogAlbum(
        collectionId: best.collectionId,
        source: best.source,
        sourceId: best.sourceId ?? best.collectionId?.toString(),
        title: best.title,
        artist: best.artist,
        year: withTracks.year ?? best.year,
        coverUrl: withTracks.coverUrl ?? best.coverUrl,
        tracks: withTracks.tracks,
      );
    }

    _albumCache[cacheKey] = detailed;
    return detailed;
  }

  /// Aday albümler arasından en iyi eşleşmeyi seçer.
  ///
  /// Eşleşme güveni düşükse (albüm adı hiç benzemiyorsa) `null` döner.
  static CatalogAlbum? _bestAlbumMatch(
    List<CatalogAlbum> candidates,
    String title, [
    String? artist,
  ]) {
    final wantedTitle = _normalize(title);
    final wantedArtist = _normalize(artist ?? '');
    CatalogAlbum? best;
    var bestScore = 0;

    for (final album in candidates) {
      final name = _normalize(album.title);
      var score = 0;
      if (name == wantedTitle) {
        score += 12;
      } else if (_sameWords(name, wantedTitle)) {
        score += 9;
      } else if (name.contains(wantedTitle) || wantedTitle.contains(name)) {
        score += 6;
      } else if (_wordOverlap(name, wantedTitle) >= 0.6) {
        score += 4;
      }
      if (score == 0) continue; // albüm adı benzemiyorsa asla seçilmez

      if (wantedArtist.isNotEmpty) {
        final albumArtist = _normalize(album.artist ?? '');
        if (albumArtist == wantedArtist ||
            albumArtist.contains(wantedArtist) ||
            wantedArtist.contains(albumArtist)) {
          score += 5;
        }
      }
      if (album.coverUrl != null) score += 1;

      if (score > bestScore) {
        bestScore = score;
        best = album;
      }
    }
    return best;
  }

  /// Sözcük kümesi aynı mı ("Curcuna (Deluxe)" ≈ "curcuna deluxe").
  static bool _sameWords(String a, String b) {
    final setA = a.split(' ').where((w) => w.isNotEmpty).toSet();
    final setB = b.split(' ').where((w) => w.isNotEmpty).toSet();
    return setA.isNotEmpty && setA.length == setB.length && setA.containsAll(setB);
  }

  /// İki başlık arasındaki sözcük örtüşme oranı.
  static double _wordOverlap(String a, String b) {
    final setA = a.split(' ').where((w) => w.length > 1).toSet();
    final setB = b.split(' ').where((w) => w.length > 1).toSet();
    if (setA.isEmpty || setB.isEmpty) return 0;
    final common = setA.intersection(setB).length;
    return common / (setA.length < setB.length ? setA.length : setB.length);
  }

  Future<List<CatalogAlbum>> _searchAlbumsRaw(String term, {
    String? country,
    int limit = 10,
  }) async {
    final data = await _get('/search', {
      'term': term,
      'entity': 'album',
      'limit': limit,
      if (country != null) 'country': country,
      'lang': 'tr_tr',
    });
    return parseAlbumSearch(data);
  }

  /// Tek bir şarkının kapağını/süresini bulur.
  Future<CatalogTrack?> findTrack(String title, {String? artist}) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return null;

    final cacheKey = '${cleanTitle.toLowerCase()}|${(artist ?? '').toLowerCase()}';
    if (_trackCache.containsKey(cacheKey)) return _trackCache[cacheKey];

    final term = artist != null && artist.trim().isNotEmpty
        ? '${artist.trim()} ${cleanTitle}'
        : cleanTitle;

    final data = await _get('/search', {
      'term': term,
      'entity': 'song',
      'limit': 5,
      'country': 'TR',
    });
    var tracks = parseSongs(data);
    if (tracks.isEmpty) {
      final fallback = await _get('/search', {
        'term': term,
        'entity': 'song',
        'limit': 5,
      });
      tracks = parseSongs(fallback);
    }
    final wanted = _normalize(cleanTitle);
    CatalogTrack? result;
    for (final track in tracks) {
      final name = _normalize(track.title);
      if (name == wanted || name.contains(wanted) || wanted.contains(name)) {
        result = track;
        break;
      }
    }
    _trackCache[cacheKey] = result;
    return result;
  }

  /// Serbest metinle albüm arar (Deezer + iTunes).
  Future<List<CatalogAlbum>> searchAlbums(String term, {int limit = 5}) async {
    final clean = term.trim();
    if (clean.isEmpty) return const [];

    final albums = <CatalogAlbum>[];
    for (final album in await _searchDeezerAlbums(clean, limit: limit)) {
      if (albums.every((existing) => existing.key != album.key)) {
        albums.add(album);
      }
    }

    var data = await _get('/search', {
      'term': clean,
      'entity': 'album',
      'limit': limit,
      'country': 'TR',
    });
    if (albums.length < limit) {
      final itunesAlbums = parseAlbumSearch(data);
      for (final album in itunesAlbums) {
        if (albums.length >= limit) break;
        if (albums.every((existing) => existing.key != album.key)) {
          albums.add(album);
        }
      }
    }
    if (albums.isEmpty) {
      data = await _get('/search', {
        'term': clean,
        'entity': 'album',
        'limit': limit,
      });
      albums.addAll(parseAlbumSearch(data));
    }
    return albums;
  }

  /// Deezer albüm araması.
  Future<List<CatalogAlbum>> _searchDeezerAlbums(String term,
      {int limit = 10}) async {
    final data = await _getDeezer('/search/album', {
      'q': term,
      'limit': limit,
    });
    return parseDeezerAlbums(data);
  }

  /// Deezer albüm ayrıntısı (parça listesiyle).
  Future<CatalogAlbum?> deezerAlbum(String id) async {
    if (id.trim().isEmpty) return null;
    final data = await _getDeezer('/album/${id.trim()}', const {});
    return parseDeezerAlbum(data);
  }

  /// Albüm kimliğiyle parça listesini getirir.
  Future<CatalogAlbum?> lookupAlbum(int collectionId) async {
    final data = await _get('/lookup', {
      'id': '$collectionId',
      'entity': 'song',
      'limit': 200,
      'country': 'TR',
    });
    return parseAlbumLookup(data);
  }

  // ---------------------------------------------------------------------------
  // Ağ
  // ---------------------------------------------------------------------------

  Future<dynamic> _get(String path, Map<String, dynamic> query) async {
    try {
      final response = await _dio.get('$_host$path', queryParameters: query);
      if (response.statusCode != 200) return null;
      final data = response.data;
      // iTunes yanıtı bazen JSON içerik türü yerine metin olarak geliyor.
      if (data is String) {
        try {
          return jsonDecode(data);
        } catch (_) {
          return null;
        }
      }
      return data;
    } catch (e) {
      debugPrint('iTunes katalog isteği başarısız ($path): $e');
    }
    return null;
  }

  Future<dynamic> _getDeezer(String path, Map<String, dynamic> query) async {
    try {
      final response = await _dio.get(
        '$_deezerHost$path',
        queryParameters: query.isEmpty ? null : query,
      );
      if (response.statusCode != 200) return null;
      final data = response.data;
      if (data is String) {
        try {
          return jsonDecode(data);
        } catch (_) {
          return null;
        }
      }
      return data;
    } catch (e) {
      debugPrint('Deezer isteği başarısız ($path): $e');
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Ayrıştırıcılar (test edilebilir, saf fonksiyonlar)
  // ---------------------------------------------------------------------------

  static List<CatalogAlbum> parseDeezerAlbums(dynamic data) {
    if (data is! Map) return const [];
    final results = data['data'];
    if (results is! List) return const [];

    final albums = <CatalogAlbum>[];
    for (final item in results) {
      if (item is! Map) continue;
      final title = (item['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      final artist = item['artist'];
      albums.add(
        CatalogAlbum(
          title: title,
          artist: artist is Map ? (artist['name'] ?? '').toString() : null,
          coverUrl: _deezerCover(item),
          year: null,
          source: 'deezer',
          sourceId: (item['id'] ?? '').toString(),
        ),
      );
    }
    return albums;
  }

  static CatalogAlbum? parseDeezerAlbum(dynamic data) {
    if (data is! Map) return null;
    final title = (data['title'] ?? '').toString().trim();
    if (title.isEmpty) return null;

    final artist = data['artist'];
    final rawTracks = data['tracks'];
    final trackList =
        rawTracks is Map && rawTracks['data'] is List ? rawTracks['data'] as List : const [];

    final cover = _deezerCover(data);
    final tracks = <CatalogTrack>[];
    for (final item in trackList) {
      if (item is! Map) continue;
      final name = (item['title'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final seconds = (item['duration'] as num?)?.toInt();
      final trackArtist = item['artist'];
      tracks.add(
        CatalogTrack(
          title: name.replaceFirst(RegExp(r'\s*\(feat\..*?\)$'), '').trim(),
          artist: trackArtist is Map
              ? (trackArtist['name'] ?? '').toString()
              : null,
          durationMs: seconds == null ? null : seconds * 1000,
          artworkUrl: cover,
        ),
      );
    }

    return CatalogAlbum(
      title: title,
      artist: artist is Map ? (artist['name'] ?? '').toString() : null,
      year: _yearFrom(data['release_date']),
      coverUrl: cover,
      tracks: tracks,
      source: 'deezer',
      sourceId: (data['id'] ?? '').toString(),
    );
  }

  static String? _deezerCover(Map item) {
    for (final key in const ['cover_xl', 'cover_big', 'cover_medium']) {
      final value = (item[key] ?? '').toString();
      if (value.startsWith('https://')) return value;
    }
    return null;
  }

  static List<CatalogAlbum> parseAlbumSearch(dynamic data) {
    final results = _results(data);
    final albums = <CatalogAlbum>[];
    for (final item in results) {
      if (item is! Map) continue;
      final collectionType = (item['collectionType'] ?? '').toString();
      final wrapperType = (item['wrapperType'] ?? '').toString();
      if (wrapperType == 'track') continue;
      if (collectionType.isNotEmpty &&
          collectionType.toLowerCase() != 'album') {
        continue;
      }
      final title = (item['collectionName'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      albums.add(
        CatalogAlbum(
          collectionId: (item['collectionId'] as num?)?.toInt(),
          title: title,
          artist: (item['artistName'] ?? '').toString().trim(),
          year: _yearFrom(item['releaseDate']),
          coverUrl: upscaleArtwork((item['artworkUrl100'] ?? '').toString()),
        ),
      );
    }
    return albums;
  }

  static CatalogAlbum? parseAlbumLookup(dynamic data) {
    final results = _results(data);
    if (results.isEmpty) return null;

    Map? collection;
    final tracks = <CatalogTrack>[];
    for (final item in results) {
      if (item is! Map) continue;
      final wrapperType = (item['wrapperType'] ?? '').toString();
      if (wrapperType == 'collection' && collection == null) {
        collection = item;
      } else if (wrapperType == 'track') {
        final title = (item['trackName'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        tracks.add(
          CatalogTrack(
            title: title,
            artist: (item['artistName'] ?? '').toString().trim(),
            durationMs: (item['trackTimeMillis'] as num?)?.toInt(),
            artworkUrl: upscaleArtwork((item['artworkUrl100'] ?? '').toString()),
          ),
        );
      }
    }

    if (collection == null && tracks.isEmpty) return null;

    final cover = collection != null
        ? upscaleArtwork((collection['artworkUrl100'] ?? '').toString())
        : tracks.first.artworkUrl;

    return CatalogAlbum(
      collectionId: (collection?['collectionId'] as num?)?.toInt(),
      title: (collection?['collectionName'] ?? '').toString().trim(),
      artist: (collection?['artistName'] ?? '').toString().trim(),
      year: _yearFrom(collection?['releaseDate']),
      coverUrl: cover,
      tracks: tracks,
    );
  }

  static List<CatalogTrack> parseSongs(dynamic data) {
    final results = _results(data);
    final tracks = <CatalogTrack>[];
    for (final item in results) {
      if (item is! Map) continue;
      final title = (item['trackName'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      tracks.add(
        CatalogTrack(
          title: title,
          artist: (item['artistName'] ?? '').toString().trim(),
          durationMs: (item['trackTimeMillis'] as num?)?.toInt(),
          artworkUrl: upscaleArtwork((item['artworkUrl100'] ?? '').toString()),
        ),
      );
    }
    return tracks;
  }

  /// `.../100x100bb.jpg` → `.../600x600bb.jpg`
  static String? upscaleArtwork(String url, {int size = 600}) {
    if (url.isEmpty) return null;
    final upscaled =
        url.replaceFirst(RegExp(r'/\d+x\d+bb\.'), '/${size}x${size}bb.');
    return Uri.tryParse(upscaled)?.scheme == 'https' ? upscaled : null;
  }

  static List _results(dynamic data) {
    if (data is Map && data['results'] is List) {
      return data['results'] as List;
    }
    return const [];
  }

  static String? _yearFrom(dynamic releaseDate) {
    final raw = (releaseDate ?? '').toString();
    if (raw.length < 4) return null;
    final year = raw.substring(0, 4);
    return int.tryParse(year) != null ? year : null;
  }

  /// Türkçe karakterleri sadeleştirip karşılaştırma için normalize eder.
  static String _normalize(String value) {
    const map = {
      'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u',
      'â': 'a', 'î': 'i', 'û': 'u',
    };
    var out = value.toLowerCase().trim();
    map.forEach((key, replacement) => out = out.replaceAll(key, replacement));
    return out.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ');
  }
}
