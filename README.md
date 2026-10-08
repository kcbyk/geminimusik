# 🎵 Gemini Müzik & AI Sesli Asistan

## Gemini kurulumu

Gemini anahtarları kaynak kodda tutulmaz. Uygulamayı aşağıdaki gibi çalıştırın:

```powershell
flutter run --dart-define=GEMINI_API_KEY=YOUR_GEMINI_API_KEY
```

Yedek anahtar kullanmak isterseniz virgülle ayırın:

```powershell
flutter run --dart-define=GEMINI_API_KEYS=key1,key2
```

## 🧠 Agent (otonom, araç kullanan ajan)

Agent ekranı artık tek turluk bir "plan yazıcı" değil; **kendi araçlarını seçen,
çok adımlı çalışan ve kendi işini doğrulayan** bir döngü. Gemini'nin native
*function calling* protokolü kullanılır (regex/metin ayrıştırma yok).

### Çalışma döngüsü
1. **Plan** — `update_plan` aracıyla A'dan Z'ye yapılacaklar listesi oluşturulur, ekranda canlı tik listesi olarak görünür.
2. **Keşif** — `list_dir` / `read_file` / `search_files` ile gerçek durum okunur; dosya adı uydurulmaz.
3. **Uygulama** — `write_file`, `edit_file`, `move_file`, `shell` ile iş yapılır.
4. **Doğrulama** — her adımdan sonra çıktı gerçekten okunur/komut gerçekten koşulur; doğrulanmayan şey "tamam" diye raporlanmaz.
5. **Özet** — ne yapıldığı, hangi araç çıktısıyla doğrulandığı ve neyin açık kaldığı yazılır.

### Araçlar
| Araç | Ne yapar |
| --- | --- |
| `update_plan` | Plan kurar/günceller (todo listesi) |
| `list_dir` · `read_file` · `search_files` | Klasör/dosya keşfi, satır aralıklı okuma, içerik arama |
| `write_file` · `edit_file` · `move_file` | Dosya yazma, güvenli düzenleme (girinti toleranslı), taşıma/kopyalama/silme |
| `shell` | Telefonda **gerçek kabuk** (`/system/bin/sh`); stdout+stderr+exit code, zaman aşımı koruması |
| `run_code` | Cihazda kurulu yorumlayıcıyı keşfeder (`probe`) ve kod çalıştırır |
| `web` | İnternet araması ve sayfa okuma |
| `music` | Şarkı arama/çalma/duraklatma/MP3 indirme/oynatıcı kontrolü |
| `phone` | Fener, pil, ses, uygulama açma, arama, cihaz bilgisi |
| `remote_terminal` | *(opsiyonel)* sizin işlettiğiniz uzak yürütücüde komut |

### Güvenlik
- **Çalışma alanı:** ajan varsayılan olarak yalnızca kendi alanına yazar
  (`Android/data/<paket>/files/agent`). Ayarlar menüsündeki
  **"Sınırsız dosya erişimi"** açılırsa `/sdcard` dahil her yola yazabilir.
- **Onay kapısı:** `rm -rf`, `mv`, `chmod`, `pm clear`, kod çalıştırma ve alan
  dışı yollar kullanıcıya sorulur ("İzin ver / Hep izin ver / Reddet").
  Reddedilen adım **hiç çalışmaz** ve model bunu öğrenir.
- **Engelli komutlar:** `rm -rf /`, `mkfs`, `dd of=/dev/...` gibi geri
  döndürülemez kalıplar hiç çalıştırılmaz.
- **Döngü koruması:** aynı araç aynı argümanlarla 3. kez çağrılırsa döngü durur;
  adım limitine takılırsa ajan uydurma özet yerine dürüst durum raporu verir.

### Sesli asistan (Jarvis) da aynı ajanı kullanıyor
Eski `if (komut.contains("fener"))` zinciri kaldırıldı. Artık Jarvis de
`phone` / `music` / `web` araçlarını **modelin kararıyla** çağırıyor; çok adımlı
sesli komutlar ("feneri aç, sonra pili söyle") çalışıyor. Hızlı müzik komutları
gecikme olmaması için yerel ayrıştırıcıda kaldı.

### İsteğe bağlı uzak yürütücü
Telefondaki kabuk yeterlidir; ancak ajanın bir geliştirme makinesinde
derleme/test yapmasını isterseniz:

```powershell
flutter run --dart-define=GEMINI_API_KEY=... --dart-define=AGENT_EXECUTOR_URL=https://sunucunuz/execute
```

Yürütücü, `POST` gövdesinde `{ "command": "..." }` almalı ve
`{ "output": "..." }` döndürmelidir. Bu değişken tanımlıysa `remote_terminal`
aracı otomatik olarak araç setine eklenir (her kullanımda onay ister).

### Testler
Ajan çekirdeği Flutter'dan bağımsız yazıldı, bu yüzden döngü sahte modelle
uçtan uca test edilebiliyor:

```powershell
flutter test
```

`test/agent_loop_test.dart` (döngü, onay, tekrar koruması, iptal, plan),
`test/agent_tools_test.dart` (gerçek dosya sistemi + gerçek kabuk),
`test/agent_screen_test.dart` (zaman çizelgesi, onay diyaloğu, ayarlar),
`test/gemini_turn_test.dart` (function calling kodlaması).

Google Gemini 2.5 Flash destekli yapay zeka sohbeti, 320kbps yüksek kaliteli MP3 müzik indirme/çalma motoru ve **arka planda/kilit ekranında sesli komutla şarkı açabilen (Wake-Word) asistanı** bir araya getiren modern Flutter uygulaması.

[![Build & Release APK](https://github.com/kcbyk/geminimusik/actions/workflows/build_apk.yml/badge.svg)](https://github.com/kcbyk/geminimusik/actions/workflows/build_apk.yml)

👉 **[📲 En Güncel APK Dosyasını İndirmek İçin Buraya Tıkla (Releases)](https://github.com/kcbyk/geminimusik/releases)**

---

## ✨ Öne Çıkan Özellikler

### 1. 🎙️ Kilit Ekranında & Arka Planda Sesli Asistan (Wake-Word)
- Telefon kilitliyken veya uygulama kapalıyken bile sesli komutları algılar.
- **Düşük Güç Tüketimi (Porcupine):** Pili tüketmeden arka planda "Jarvis", "Porcupine", "Bumblebee", "Hey Google" gibi uyandırma kelimelerini bekler.
- **Anahtarsız Yerel Mod:** Herhangi bir API anahtarı veya üyelik olmadan telefonun kendi konuşma tanıma motoruyla doğrudan çalışabilir.
- **Doğal Komutlar:**
  - *"Duman Kırmış Kalbini şarkısını çal"*
  - *"Ezhel Geceler aç"*
  - *"Müziği duraklat"* / *"Çalmaya devam et"*
  - *"Sonraki şarkı"* / *"Kapat"*

### 2. 🎧 Müzik Hub (320kbps MP3 İndirici & Çalar)
- YouTube üzerinden anında şarkı arama ve dinleme.
- CDN destekli yüksek hızlı 320kbps MP3 indirme.
- Canlı indirme çarkı, Spotify/Apple Music tarzı neon gradyan kartlar ve canlı equalizer.
- **TikTok Tarzı Süre Kaydırma:** Mini oynatıcı üzerinde parmakla kaydırarak anında ileri/geri sarma ve canlı zaman balonu.

### 3. 🤖 Gemini 2.5 Flash AI Sohbet & Canlı Web Arama
- Google Gemini 2.5 Flash ile ultra hızlı ve akıllı sohbet motoru.
- Çoklu API anahtarı havuzu (otomatik yük dengeleme ve fallback).
- Canlı web arama entegrasyonu (güncel döviz kurları, haberler, biyografiler).
- Açılır/kapanır kaynaklar akordeonu ve web favicon rozetleri.

---

## 🛠️ Kurulum & Manuel Derleme

Projeyi yerel makinenizde çalıştırmak veya APK üretmek için:

```bash
# Bağımlılıkları yükle
flutter pub get

# Hata kontrolü
flutter analyze

# Android APK Üret (Release)
flutter build apk --release

# Web Sürümünü Derle
flutter build web --release
```

Derlenen APK şurada yer alır:  
`build/app/outputs/flutter-apk/app-release.apk`
