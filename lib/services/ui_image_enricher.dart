import 'dart:async';

import 'package:flutter/foundation.dart';

import 'image_discovery_service.dart';

/// Yanıttaki kart/galeri bloklarına gerçek görsel ekler.
///
/// Model görsel URL'si uydurmadığı için `image_url` alanları boş geliyor;
/// bu sınıf her kart için kısa bir görsel araması yapıp alanı dolduruyor.
/// Oyun/dizi/film karakterleri, ürünler, kişiler — hepsi aynı yoldan geçer.
///
/// [resolveImage] test edilebilirlik için enjekte edilebilir.
class UiImageEnricher {
  final Future<String?> Function(String query) resolveImage;
  final Future<List<String>> Function(String query) resolveGallery;

  /// Aynı anda kaç kart için arama yapılır (hız/güvenlik dengesi).
  final int maxCards;

  UiImageEnricher({
    Future<String?> Function(String query)? resolveImage,
    Future<List<String>> Function(String query)? resolveGallery,
    this.maxCards = 8,
  })  : resolveImage = resolveImage ??
            ((query) => ImageDiscoveryService.instance.discoverOne(query)),
        resolveGallery = resolveGallery ??
            ((query) async {
              final images = await ImageDiscoveryService.instance
                  .discover(query, limit: 6,
                      timeout: const Duration(seconds: 10));
              return images.map((image) => image.url).toList();
            });

  /// Blokta görsel alanı boşsa doldurur; değişiklik yoksa `null` döner.
  Future<Map<String, dynamic>?> fillImages(Map<String, dynamic> data) async {
    final type = (data['type'] ?? '').toString().toLowerCase();
    switch (type) {
      case 'card_grid':
      case 'cardgrid':
      case 'grid':
        return _fillCardList(data);
      case 'gallery':
        return _fillGallery(data);
      case 'card':
      case 'info_card':
      case 'product_card':
        return _fillSingleCard(data);
      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> _fillCardList(Map<String, dynamic> data) async {
    final raw = data['cards'] ?? data['items'];
    if (raw is! List || raw.isEmpty) return null;

    final parentTitle = (data['title'] ?? data['subtitle'] ?? '').toString().trim();
    final jobs = <Future<void>>[];
    var changed = false;
    var scheduled = 0;

    for (final item in raw) {
      if (scheduled >= maxCards) break;
      if (item is! Map) continue;

      if (_hasImage(item)) continue;
      final title = _titleOf(item);
      if (title == null) continue;

      scheduled++;
      final query = parentTitle.isEmpty
          ? title
          : '$title $parentTitle';
      jobs.add(() async {
        final url = await _safeResolve(query);
        if (url == null) return;
        item['image_url'] = url;
        changed = true;
      }());
    }

    if (jobs.isEmpty) return null;
    await Future.wait(jobs);
    return changed ? data : null;
  }

  Future<Map<String, dynamic>?> _fillGallery(Map<String, dynamic> data) async {
    final raw = data['images'] ?? data['items'];
    final existing = raw is List ? raw.where(_itemHasImage).length : 0;
    if (existing >= 1) return null;

    final title = (data['title'] ?? data['name'] ?? '').toString().trim();
    if (title.isEmpty) return null;

    final usable = await _safeGallery(title);
    if (usable.isEmpty) return null;

    data['images'] = [
      for (final url in usable) {'image_url': url},
    ];
    return data;
  }

  Future<Map<String, dynamic>?> _fillSingleCard(
      Map<String, dynamic> data) async {
    if (_hasImage(data)) return null;

    final title = _titleOf(data);
    if (title == null) return null;
    final subtitle = (data['subtitle'] ?? data['description'] ?? '')
        .toString()
        .trim();
    final query = subtitle.isEmpty ? title : '$title $subtitle';

    final url = await _safeResolve(query);
    if (url == null) return null;

    // Bileşenlerin okuduğu alan adları farklı.
    final type = (data['type'] ?? '').toString().toLowerCase();
    if (type == 'card') {
      data['image'] = url;
    } else {
      data['image_url'] = url;
    }
    return data;
  }

  // ---------------------------------------------------------------------------

  static bool _hasImage(Map item) {
    for (final key in const ['image_url', 'image', 'imageUrl', 'banner', 'thumbnail', 'thumbnail_url', 'cover']) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) return true;
    }
    return false;
  }

  static bool _itemHasImage(dynamic item) {
    if (item is Map) return _hasImage(item);
    if (item is String) return item.trim().startsWith('http');
    return false;
  }

  static String? _titleOf(Map item) {
    for (final key in const ['title', 'name', 'label', 'category']) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  Future<String?> _safeResolve(String query) async {
    try {
      final url = await resolveImage(query);
      if (url == null) return null;
      return url.startsWith('https://') ? url : null;
    } catch (e) {
      debugPrint('Kart görseli bulunamadı ($query): $e');
      return null;
    }
  }

  Future<List<String>> _safeGallery(String query) async {
    try {
      final urls = await resolveGallery(query);
      return urls
          .map((url) => url.trim())
          .where((url) => url.startsWith('https://'))
          .toList();
    } catch (e) {
      debugPrint('Galeri görselleri bulunamadı ($query): $e');
      return const [];
    }
  }
}
