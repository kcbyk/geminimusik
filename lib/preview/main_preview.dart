import 'package:flutter/material.dart';

import '../theme/chat_ui.dart';
import '../widgets/chat/chat_actions.dart';
import '../widgets/chat/chat_activity.dart';
import '../widgets/chat/chat_markdown.dart';
import '../widgets/chat/chat_sources.dart';
import '../widgets/chat/music_cards.dart';

/// Yalnızca yeni sohbet arayüzünü gösteren hafif web önizlemesi.
///
/// Tam uygulamayı web'e derlemek Android'e özel eklentiler ve 2 GB'lık derleme
/// belleği yüzünden pratik değil; bu giriş noktası gerçek widget'ları (aynı
/// ChatMarkdown, ChatImageCollage, AlbumCard…) kullanır ama bağımlılık ağacını
/// küçük tutar:
///
/// ```bash
/// flutter run -d web-server -t lib/preview/main_preview.dart --web-port 8081
/// ```
void main() => runApp(const PreviewApp());

class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemini Music — Sohbet UI Önizleme',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: ChatUi.bg,
        colorScheme: const ColorScheme.dark(primary: ChatUi.accent),
      ),
      home: const PreviewHome(),
    );
  }
}

class _DemoTurn {
  final String prompt;
  final String answer;
  final Duration thinking;
  final int sources;
  final List<Map<String, String>> sourceList;

  /// true ise yanıtın altında albüm kartı çizilir.
  final bool withAlbum;

  const _DemoTurn({
    required this.prompt,
    required this.answer,
    required this.thinking,
    this.sources = 0,
    this.sourceList = const [],
    this.withAlbum = false,
  });
}

/// Aynı sunucudan gelen demo görselleri (CORS/ağ sorunu çıkmasın diye yerel).
String _asset(String name) => Uri.base.resolve('demo/$name').toString();

/// `__IMG1__` gibi yer tutucuları çalışma zamanında gerçek URL'ye çevirir.
String _resolveImages(String markdown) => markdown
    .replaceAll('__IMG1__', _asset('portrait-1.png'))
    .replaceAll('__IMG2__', _asset('stage-2.png'))
    .replaceAll('__IMG3__', _asset('cover-3.png'));

const List<_DemoTurn> _turns = [
  _DemoTurn(
    prompt: 'Wegh kimdir',
    thinking: Duration(seconds: 9),
    sources: 13,
    answer: '''
## 🎤 Wegh kimdir?

**Wegh**, yeni nesil Türkçe rap sahnesinin dikkat çeken isimlerinden biri.
Gerçek adı **Arif Efe Çilli**; sahne adı olarak *Wegh Rumi*'yi de kullanıyor.

![Wegh stüdyoda](__IMG1__)
![Wegh sahnede](__IMG2__)
![CURCUNA kapağı](__IMG3__)

- **Gerçek adı:** Arif Efe Çilli
- **Sahne adı:** Wegh / Wegh Rumi
- **Doğum yılı:** 2000
- **Kariyer başlangıcı:** 2020–2021

Sert vokal geçişleri, değişken flow kullanımı ve karanlık beat tercihleriyle
tanınıyor. Diskografisinde 2026 çıkışlı **CURCUNA** öne çıkıyor.
''',
    sourceList: [
      {'title': 'Wegh — Vikipedi', 'url': 'https://tr.wikipedia.org/wiki/Wegh'},
      {'title': 'CURCUNA — Apple Music', 'url': 'https://music.apple.com/tr'},
      {'title': 'Wegh', 'url': 'https://open.spotify.com'},
      {'title': 'Geri Ver (Official)', 'url': 'https://youtube.com'},
    ],
  ),
  _DemoTurn(
    prompt: 'CURCUNA albümünü tanıt',
    thinking: Duration(seconds: 6),
    sources: 8,
    withAlbum: true,
    answer: '''
## 🎧 CURCUNA (2026)

Wegh'in 2026'da yayımlanan albümü **9 parçadan** oluşuyor; prodüksiyonda trap
ile boom-bap arasında bir denge var.

### Albümün öne çıkanları

1. **Geri Ver** — 2025'te tekli olarak çıktı, albümde yeniden düzenlendi
2. **Tütün ve Votka** — en sert vokal geçişleri
3. **Halef Selef** — albümün en çok dinlenen parçası

| Parça | Süre | Tür |
| --- | --- | --- |
| Intro | 1:12 | Giriş |
| Geri Ver | 2:58 | Tekli |
| Halef Selef | 3:12 | Albüm |

Parça satırına dokunmak *"… şarkısını çal"*, indirme ikonuna dokunmak
*"… şarkısını indir"* komutunu üretir.
''',
    sourceList: [
      {'title': 'CURCUNA — Apple Music', 'url': 'https://music.apple.com/tr'},
      {'title': 'CURCUNA', 'url': 'https://open.spotify.com'},
    ],
  ),
  _DemoTurn(
    prompt: 'Markdown görselleri nasıl çalışıyor?',
    thinking: Duration(seconds: 4),
    sources: 3,
    answer: '''
## 💻 Markdown görselleri nasıl çalışıyor?

Görseli gövdeye markdown sözdizimiyle koymak yeterli. Art arda yazılan görseller
tek bir **kolaj** hâline gelir.

```dart
final markdown = \'\'\'
## 🎤 Wegh kimdir?

![Wegh](https://cdn.example/1.jpg)
![Wegh](https://cdn.example/2.jpg)
![Wegh](https://cdn.example/3.jpg)
\'\'\';

await tester.pumpWidget(ChatMarkdown(data: markdown));
```

### Kolaj kuralı

| Görsel sayısı | Düzen |
| --- | --- |
| 1 | Tam genişlik, yuvarlatılmış kare |
| 2 | Yan yana iki eşit kare |
| 3 | Solda büyük + sağda üst üste iki kare |
| 4+ | 2×2 ızgara, son karede "+N" |

> Kod bloğunun sağ üstündeki **Kopyala** düğmesi metni panoya alır.
''',
  ),
];

class PreviewHome extends StatefulWidget {
  const PreviewHome({super.key});

  @override
  State<PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<PreviewHome> {
  final List<_DemoTurn> _shown = [_turns.first];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _next = 1;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final value = (text ?? _controller.text).trim();
    if (value.isEmpty) return;
    setState(() {
      // İstemle eşleşen hazır yanıtı seç, yoksa sıradakini göster.
      final match = _turns.where(
        (t) => value.toLowerCase().contains(
              t.prompt.toLowerCase().split(' ').first,
            ),
      );
      final turn = match.isNotEmpty
          ? match.first
          : _turns[_next++ % _turns.length];
      _shown.add(turn);
      _controller.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 760;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              children: [
                _buildHeader(isNarrow),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      for (final turn in _shown) ...[
                        _buildUser(turn.prompt),
                        _buildAssistant(turn),
                      ],
                      if (isNarrow) const SizedBox(height: 40),
                    ],
                  ),
                ),
                _buildComposer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isNarrow) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4285F4), Color(0xFF9B72CB), Color(0xFFD96570)],
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: const Text('♪', style: TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gemini Music · Sohbet arayüzü',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: ChatUi.textPrimary,
                  ),
                ),
                Text(
                  'Gerçek Flutter widget\'ları — demo yanıtlar',
                  style: ChatUi.caption,
                ),
              ],
            ),
          ),
          if (!isNarrow)
            TextButton.icon(
              onPressed: () => setState(() {
                _shown
                  ..clear()
                  ..add(_turns[_next++ % _turns.length]);
              }),
              icon: const Icon(Icons.refresh_rounded,
                  size: 16, color: ChatUi.textMuted),
              label: const Text(
                'Başka örnek',
                style: TextStyle(fontSize: 12.5, color: ChatUi.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUser(String prompt) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 18, left: 44),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            color: ChatUi.userBubble,
            borderRadius: BorderRadius.circular(ChatUi.bubbleRadius),
          ),
          child: Text(
            prompt,
            style: const TextStyle(
              color: ChatUi.textPrimary,
              fontSize: 15.5,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssistant(_DemoTurn turn) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 3),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF4285F4), Color(0xFF9B72CB)],
              ),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ChatActivityRow(
                  thinking: turn.thinking,
                  sourceCount: turn.sources,
                  searchQuery: turn.prompt,
                  extraSteps: const ['İçerik değerlendiriliyor'],
                ),
                ChatMarkdown(data: _resolveImages(turn.answer)),
                if (turn.withAlbum)
                  AlbumCard(
                    title: 'CURCUNA',
                    artist: 'Wegh',
                    year: '2026',
                    coverUrl: _asset('cover-3.png'),
                    tracks: const [
                      AlbumTrack(title: 'Intro', duration: '1:12'),
                      AlbumTrack(title: 'Tütün ve Votka', duration: '2:47'),
                      AlbumTrack(title: 'Geri Ver', duration: '2:58'),
                      AlbumTrack(title: 'Radikal Eşkıya', duration: '3:04'),
                      AlbumTrack(title: 'Baliber', duration: '2:31'),
                      AlbumTrack(title: 'Halef Selef', duration: '3:12'),
                    ],
                    onAction: (prompt) => _send(prompt),
                  ),
                if (turn.sourceList.isNotEmpty)
                  ChatSourcesStrip(sources: turn.sourceList),
                const SizedBox(height: 4),
                ChatMessageActions(
                  rawText: turn.answer,
                  onSpeak: () {},
                  onRegenerate: () => _send(turn.prompt),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: ChatUi.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: ChatUi.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.add_rounded, color: ChatUi.textMuted, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                style: const TextStyle(
                  color: ChatUi.textPrimary,
                  fontSize: 15,
                ),
                decoration: const InputDecoration(
                  hintText: 'Bir şey sor… (demo)',
                  hintStyle: TextStyle(color: ChatUi.textMuted, fontSize: 15),
                  border: InputBorder.none,
                ),
                onSubmitted: (v) => _send(v),
              ),
            ),
            Material(
              color: ChatUi.accent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _send(),
                child: const Padding(
                  padding: EdgeInsets.all(7),
                  child: Icon(Icons.arrow_upward_rounded,
                      size: 18, color: Color(0xFF04101F)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
