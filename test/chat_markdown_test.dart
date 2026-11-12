import 'package:ai_music_hub/models/generative_ui/ui_component_model.dart';
import 'package:ai_music_hub/models/generative_ui/ui_action_model.dart';
import 'package:ai_music_hub/widgets/chat/chat_activity.dart';
import 'package:ai_music_hub/widgets/chat/chat_image.dart';
import 'package:ai_music_hub/widgets/chat/chat_markdown.dart';
import 'package:ai_music_hub/widgets/chat/chat_sources.dart';
import 'package:ai_music_hub/widgets/chat/music_cards.dart';
import 'package:ai_music_hub/widgets/generative_ui/components/ui_gallery_widget.dart';
import 'package:ai_music_hub/widgets/generative_ui/generative_message_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
}

void main() {
  group('MarkdownBlocks', () {
    test('art arda gelen görselleri tek kolaj bloğuna toplar', () {
      const source = '''
Dostum! İşte birkaç görsel:

![Wegh](https://example.com/1.jpg)
![Wegh](https://example.com/2.jpg)
![Wegh](https://example.com/3.jpg)

Bu arada kariyeri 2020'de başladı.
''';
      final blocks = MarkdownBlocks.parse(source);
      expect(blocks.length, 3);
      expect(blocks[0].kind, MdBlockKind.text);
      expect(blocks[1].kind, MdBlockKind.images);
      expect(blocks[1].images.length, 3);
      expect(blocks[1].images.first.url, 'https://example.com/1.jpg');
      expect(blocks[2].kind, MdBlockKind.text);
    });

    test('kod bloğu içindeki görsel sözdizimini görsel sanmaz', () {
      const source = '''
Kod örneği:
```dart
final link = "![alt](https://example.com/x.jpg)";
```
''';
      final blocks = MarkdownBlocks.parse(source);
      expect(blocks.length, 2);
      expect(blocks[0].kind, MdBlockKind.text);
      expect(blocks[1].kind, MdBlockKind.code);
      expect(blocks[1].language, 'dart');
      expect(blocks[1].text.contains('example.com'), isTrue);
    });

    test('HTML img etiketini de görsel olarak tanır', () {
      const source = '<img src="https://example.com/a.png" alt="A">';
      final blocks = MarkdownBlocks.parse(source);
      expect(blocks.single.kind, MdBlockKind.images);
      expect(blocks.single.images.single.alt, 'A');
    });

    test('göreli / geçersiz görsel yollarını yok sayar', () {
      const source = '![x](images/local.png)';
      final blocks = MarkdownBlocks.parse(source);
      expect(blocks.single.kind, MdBlockKind.text);
    });
  });

  group('ChatMarkdown render', () {
    testWidgets('başlık, liste, tablo ve kod bloğu sorunsuz çizilir',
        (tester) async {
      const content = '''
## 🎤 Wegh kimdir?

Gerçek adı **Arif Efe Çilli** olan yeni nesil Türkçe rap sanatçısı.

- Gerçek adı: Arif Efe Çilli
- Sahne adı: Wegh / Wegh Rumi
- Doğum yılı: 2000

| Şarkı | Yıl |
| --- | --- |
| Kennedy'i Ben Vurdum | 2024 |
| Geri Ver | 2025 |

```dart
void main() => runApp(const App());
```
''';
      await tester.pumpWidget(_wrap(const ChatMarkdown(data: content)));
      await tester.pump();

      expect(find.textContaining('Wegh kimdir?'), findsOneWidget);
      expect(find.textContaining('Arif Efe Çilli'), findsWidgets);
      expect(find.textContaining('Geri Ver'), findsOneWidget);
      // Kod bloğu başlığı ve kopyala düğmesi
      expect(find.text('dart'), findsOneWidget);
      expect(find.text('Kopyala'), findsOneWidget);
    });

    testWidgets('tek görsel ve 3 görselli kolaj çizilir', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChatImageCollage(
            images: [
              ChatImageRef(url: 'https://example.com/1.jpg'),
              ChatImageRef(url: 'https://example.com/2.jpg'),
              ChatImageRef(url: 'https://example.com/3.jpg'),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ChatImageTile), findsNWidgets(3));
    });

    testWidgets('5+ görselde +N sayacı görünür', (tester) async {
      final images = List.generate(
        7,
        (i) => ChatImageRef(url: 'https://example.com/$i.jpg'),
      );
      await tester.pumpWidget(_wrap(ChatImageCollage(images: images)));
      await tester.pump();
      expect(find.text('+3'), findsOneWidget);
    });
  });

  group('Sohbet bileşenleri', () {
    testWidgets('aktivite satırı açılıp kapanır', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChatActivityRow(
            thinking: Duration(seconds: 9),
            sourceCount: 13,
            searchQuery: 'Wegh kimdir',
            extraSteps: ['İçerik değerlendiriliyor'],
          ),
        ),
      );
      expect(find.textContaining('9s düşündü'), findsOneWidget);
      expect(find.textContaining('13 web sitesi arandı'), findsOneWidget);

      await tester.tap(find.textContaining('9s düşündü'));
      await tester.pumpAndSettle();
      expect(find.text('İçerik değerlendiriliyor'), findsOneWidget);
      expect(find.text('Arama: Wegh kimdir'), findsOneWidget);
    });

    testWidgets('kaynak şeridi çiplerini gösterir', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChatSourcesStrip(
            sources: [
              {'title': 'Wikipedia', 'url': 'https://tr.wikipedia.org/wiki/Wegh'},
              {'title': 'Apple Music', 'url': 'https://music.apple.com/tr'},
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.text('2 kaynak'), findsOneWidget);
      expect(find.text('Wikipedia'), findsOneWidget);
      expect(find.textContaining('wikipedia.org'), findsOneWidget);
    });

    testWidgets('galeri kolaj + tümünü gör düğmesi', (tester) async {
      const comp = UiComponent(
        type: 'gallery',
        title: 'Wegh görselleri',
        data: {
          'images': [
            {'url': 'https://example.com/1.jpg', 'caption': 'Foto 1'},
            {'url': 'https://example.com/2.jpg', 'caption': 'Foto 2'},
            {'url': 'https://example.com/3.jpg', 'caption': 'Foto 3'},
          ],
        },
      );
      await tester.pumpWidget(_wrap(const UiGalleryWidget(component: comp)));
      await tester.pump();
      expect(find.text('Wegh görselleri'), findsOneWidget);
      expect(find.text('Tümünü gör (3)'), findsOneWidget);
      expect(find.byType(ChatImageTile), findsNWidgets(3));
    });
  });

  group('Müzik bileşenleri', () {
    testWidgets('albüm kartı parça listesini çizer', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AlbumCard(
            title: 'CURCUNA',
            artist: 'Wegh',
            year: '2026',
            tracks: const [
              AlbumTrack(title: 'Intro'),
              AlbumTrack(title: 'Tütün ve Votka'),
              AlbumTrack(title: 'Geri Ver'),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.text('CURCUNA'), findsOneWidget);
      expect(find.textContaining('Wegh · 2026 · 3 parça'), findsOneWidget);
      expect(find.text('Tütün ve Votka'), findsOneWidget);
    });

    testWidgets('```ui album``` bloğu GenerativeMessageView içinde çizilir',
        (tester) async {
      const content = '''
İşte albümü:
```ui
{
  "type": "album",
  "title": "CURCUNA",
  "subtitle": "Wegh",
  "year": "2026",
  "tracks": [
    {"title": "Intro"},
    {"title": "Halef Selef"}
  ]
}
```
''';
      await tester.pumpWidget(_wrap(const GenerativeMessageView(content: content)));
      await tester.pump();
      expect(find.text('CURCUNA'), findsOneWidget);
      expect(find.text('Halef Selef'), findsOneWidget);
    });

    testWidgets('tracklist ve artist türleri render edilir', (tester) async {
      final tracklist = UiAlbumWidgetHarness(
        component: const UiComponent(
          type: 'tracklist',
          title: 'En dikkat çeken şarkıları',
          data: {
            'tracks': [
              {'title': "Kennedy'i Ben Vurdum", 'duration': '2:41'},
              {'title': 'Sana Vuruldum', 'artist': 'Ulubatlı Hasan'},
            ],
          },
        ),
      );
      await tester.pumpWidget(_wrap(tracklist));
      await tester.pump();
      expect(find.text("Kennedy'i Ben Vurdum"), findsOneWidget);
      expect(find.text('2:41'), findsOneWidget);
      expect(find.text('Ulubatlı Hasan'), findsOneWidget);
    });
  });

  group('UiComponent normalize', () {
    test('müzik türü takma adları doğru türe çevrilir', () {
      expect(UiComponent.fromJson({'type': 'music_album'}).type, 'album');
      expect(UiComponent.fromJson({'type': 'playlist'}).type, 'tracklist');
      expect(UiComponent.fromJson({'type': 'artist_card'}).type, 'artist');
    });

    test('UiAction prompt olarak taşınır', () {
      const action = UiAction(type: 'prompt', label: 'Çal', value: 'Çal');
      expect(action.value, 'Çal');
    });
  });

  group('Mesaj düzeni', () {
    testWidgets('dar ekranda asistan mesajı taşmadan çizilir', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      const content = """
## 🎤 Wegh kimdir?

Gerçek adı **Arif Efe Çilli** olan yeni nesil Türkçe rap sanatçısı.

![Wegh](https://example.com/1.jpg)
![Wegh](https://example.com/2.jpg)
![Wegh](https://example.com/3.jpg)

- **Gerçek adı:** Arif Efe Çilli
- **Sahne adı:** Wegh / Wegh Rumi
- **Doğum yılı:** 2000

```dart
final x = 1;
```

| Şarkı | Yıl |
| --- | --- |
| Geri Ver | 2025 |
""";

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 40),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.auto_awesome, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          ChatActivityRow(
                            thinking: Duration(seconds: 9),
                            sourceCount: 13,
                            searchQuery: 'Wegh kimdir',
                          ),
                          ChatMarkdown(data: content),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 200),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(ChatImageTile), findsNWidgets(3));
    });
  });
}

/// Tracklist bileşenini tek başına test etmek için küçük sarmalayıcı.
class UiAlbumWidgetHarness extends StatelessWidget {
  final UiComponent component;

  const UiAlbumWidgetHarness({super.key, required this.component});

  @override
  Widget build(BuildContext context) {
    return GenerativeMessageView(
      content: '```ui\n{"type":"${component.type}","title":"${component.title}",'
          '"tracks":[{"title":"Kennedy\'i Ben Vurdum","duration":"2:41"},'
          '{"title":"Sana Vuruldum","artist":"Ulubatlı Hasan"}]}\n```',
    );
  }
}
