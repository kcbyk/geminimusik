import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_music_hub/models/generative_ui/ui_component_model.dart';
import 'package:ai_music_hub/services/image_discovery_service.dart';
import 'package:ai_music_hub/services/image_intent.dart';
import 'package:ai_music_hub/services/markdown_media.dart';
import 'package:ai_music_hub/services/music_catalog_service.dart';
import 'package:ai_music_hub/widgets/chat/music_cards.dart';

/// iTunes Search API yanıtına benzeyen örnek (albüm arama).
Map<String, dynamic> albumSearchFixture() => {
      'resultCount': 2,
      'results': [
        {
          'wrapperType': 'collection',
          'collectionType': 'Album',
          'artistName': 'Wegh',
          'collectionName': 'CURCUNA',
          'collectionId': 1700000001,
          'releaseDate': '2026-02-13T08:00:00Z',
          'trackCount': 9,
          'artworkUrl100':
              'https://is1-ssl.mzstatic.com/image/thumb/x/100x100bb.jpg',
        },
        {
          'wrapperType': 'collection',
          'collectionType': 'Album',
          'artistName': 'Baska Sanatci',
          'collectionName': 'Curcuna Radyo',
          'collectionId': 1700000002,
          'releaseDate': '2019-01-01T08:00:00Z',
          'artworkUrl100':
              'https://is1-ssl.mzstatic.com/image/thumb/y/100x100bb.jpg',
        },
      ],
    };

Map<String, dynamic> albumLookupFixture() => {
      'resultCount': 3,
      'results': [
        {
          'wrapperType': 'collection',
          'collectionType': 'Album',
          'artistName': 'Wegh',
          'collectionName': 'CURCUNA',
          'collectionId': 1700000001,
          'releaseDate': '2026-02-13T08:00:00Z',
          'artworkUrl100':
              'https://is1-ssl.mzstatic.com/image/thumb/x/100x100bb.jpg',
        },
        {
          'wrapperType': 'track',
          'trackName': 'Geri Ver',
          'artistName': 'Wegh',
          'trackTimeMillis': 178000,
          'artworkUrl100':
              'https://is1-ssl.mzstatic.com/image/thumb/x/100x100bb.jpg',
        },
        {
          'wrapperType': 'track',
          'trackName': 'Sana Vuruldum',
          'artistName': 'Wegh',
          'trackTimeMillis': 161000,
          'artworkUrl100':
              'https://is1-ssl.mzstatic.com/image/thumb/z/100x100bb.jpg',
        },
      ],
    };

void main() {
  group('MusicCatalogService ayrıştırma', () {
    test('Albüm aramasını çözer ve kapağı 600px\'e yükseltir', () {
      final albums =
          MusicCatalogService.parseAlbumSearch(albumSearchFixture());

      expect(albums, hasLength(2));
      expect(albums.first.title, 'CURCUNA');
      expect(albums.first.artist, 'Wegh');
      expect(albums.first.year, '2026');
      expect(albums.first.collectionId, 1700000001);
      expect(albums.first.coverUrl, contains('600x600bb.jpg'));
      expect(albums.first.coverUrl, isNot(contains('100x100')));
    });

    test('Albüm lookup parça listesini süreleriyle birlikte çözer', () {
      final album = MusicCatalogService.parseAlbumLookup(albumLookupFixture());

      expect(album, isNotNull);
      expect(album!.title, 'CURCUNA');
      expect(album.tracks, hasLength(2));
      expect(album.tracks.first.title, 'Geri Ver');
      expect(album.tracks.first.durationLabel, '2:58');
      expect(album.tracks[1].durationLabel, '2:41');
      // Parçaların kendi kapağı da çözülmeli.
      expect(album.tracks.every((t) => (t.artworkUrl ?? '').isNotEmpty), isTrue);
      expect(album.tracks[1].artworkUrl, contains('/600x600bb.jpg'));
      expect(album.coverUrl, contains('600x600bb.jpg'));
    });

    test('Şarkı aramasını çözer', () {
      final tracks = MusicCatalogService.parseSongs({
        'results': [
          {
            'wrapperType': 'track',
            'trackName': 'Delta',
            'artistName': 'Wegh',
            'trackTimeMillis': 125000,
            'artworkUrl100':
                'https://is1-ssl.mzstatic.com/image/thumb/q/100x100bb.jpg',
          },
        ],
      });

      expect(tracks, hasLength(1));
      expect(tracks.first.durationLabel, '2:05');
    });

    test('Geçersiz/boş yanıtlar güvenli biçimde boş döner', () {
      expect(MusicCatalogService.parseAlbumSearch(null), isEmpty);
      expect(MusicCatalogService.parseSongs({'results': 'x'}), isEmpty);
      expect(MusicCatalogService.parseAlbumLookup(null), isNull);
    });

    test('upscaleArtwork yalnızca https adresleri kabul eder', () {
      expect(
        MusicCatalogService.upscaleArtwork(
            'https://is1.mzstatic.com/a/100x100bb.jpg'),
        'https://is1.mzstatic.com/a/600x600bb.jpg',
      );
      expect(
        MusicCatalogService.upscaleArtwork(
            'http://is1.mzstatic.com/a/100x100bb.jpg'),
        isNull,
      );
      expect(MusicCatalogService.upscaleArtwork(''), isNull);
    });

    test('CatalogTrack.toJson parça kartı alanlarını üretir', () {
      const track = CatalogTrack(
        title: 'Geri Ver',
        artist: 'Wegh',
        durationMs: 178000,
        artworkUrl: 'https://x/600x600bb.jpg',
      );
      expect(track.toJson(), {
        'title': 'Geri Ver',
        'artist': 'Wegh',
        'duration': '2:58',
        'artwork': 'https://x/600x600bb.jpg',
      });
    });
  });

  group('ImageDiscoveryService ayrıştırma', () {
    test('Wikipedia pageimages yanıtından görsel çıkarır', () {
      final images = ImageDiscoveryService.parseWikipedia({
        'query': {
          'pages': {
            '42': {
              'title': 'Wegh',
              'thumbnail': {
                'source': 'https://upload.wikimedia.org/thumb/wegh.jpg',
                'width': 320,
              },
              'original': {'source': 'https://upload.wikimedia.org/wegh.jpg'},
            },
          },
        },
      });

      expect(images, hasLength(1));
      expect(images.first.url, 'https://upload.wikimedia.org/wegh.jpg');
      expect(images.first.thumbnailUrl,
          'https://upload.wikimedia.org/thumb/wegh.jpg');
      expect(images.first.source, 'Wikipedia');
    });

    test('Görseli olmayan sayfalar atlanır', () {
      final images = ImageDiscoveryService.parseWikipedia({
        'query': {
          'pages': {
            '1': {'title': 'Bos Sayfa'},
          },
        },
      });
      expect(images, isEmpty);
    });

    test('Openverse sonuçlarını çözer', () {
      final images = ImageDiscoveryService.parseOpenverse({
        'results': [
          {
            'url': 'https://live.staticflickr.com/1/a.jpg',
            'thumbnail': 'https://live.staticflickr.com/1/a_small.jpg',
            'title': 'Konser',
            'creator': 'Birisi',
            'source': 'flickr',
            'foreign_landing_url': 'https://flickr.com/1',
          },
        ],
      });

      expect(images, hasLength(1));
      expect(images.first.title, 'Konser');
      expect(images.first.source, 'flickr');
      expect(images.first.toGalleryJson()['url'],
          'https://live.staticflickr.com/1/a.jpg');
    });

    test('Kullanılamaz görsel adresleri elenir', () {
      expect(ImageDiscoveryService.isUsableImageUrl('https://x/a.jpg'), isTrue);
      expect(ImageDiscoveryService.isUsableImageUrl('http://x/a.jpg'), isFalse);
      expect(ImageDiscoveryService.isUsableImageUrl('https://x/logo.png'),
          isFalse);
      expect(ImageDiscoveryService.isUsableImageUrl('https://x/ikon.svg'),
          isFalse);
      expect(ImageDiscoveryService.isUsableImageUrl(''), isFalse);
    });
  });

  group('Müzik kartı görselleri', () {
    testWidgets('Albüm kartındaki her parça satırı kendi kapağını gösterir',
        (tester) async {
      const tracks = [
        AlbumTrack(
          title: 'Geri Ver',
          duration: '2:58',
          artworkUrl: 'https://cdn.test/geriver.jpg',
        ),
        AlbumTrack(
          title: 'Sana Vuruldum',
          duration: '2:41',
          artworkUrl: 'https://cdn.test/vuruldum.jpg',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AlbumCard(
                title: 'CURCUNA',
                artist: 'Wegh',
                year: '2026',
                coverUrl: 'https://cdn.test/album.jpg',
                tracks: tracks,
              ),
            ),
          ),
        ),
      );

      // Albüm kapağı + iki parça kapağı.
      final covers = tester.widgetList<AlbumCover>(
        find.descendant(
          of: find.byType(AlbumCard),
          matching: find.byType(AlbumCover),
        ),
      ).toList();
      final urls = covers.map((cover) => cover.url).toList();

      expect(urls, contains('https://cdn.test/album.jpg'));
      expect(urls, contains('https://cdn.test/geriver.jpg'));
      expect(urls, contains('https://cdn.test/vuruldum.jpg'));

      // Parça kapakları albüm kartındakinden küçük olmalı.
      final trackCover = covers.firstWhere(
        (cover) => cover.url == 'https://cdn.test/geriver.jpg',
      );
      expect(trackCover.size, lessThan(60));
    });

    testWidgets('Parçanın kapağı yoksa albüm kapağı kullanılır',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrackListCard(
              title: 'En iyi şarkılar',
              coverUrl: 'https://cdn.test/liste.jpg',
              tracks: const [AlbumTrack(title: 'Delta')],
            ),
          ),
        ),
      );

      final covers = tester
          .widgetList<AlbumCover>(find.byType(AlbumCover))
          .map((cover) => cover.url)
          .toList();
      // Başlık kapağı + satır kapağı.
      expect(covers.where((url) => url == 'https://cdn.test/liste.jpg').length,
          2);
    });

    testWidgets('Görsel yoksa satır kapağı yer kaplamaz', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackListCard(tracks: [AlbumTrack(title: 'Delta')]),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(TrackRow),
          matching: find.byType(AlbumCover),
        ),
        findsNothing,
      );
      expect(find.text('Delta'), findsOneWidget);
    });

    test('tracksFromComponent artwork alanını okur', () {
      const component = UiComponent(
        type: 'album',
        title: 'CURCUNA',
        data: {
          'tracks': [
            {
              'title': 'Geri Ver',
              'duration': '2:58',
              'artwork': 'https://cdn.test/geriver.jpg',
            },
            {
              'title': 'Sana Vuruldum',
              'artwork': {'url': 'https://cdn.test/vuruldum.jpg'},
            },
            'Delta',
          ],
        },
      );

      final tracks = tracksFromComponent(component);
      expect(tracks, hasLength(3));
      expect(tracks[0].artworkUrl, 'https://cdn.test/geriver.jpg');
      expect(tracks[0].duration, '2:58');
      expect(tracks[1].artworkUrl, 'https://cdn.test/vuruldum.jpg');
      expect(tracks[2].artworkUrl, isNull);
    });

    test('AlbumTrack.withArtwork yalnızca boş alanı doldurur', () {
      const track = AlbumTrack(
        title: 'Delta',
        duration: '2:05',
        artworkUrl: 'https://cdn.test/ozel.jpg',
      );
      final withArtwork = track.withArtwork('https://cdn.test/albumm.jpg');
      expect(withArtwork.artworkUrl, 'https://cdn.test/ozel.jpg');
      expect(withArtwork.duration, '2:05');
      expect(track.withArtwork(null).artworkUrl, 'https://cdn.test/ozel.jpg');
    });
  });

  group('Görsel isteği algılama', () {
    test('Türkçe görsel isteklerinden varlık adı çıkarır', () {
      const cases = {
        'Wegh görsellerini göster': 'Wegh',
        'bana Wegh fotoğrafları': 'Wegh',
        "Wegh'in fotoğraflarını göster": 'Wegh',
        'Wegh’in resimlerini göster': 'Wegh',
        'curcuna albümünün kapağını göster': 'curcuna',
        'CURCUNA kapak': 'CURCUNA',
        'görsel bul: kırmızı arabalar': 'kırmızı arabalar',
        'resim: Tarkan konser': 'Tarkan konser',
        'Tarkan kimdir': 'Tarkan',
        'Melike Şahin hakkında bilgi ver': 'Melike Şahin',
        'Wegh şarkıcısının fotoğrafını göster': 'Wegh',
      };
      cases.forEach((input, expected) {
        expect(imageIntentQuery(input), expected, reason: input);
      });
    });

    test('Görsel isteği olmayan mesajlarda null döner', () {
      for (final input in [
        'merhaba',
        'nasıl yaparım',
        'Flutter ile state yönetimi',
        'bana bir şarkı öner',
        '',
      ]) {
        expect(imageIntentQuery(input), isNull, reason: input);
      }
    });

    test('Sadece "görsel göster" dendiğinde başlıktan varlık türetir', () {
      expect(
        imageIntentQuery('görselleri göster',
            content: '# Wegh\n\nTürkçe rap sanatçısı.'),
        'Wegh',
      );
      expect(imageIntentQuery('görselleri göster'), isNull);
    });

    test('Müzik sorgusu tespiti', () {
      expect(looksMusical('Wegh albümünü göster'), isTrue);
      expect(looksMusical('Curcuna kapağı'), isTrue);
      expect(looksMusical('hava durumu'), isFalse);
    });
  });

  group('Yanıta görsel yerleştirme', () {
    const content = '# Wegh\n\nTürkçe rap sahnesinin dikkat çeken isimlerinden biri. '
        'Kısa sürede geniş bir dinleyici kitlesine ulaştı.\n\n## Albümleri\n\n- CURCUNA (2026)';

    test('Görseller ilk paragrafın altına kolaj olarak eklenir', () {
      final result = insertImagesIntoMarkdown(content, [
        'https://cdn.test/1.jpg',
        'https://cdn.test/2.jpg',
        'https://cdn.test/3.jpg',
        'https://cdn.test/4.jpg',
      ]);

      expect(RegExp(r'!\[').allMatches(result).length, 3);
      expect(result.indexOf('![görsel](https://cdn.test/1.jpg)'),
          lessThan(result.indexOf('## Albümleri')));
      expect(result, contains('# Wegh'));
      expect(result, isNot(contains('cdn.test/4.jpg')));
    });

    test('Yanıtta zaten görsel varsa en fazla bir tane eklenir', () {
      final withOne = '$content\n\n![mevcut](https://cdn.test/var.jpg)';
      final result =
          insertImagesIntoMarkdown(withOne, ['https://cdn.test/yeni.jpg']);
      expect(RegExp(r'!\[').allMatches(result).length, 2);
    });

    test('İki ve daha fazla görsel varsa hiç eklenmez', () {
      final withTwo = '$content\n\n![a](https://cdn.test/a.jpg)\n'
          '![b](https://cdn.test/b.jpg)';
      final result =
          insertImagesIntoMarkdown(withTwo, ['https://cdn.test/c.jpg']);
      expect(result, withTwo);
    });

    test('http olmayan adresler yok sayılır', () {
      final result = insertImagesIntoMarkdown(content, ['/demo/a.png', '']);
      expect(result, content);
    });

    test('Paragraf yoksa sonuna eklenir', () {
      final result = insertImagesIntoMarkdown('Kısa yanıt.', [
        'https://cdn.test/x.jpg',
      ]);
      expect(result, 'Kısa yanıt.\n\n![görsel](https://cdn.test/x.jpg)');
    });
  });
}
