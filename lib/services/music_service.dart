import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song_model.dart';

class MusicService {
  // 1. Birincil & En Hızlı Doğrudan MP3 Motoru (CORS & Web Tam Uyumlu): youtube-mp36
  static const String _rapidMp3Host = 'youtube-mp36.p.rapidapi.com';
  static const String _rapidApiKey = 'adc4b7af04mshadb5aab86d5eff7p1946e8jsn61fbc4deba81';

  // 2. Yedek RapidAPI Akış Motoru: ytstream-download-youtube-videos (Çoklu Yedek Anahtar Havuzu)
  static const String _rapidApiHost = 'ytstream-download-youtube-videos.p.rapidapi.com';
  static const String _rapidApiBaseUrl = 'https://ytstream-download-youtube-videos.p.rapidapi.com';
  static const List<String> _ytStreamApiKeys = [
    'adc4b7af04mshadb5aab86d5eff7p1946e8jsn61fbc4deba81', // Birincil Anahtar
    '550292b6c2msh6f03553b10bc495p15d293jsn1a8ef5f8e47f', // Yedek Anahtar 1
    'a25458b35dmshff7650f186959bcp12b071jsn8408bc851eb2', // Yedek Anahtar 2
    'f890c11bc2msh5d052433c7ad0d5p15925djsn5a5f8b7a00a3', // Yedek Anahtar 3
  ];

  // 3. Yedek Render API
  static const String _baseUrl = 'https://mp3-apisi.onrender.com';
  static const String _apiKey = 'sk-212601df4dcd2036cb5b4da3';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  /// YouTube video ID'sini URL veya ID metninden ayıklar
  static String? extractYouTubeId(String? input) {
    if (input == null) return null;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // Doğrudan 11 karakterli video ID
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(trimmed)) {
      return trimmed;
    }

    // URL formatları: ?v=..., youtu.be/..., embed/..., shorts/...
    final match = RegExp(r'(?:v=|\/embed\/|\/v\/|youtu\.be\/|\/shorts\/)([a-zA-Z0-9_-]{11})').firstMatch(trimmed);
    if (match != null) {
      return match.group(1);
    }

    return null;
  }

  /// 1. APİ (BİRİNCİL): RapidAPI youtube-mp36 üzerinden doğrudan, CDN barındırmalı ve CORS uyumlu gerçek .mp3 bağlantısını çeker
  /// Hem Web'de hem Mobilde 0.5 saniyede donmadan, Format Hatası 4 vermeden çalar!
  Future<String?> getDirectMp3Link(String videoId) async {
    try {
      int attempts = 0;
      while (attempts < 5) {
        attempts++;
        final response = await _dio.get(
          'https://$_rapidMp3Host/dl',
          queryParameters: {'id': videoId},
          options: Options(
            headers: {
              'x-rapidapi-host': _rapidMp3Host,
              'x-rapidapi-key': _rapidApiKey,
            },
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
          ),
        );

        if (response.statusCode == 200 && response.data != null) {
          final data = response.data;
          if (data is Map<String, dynamic>) {
            final status = data['status']?.toString();
            final link = data['link']?.toString();
            if (status == 'ok' && link != null && link.isNotEmpty) {
              return link;
            }
            if (status == 'processing') {
              // Hazırlanıyorsa 1 saniye bekleyip tekrar dene
              await Future.delayed(const Duration(milliseconds: 1200));
              continue;
            }
          }
        }
        break;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 2. APİ: ytstream üzerinden doğrudan ses akışı URL'i çeker (Tüm yedek anahtarları sırayla dener)
  Future<String?> getRapidApiAudioStream(String videoId) async {
    for (final apiKey in _ytStreamApiKeys) {
      try {
        final response = await _dio.get(
          '$_rapidApiBaseUrl/dl',
          queryParameters: {'id': videoId},
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'x-rapidapi-host': _rapidApiHost,
              'x-rapidapi-key': apiKey,
            },
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
          ),
        );

        if (response.statusCode == 200 && response.data != null) {
          final data = response.data;
          if (data is Map<String, dynamic>) {
            // 1. adaptiveFormats içinde ses akışı arayalım
            final adaptiveFormats = data['adaptiveFormats'] as List?;
            if (adaptiveFormats != null) {
              // Öncelikle tüm cihaz ve tarayıcılarda en sorunsuz çalan audio/mp4 (m4a/aac) formatı
              for (final f in adaptiveFormats) {
                final mime = (f['mimeType'] ?? '').toString();
                final url = f['url']?.toString();
                if (mime.contains('audio/mp4') && url != null && url.isNotEmpty) {
                  return url;
                }
              }
              // Bulunamazsa diğer ses formatları (audio/webm vb.)
              for (final f in adaptiveFormats) {
                final mime = (f['mimeType'] ?? '').toString();
                final url = f['url']?.toString();
                if (mime.contains('audio') && url != null && url.isNotEmpty) {
                  return url;
                }
              }
            }

            // 2. formats (birleşik ses/video formatları) içinden URL
            final formats = data['formats'] as List?;
            if (formats != null) {
              for (final f in formats) {
                final url = f['url']?.toString();
                if (url != null && url.isNotEmpty) {
                  return url;
                }
              }
            }
          }
        }
      } catch (_) {
        // Bu anahtar başarısız olursa veya kotası biterse döngü sonraki yedek anahtarla devam eder
      }
    }
    return null;
  }

  /// Şarkı adına göre YALNIZCA YouTube üzerinden arama yapar (SoundCloud ve Archive hariç tutulur)
  Future<List<SongItem>> searchSongs(String query) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/v1/search',
        queryParameters: {
          'q': query,
          'limit': 30,
          'key': _apiKey,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final list = response.data['sonuclar'] as List?;
        if (list != null) {
          return list
              .map((item) => SongItem.fromJson(item as Map<String, dynamic>))
              .where((song) => song.source.toLowerCase() == 'youtube')
              .toList();
        }
      }
      return [];
    } catch (e) {
      throw Exception('Şarkı araması sırasında hata oluştu: $e');
    }
  }

  /// URL ile doğrudan dönüştürme başlatır (/convert)
  Future<Map<String, dynamic>> convertUrl({
    required String url,
    required String title,
    String source = 'youtube',
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/api/v1/convert',
        queryParameters: {'key': _apiKey},
        data: {
          'url': url,
          'baslik': title,
          'kaynak': source,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
      throw Exception('Dönüştürme görevi başlatılamadı');
    } catch (e) {
      // POST /convert başarısız olursa instantJob'a geç
      return startInstantJob(title);
    }
  }

  /// 2. API (YEDEK): Anında dönüştürme başlatır (/instant) ve job_id döndürür
  Future<Map<String, dynamic>> startInstantJob(String query) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/v1/instant',
        queryParameters: {
          'q': query,
          'key': _apiKey,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
      throw Exception('Dönüştürme görevi başlatılamadı');
    } catch (e) {
      throw Exception('İndirme isteği hatası: $e');
    }
  }

  /// 2. API (YEDEK): Durum kontrolü yapar (/status/{job_id})
  Future<Map<String, dynamic>> checkStatus(String jobId) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/v1/status/$jobId',
        queryParameters: {'key': _apiKey},
      );

      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
      throw Exception('Durum sorgulanamadı');
    } catch (e) {
      throw Exception('Durum sorgu hatası: $e');
    }
  }

  /// Hazır olan dosyanın tam URL'ini döndürür
  String getFullDownloadUrl(String remotePath) {
    String fullUrl;
    if (remotePath.startsWith('http://') || remotePath.startsWith('https://')) {
      fullUrl = remotePath;
    } else {
      final cleanPath = remotePath.startsWith('/') ? remotePath : '/$remotePath';
      fullUrl = '$_baseUrl$cleanPath';
    }
    final separator = fullUrl.contains('?') ? '&' : '?';
    return '$fullUrl${separator}key=$_apiKey';
  }

  /// Ses dosyasını cihaza kaydeder (Doğrudan stream veya yedek sunucu dosyası)
  Future<String> downloadMp3File({
    required String remotePath,
    required String fallbackFileName,
    required Function(int received, int total) onProgress,
  }) async {
    final fullUrl = remotePath.startsWith('http://') || remotePath.startsWith('https://')
        ? remotePath
        : getFullDownloadUrl(remotePath);

    if (kIsWeb) {
      // Web platformunda dosya sistemi yerine doğrudan tarayıcı stream veya URL kullanılır
      return fullUrl;
    }

    try {
      final directory = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();

      // Müzik dosyalarını tutacağımız klasör
      final musicDir = Directory('${directory.path}/Music');
      if (!await musicDir.exists()) {
        await musicDir.create(recursive: true);
      }

      // Dosya adını sanitize et
      String safeName = fallbackFileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      if (!safeName.endsWith('.mp3') && !safeName.endsWith('.m4a')) {
        safeName += '.mp3';
      }

      final savePath = '${musicDir.path}/$safeName';

      await _dio.download(
        fullUrl,
        savePath,
        onReceiveProgress: onProgress,
      );

      return savePath;
    } catch (e) {
      // Eğer yerel diske indirme başarısız olsa bile direkt URL'yi döndürerek çalınmasını sağla
      return fullUrl;
    }
  }
}
