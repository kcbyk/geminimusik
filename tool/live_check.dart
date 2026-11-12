// Canlı ağ kontrolü (CI'da çalışmaz, elle çalıştırılır):
//   flutter test tool/live_check.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_music_hub/services/image_discovery_service.dart';
import 'package:ai_music_hub/services/music_catalog_service.dart';
import 'package:ai_music_hub/services/ui_image_enricher.dart';

void main() {
  test('CURCUNA / Wegh: kapak + 9 parça + süreler', () async {
    final album =
        await MusicCatalogService.instance.findAlbum('CURCUNA', artist: 'Wegh');
    print('albüm: ${album?.title} / ${album?.artist} / ${album?.year} '
        '(${album?.source})');
    print('kapak: ${album?.coverUrl}');
    for (final track in album?.tracks ?? const []) {
      print('  - ${track.title} (${track.durationLabel})');
    }
    expect(album, isNotNull);
    expect(album!.title.toUpperCase(), contains('CURCUNA'));
    expect(album.coverUrl, isNotNull);
    expect(album.tracks.length, greaterThanOrEqualTo(9));
    expect(album.tracks.every((t) => t.durationLabel != null), isTrue);
    expect(album.tracks.every((t) => t.artworkUrl != null), isTrue);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('iTunes yedeği: Geri Ver / Wegh', () async {
    final album = await MusicCatalogService.instance
        .findAlbum('Kennedy\'i Ben Vurdum', artist: 'Wegh');
    print('iTunes: ${album?.title} (${album?.source}) ${album?.coverUrl}');
    expect(album, isNotNull);
    expect(album!.coverUrl, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('Alakasız sorguda yanlış kapak takmaz', () async {
    final album = await MusicCatalogService.instance
        .findAlbum('zzqqxx bilinmeyen albüm 12345');
    print('alakasız sonuç: $album');
    expect(album, isNull);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('Görsel keşif: albüm kapağı önce gelir', () async {
    final images = await ImageDiscoveryService.instance
        .discover('CURCUNA Wegh', limit: 6, musicFirst: true);
    for (final image in images) {
      print('  - [${image.source}] ${image.title} → ${image.url}');
    }
    expect(images, isNotEmpty);
    expect(images.first.source, 'Deezer albüm kapağı');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('Oyun karakteri: Ellie (The Last of Us Part II) görseli', () async {
    final images = await ImageDiscoveryService.instance.discover(
        'Ellie The Last of Us Part II', limit: 4);
    for (final image in images) {
      print('  - [${image.source}] ${image.title} → ${image.url}');
    }
    expect(images, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('card_grid: karakter kartları gerçek görsellerle dolar', () async {
    final data = <String, dynamic>{
      'type': 'card_grid',
      'title': 'The Last of Us Part II karakterleri',
      'cards': [
        {'title': 'Ellie', 'description': 'Oynanabilir ana karakter'},
        {'title': 'Abby', 'description': 'Oynanabilir ikinci karakter'},
        {'title': 'Joel', 'description': 'Ellie\'nin babası figürü'},
      ],
    };
    final enriched = await UiImageEnricher().fillImages(data);
    expect(enriched, isNotNull);
    for (final card in data['cards'] as List) {
      print('  - ${card['title']}: ${card['image_url']}');
      expect(card['image_url'], isNotNull);
      expect(card['image_url'], startsWith('https://'));
    }
  }, timeout: const Timeout(Duration(seconds: 120)));
}
