# Sohbet Arayüzü Yükseltmesi — ChatGPT seviyesinde markdown, görsel ve kart dili

Bu sürümde sohbet ekranı; markdown kalitesi, görsel kullanımı ve kart tasarımı
açısından ChatGPT'nin mobil deneyimine yaklaştırıldı. Model tarafı da (sistem
istemi) bu yeni dili üretecek şekilde güncellendi.

---

## 1. Ne değişti? (kısa özet)

| Alan | Önce | Sonra |
| --- | --- | --- |
| Markdown | Tek `MarkdownBody`, sabit 15.5 px, görseller tek tek ve biçimsiz | Blok tabanlı motor: `ChatMarkdown` — 16 px/1.62 ritim, ChatGPT tipografisi |
| Görseller | Karusel (`PageView`) veya ham `Image.network` | **Kolaj**: 1 tam kare, 2 yan yana, 3 büyük + iki küçük, 4+ ızgara ve “+N” |
| Görsel görüntüleme | Yok / basit lightbox | **Tam ekran görüntüleyici**: sayfalar arası kaydırma, pinch-zoom, “3 / 9” sayacı |
| Kod blokları | Dekoratif kutu | Dil etiketi + **tek dokunuşla kopyala** + yatay kaydırma |
| Düşünme | “Yanıt oluşturuluyor…” spinner | **“9s düşündü · 13 web sitesi arandı ⌄”** özeti, açılınca adımlar |
| Kaynaklar | Üstte, büyük kartlar | Yanıtın **altında** favicon'lu çipler, “Tümü” ile genişleme |
| Aksiyonlar | 4 adet `IconButton` | ChatGPT tarzı ikon şeridi: kopyala, 👍, 👎, sesli dinle, yeniden üret, paylaş |
| Müzik | Sadece düz metin | `album` / `tracklist` / `artist` **kart bileşenleri** (kapak + parça listesi + çal/indir) |
| Kullanıcı balonu | Gri, çerçeveli, yarıçap 22 | Sade `#262626`, yarıçap 20, çerçevesiz |

---

## 2. Yeni dosyalar

```
lib/theme/chat_ui.dart                       # tasarım jetonları (renk, tipografi, ölçü)
lib/widgets/chat/chat_markdown.dart          # blok ayrıştırıcı + markdown görünümü + kod bloğu
lib/widgets/chat/chat_image.dart             # görsel referansı, kolaj, tam ekran görüntüleyici
lib/widgets/chat/chat_activity.dart          # "düşündü / web sitesi arandı" satırı + canlı gösterge
lib/widgets/chat/chat_sources.dart           # kaynak çipleri
lib/widgets/chat/chat_actions.dart           # mesaj aksiyon satırı
lib/widgets/chat/music_cards.dart            # albüm kartı, parça satırı, sanatçı kartı
lib/widgets/generative_ui/components/ui_music_widgets.dart  # album/tracklist/artist bileşenleri
test/chat_markdown_test.dart                 # 16 yeni test
design/chat_ui_preview.html                  # tasarımın statik HTML önizlemesi
```

## 3. Güncellenen dosyalar

- `lib/screens/chat_screen.dart` — mesaj çizimi tamamen yenilendi
  (`_buildUserMessage`, `_buildAssistantMessage`, `_buildMusicTransferCard`,
  `_regenerateMessage`), düşünme göstergesi, artık kullanılmayan
  `_ExpandableSourcesWidget` kaldırıldı.
- `lib/widgets/generative_ui/generative_message_view.dart` — metin segmentleri
  `ChatMarkdown` ile çiziliyor.
- `lib/widgets/generative_ui/components/ui_gallery_widget.dart` — karusel yerine
  kolaj + tam ekran görüntüleyici.
- `lib/models/generative_ui/ui_component_model.dart` — `album`, `tracklist`,
  `artist` türleri ve takma adları (`music_album`, `playlist`, `artist_card`…).
- `lib/services/generative_ui/generative_ui_parser.dart` — desteklenen tür listesi.
- `lib/widgets/generative_ui/generative_ui_renderer.dart` — yeni bileşen dalları.
- `lib/models/chat_message.dart` — `thinkingMs`, `activitySteps` alanları
  (geçmiş kaydıyla uyumlu: alan yoksa eski mesajlar sorunsuz yüklenir).
- `lib/services/gemini_service.dart` — sistem istemine “GÖRSEL KULLANIMI”,
  “BAŞLIK VE LİSTE RİTMİ” bölümleri ve albüm/tracklist/artist dokümantasyonu.
- `pubspec.yaml` — `markdown: ^7.3.1` doğrudan bağımlılık olarak eklendi
  (kod bloğu ayrıştırması için; flutter_markdown zaten kullanıyordu).

---

## 4. Modeli yönlendiren yeni kurallar

Sistem istemine eklenen maddeler:

1. Kişi/albüm/ürün hakkında yanıtta **gerçek** görsel URL'si varsa gövdeye
   `![açıklama](https://…jpg)` olarak yerleştir; art arda gelen görseller tek
   blok olarak gösterilir, aralarına boş satır koyma.
2. Görsel URL'si yoksa hiç görsel yazma (yer tutucu/tahmini URL yasak).
3. Bölüm başlıklarında `##` + tek emoji (ör. `## 🎤 Wegh kimdir?`).
4. Künye bilgileri madde listesi, şarkı listeleri numaralı liste.
5. Albüm/parça listeleri için `album` veya `tracklist`, sanatçı için `artist`
   bileşeni üret.

Örnek üretim:

````markdown
## 🎤 Wegh kimdir?

Gerçek adı **Arif Efe Çilli** olan yeni nesil Türkçe rap sanatçısı.

![Wegh](https://…/wegh.jpg)
![Wegh — sahne](https://…/wegh-live.jpg)
![Wegh — albüm kapağı](https://…/curcuna.jpg)

- **Gerçek adı:** Arif Efe Çilli
- **Sahne adı:** Wegh / Wegh Rumi
- **Doğum yılı:** 2000

```ui
{ "type": "album", "title": "CURCUNA", "subtitle": "Wegh", "year": "2026",
  "tracks": [{ "title": "Intro" }, { "title": "Geri Ver" }] }
```
````

---

## 5. Tasarım jetonlarını değiştirmek

Tek dosya: `lib/theme/chat_ui.dart`.

```dart
ChatUi.accent       // vurgu rengi (bağlantı, birincil buton)
ChatUi.body         // gövde metni: 16 px / 1.62
ChatUi.bubbleRadius // kullanıcı balonu
ChatUi.imageRadius  // kolaj köşe yarıçapı
```

Yeni bir bileşen yazarken sabit renk yazmak yerine bu jetonları kullan; böylece
tema değişikliği tek yerden yayılır.

## 6. Yeni bir müzik bileşeni eklemek

1. `ui_component_model.dart` → `_normalizeType` içine takma adları ekle.
2. `generative_ui_parser.dart` → `_supportedTypes` kümesine türü ekle
   (eklenmezse modelin ürettiği JSON sessizce yok sayılır).
3. `generative_ui_renderer.dart` → `switch` içine dalı ekle.
4. Görsel bileşeni `lib/widgets/chat/music_cards.dart` içine yaz.

## 7. Doğrulama

```bash
flutter analyze          # 0 hata
flutter test             # 172 test (156 mevcut + 16 yeni)
```

Yeni testlerin kapsadığı davranışlar: kolaj gruplama, kod bloğu içindeki görsel
sözdiziminin yanlış yakalanmaması, HTML `<img>` desteği, geçersiz URL filtresi,
“+N” sayacı, aktivite satırının açılıp kapanması, kaynak çipleri, albüm/parça
kartları ve 360 px genişlikte taşma olmaması.

## 8. Tasarımı görsel olarak incelemek

`design/chat_ui_preview.html` dosyasını tarayıcıda aç: telefon mockup'ı, renk
jetonları ve yeni davranışların listesi tek sayfada.

---

## 9. Web önizlemesi (telefonda/emülatörde derlemeden bakmak için)

Tam uygulamayı web'e derlemek Android'e özel eklentiler (porcupine,
flutter_foreground_task, torch_light…) ve derleme belleği yüzünden pratik
değil. Bunun yerine yalnızca sohbet katmanını çizen hafif bir giriş noktası var:

```bash
flutter run -d web-server -t lib/preview/main_preview.dart \
  --web-hostname 0.0.0.0 --web-port 8081
```

`lib/preview/main_preview.dart` gerçek `ChatMarkdown`, `ChatImageCollage`,
`AlbumCard`, `ChatSourcesStrip`, `ChatMessageActions` ve `ChatActivityRow`
widget'larını kullanır; içerik hazır demo yanıtlarından gelir. Demo görselleri
`web/demo/` altındadır ve aynı sunucudan servis edilir (CORS sorunu çıkmaz).

### Tam uygulamada demo yanıtları

`--dart-define=DEMO_MODE=true` ile derlenip **API anahtarı yoksa**
`lib/services/demo_content.dart` devreye girer ve arayüzü gerçek yanıt
üretmeden test etmenizi sağlar. Üretim derlemesinde (bayrak verilmezse) ve
anahtar varsa tamamen devre dışıdır.

```bash
# gerçek anahtarla (demo devre dışı)
flutter run --dart-define=GEMINI_API_KEY=...

# anahtarsız, demo içerikle
flutter run --dart-define=DEMO_MODE=true
```

---

## Albüm/parça kapakları ve görsel arama (2026-11)

### Sorun
- Albüm kartlarında kapak yoktu; parça satırlarında hiç görsel yoktu.
- "Görsellerini göster" gibi isteklerde görsel listesi boş dönüyordu
  (`searchImagePreviews` yalnızca sayfa meta görselini arıyor, çoğu sitede
  HTML gelmediği için sessizce boş dönüyordu).

### Çözüm
| Dosya | Görev |
| --- | --- |
| `lib/services/music_catalog_service.dart` | Deezer + iTunes Search API ile gerçek albüm kapağı, parça listesi, süre ve parça kapağı. Emin olamazsa `null` döner (yanlış kapak takmaz). |
| `lib/services/image_discovery_service.dart` | Görsel keşif zinciri: Deezer/Apple kapak → Wikipedia → Wikimedia Commons → Openverse → arka uç (Pinterest + OG görsel). HTTPS + alaka filtresi. |
| `lib/services/image_intent.dart` | Türkçe görsel isteği çözümleme ("Wegh'in fotoğraflarını göster" → `Wegh`). |
| `lib/services/markdown_media.dart` | Görselleri yanıtın ilk paragrafının altına ChatGPT tarzı kolaj olarak yerleştirir. |
| `lib/widgets/chat/music_cards.dart` | `AlbumTrack.artworkUrl`; parça satırında 38×38 yuvarlatılmış kapak, yoksa albüm kapağı. |
| `lib/screens/chat_screen.dart` | `_enrichMusicBlocks`: yanıttaki `album`/`tracklist`/`artist` bloklarını katalogdan doldurur; görsel isteğinde görselleri gömer. |

### Davranış
1. Model `album` bloğu üretir → uygulama Deezer/iTunes'tan kapağı, yılı ve 9
   parçayı (süreleriyle) yazar. Model kapak uydurmaz (prompt'ta yasak).
2. Her parça satırı kendi kapağını gösterir; parçanın kapağı yoksa albüm
   kapağı kullanılır, hiç görsel yoksa satır kapağı yer kaplamaz.
3. "görsellerini göster / fotoğrafları / kapak / görsel bul: X" gibi isteklerde
   gerçek görseller bulunur ve yanıtın içine kolaj olarak eklenir.

### Test
- `test/music_image_test.dart` — 24 test (ayrıştırma, alaka, intent, kolaj, widget).
- `tool/live_check.dart` — canlı ağ kontrolü: `flutter test tool/live_check.dart`.
  CURCUNA / Wegh için Deezer'dan kapak + 9 parça geldiği doğrulandı.

### Ek düzeltme (kart görselleri + kaynak konumu)

**Sorun 1 — kartlarda fotoğraf yok.** `card_grid` / `card` / `info_card` /
`gallery` bloklarındaki `image_url` alanları boş geliyordu (model görsel
uydurmuyor), uygulama da bu türleri doldurmuyordu. "The Last of Us Part II
karakterlerinin görselleri" gibi isteklerde kartlar fotoğrafsız kalıyordu.

Çözüm: `lib/services/ui_image_enricher.dart`
- Her kart için başlık + blok başlığı ile görsel araması yapar
  (ör. `Ellie The Last of Us Part II karakterleri`), sonucu `image_url` alanına yazar.
- Kartlar paralel aranır (en fazla 8), var olan görseller korunur, yalnızca
  `https` kabul edilir, bulunamazsa blok bozulmaz.
- Galeri boşsa başlıktan 6 görsele kadar doldurulur.
- Aynı yol müzik dışı her konu için geçerli (oyun, dizi, film, ürün, kişi…).

**Görsel keşif zinciri hızlandı.** `image_discovery_service.dart`
- Wikipedia + Pinterest (arka uç) + Commons artık **paralel** çalışıyor;
  kart görselleri için `discoverOne()` yalnızca Pinterest + Wikipedia dener.
- Pinterest, oyun/dizi/film karakterleri için en isabetli kaynak olduğu için
  sıralamada öne alındı; Openverse yalnızca hiç sonuç yoksa çağrılıyor.
- Sonuç boşsa sorgu sadeleştirilip (`… deki karakterlerin görselleri` → varlık
  adı) tekrar deneniyor.

**Sorun 2 — kaynaklar en alttaydı.** `ChatSourcesStrip` mesajın en dibinde,
aksiyonların üstünde duruyordu. Artık `ChatActivityRow` içinde:
"9s düşündü · 9 web sitesi arandı ⌄" satırı açıldığında adımların altında
kaynak listesi görünüyor. `AnimatedCrossFade` yerine `AnimatedSize` kullanıldı;
kapalıyken kaynaklar hiç kurulmuyor.

**Testler:** `test/music_image_test.dart` içinde kart zenginleştirme (6 test) ve
kaynak konumu (1 widget testi); toplam 188 test.
