# 🎵 Gemini Müzik & AI Sesli Asistan

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
