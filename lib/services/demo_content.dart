/// API anahtarı olmadan arayüzü denemek için hazır yanıtlar.
///
/// Yalnızca `--dart-define=DEMO_MODE=true` ile derlendiğinde ve **hiç API
/// anahtarı yoksa** devreye girer. Üretim derlemesinde tamamen kapalıdır,
/// gerçek anahtar varsa hiç kullanılmaz. Amaç: web/masaüstü önizlemesinde
/// markdown, görsel kolajı, albüm kartı ve kaynak şeridinin nasıl göründüğünü
/// gerçek yanıt üretmeden gösterebilmek.
class DemoContent {
  const DemoContent._();

  static const bool enabled =
      bool.fromEnvironment('DEMO_MODE', defaultValue: false);

  /// İsteme uygun hazır yanıtı döndürür. Demo kapalıysa null döner.
  static String? textFor(String prompt) {
    if (!enabled) return null;
    final lower = prompt.toLowerCase();

    final String text;
    if (lower.contains('albüm') ||
        lower.contains('album') ||
        lower.contains('curcuna') ||
        lower.contains('parça')) {
      text = _album;
    } else if (lower.contains('kod') ||
        lower.contains('markdown') ||
        lower.contains('görsel') ||
        lower.contains('tablo')) {
      text = _kod;
    } else if (lower.contains('merhaba') || lower.contains('selam')) {
      text = _selam;
    } else {
      text = _kisi;
    }

    return text;
  }

  // ---------------------------------------------------------------------------
  // Hazır yanıtlar
  // ---------------------------------------------------------------------------

  static const String _selam = '''
Merhaba! Ben Gemini Music'in sohbet asistanı. Demo modunda çalışıyorum, yani
yanıtlar örnek içerikten geliyor.

Şunları deneyebilirsin:

- **Wegh kimdir** → kişi + görsel kolajı örneği
- **CURCUNA albümünü tanıt** → albüm kartı + parça listesi
- **Markdown görselleri nasıl çalışıyor?** → kod bloğu + tablo
''';

  static const String _kisi = '''
## 🎤 Wegh kimdir?

**Wegh**, yeni nesil Türkçe rap sahnesinin dikkat çeken isimlerinden biri.
Gerçek adı **Arif Efe Çilli**; sahne adı olarak *Wegh Rumi*'yi de kullanıyor.

![Wegh stüdyoda](https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/PNG_transparency_demonstration_1.png/280px-PNG_transparency_demonstration_1.png)
![Wegh sahnede](https://upload.wikimedia.org/wikipedia/commons/thumb/9/9a/Gull_portrait_ca_usa.jpg/320px-Gull_portrait_ca_usa.jpg)
![CURCUNA kapağı](https://upload.wikimedia.org/wikipedia/commons/thumb/3/3f/JPEG_example_flower.jpg/320px-JPEG_example_flower.jpg)

- **Gerçek adı:** Arif Efe Çilli
- **Sahne adı:** Wegh / Wegh Rumi
- **Doğum yılı:** 2000
- **Kariyer başlangıcı:** 2020–2021

Sert vokal geçişleri, değişken flow kullanımı ve karanlık beat tercihleriyle
tanınıyor. Diskografisinde 2026 çıkışlı **CURCUNA** öne çıkıyor.

> Bu yanıt demo modunda üretildi; görseller yalnızca kolaj düzenini göstermek
> için yer tutucudur.
''';

  static const String _album = '''
## 🎧 CURCUNA (2026)

Wegh'in 2026'da yayımlanan albümü **9 parçadan** oluşuyor; prodüksiyonda trap
ile boom-bap arasında bir denge var.

```ui
{
  "type": "album",
  "title": "CURCUNA",
  "subtitle": "Wegh",
  "year": "2026",
  "tracks": [
    {"title": "Intro", "duration": "1:12"},
    {"title": "Tütün ve Votka", "duration": "2:47"},
    {"title": "Geri Ver", "duration": "2:58"},
    {"title": "Radikal Eşkıya", "duration": "3:04"},
    {"title": "Baliber", "duration": "2:31"},
    {"title": "Daha Çok Var", "duration": "2:44"},
    {"title": "Halef Selef", "duration": "3:12"},
    {"title": "ŞŞS", "duration": "2:20"},
    {"title": "Outro", "duration": "1:05"}
  ]
}
```

### Albümün öne çıkanları

1. **Geri Ver** — 2025'te tekli olarak çıktı, albümde yeniden düzenlendi
2. **Tütün ve Votka** — en sert vokal geçişleri
3. **Halef Selef** — albümün en çok dinlenen parçası

Parça satırına dokunmak *"… şarkısını çal"*, indirme ikonuna dokunmak
*"… şarkısını indir"* komutunu üretir.
''';

  static const String _kod = '''
## 💻 Markdown görselleri nasıl çalışıyor?

Görseli yanıt gövdesine markdown sözdizimiyle koymak yeterli. Art arda yazılan
görseller tek bir **kolaj** hâline gelir.

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
| 4+ | 2×2 ızgara, son karede “+N” |

Kod bloğunun sağ üstündeki **Kopyala** düğmesi metni panoya alır.
''';
}
