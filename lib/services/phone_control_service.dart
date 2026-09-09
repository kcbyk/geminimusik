import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:torch_light/torch_light.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:volume_controller/volume_controller.dart';

/// Jarvis Telefon ve Donanım Kontrol Servisi
class PhoneControlService {
  static final PhoneControlService instance = PhoneControlService._internal();
  PhoneControlService._internal();

  final Battery _battery = Battery();
  bool _isTorchOn = false;

  bool get isTorchOn => _isTorchOn;

  /// Feneri Aç / Kapat
  Future<String> toggleFlashlight({bool? enable}) async {
    try {
      final target = enable ?? !_isTorchOn;
      if (target) {
        await TorchLight.enableTorch();
        _isTorchOn = true;
        return 'Fener açıldı efendim.';
      } else {
        await TorchLight.disableTorch();
        _isTorchOn = false;
        return 'Fener kapatıldı efendim.';
      }
    } catch (e) {
      debugPrint('[PhoneControl] Fener hatası: $e');
      return 'Fener kontrol edilemedi, cihazınız desteklemiyor olabilir.';
    }
  }

  /// Pil Seviyesi ve Durumu
  Future<String> getBatteryInfo() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;

      String stateDesc = '';
      if (state == BatteryState.charging) {
        stateDesc = 've şu anda şarj oluyor';
      } else if (state == BatteryState.full) {
        stateDesc = 've batarya tamamen dolu';
      }

      return 'Pil seviyeniz yüzde $level $stateDesc efendim.'.trim();
    } catch (e) {
      debugPrint('[PhoneControl] Pil hatası: $e');
      return 'Pil bilgisi alınamadı.';
    }
  }

  /// Ses Seviyesi Kontrolü (yükselt, kıs, sessize al, maksimum)
  Future<String> adjustVolume(String command) async {
    try {
      final current = await VolumeController().getVolume();
      double target = current;

      final lower = command.toLowerCase();
      if (lower.contains('sessiz') || lower.contains('kapat') || lower.contains('sıfırla')) {
        target = 0.0;
        VolumeController().setVolume(target);
        return 'Ses tamamen kısıldı efendim.';
      } else if (lower.contains('ful') || lower.contains('son ses') || lower.contains('maksimum')) {
        target = 1.0;
        VolumeController().setVolume(target);
        return 'Ses maksimum seviyeye getirildi efendim.';
      } else if (lower.contains('yükselt') || lower.contains('arttır') || lower.contains('aç')) {
        target = (current + 0.2).clamp(0.0, 1.0);
        VolumeController().setVolume(target);
        final percent = (target * 100).round();
        return 'Ses seviyesi yüzde $percent yapıldı efendim.';
      } else if (lower.contains('kıs') || lower.contains('azalt')) {
        target = (current - 0.2).clamp(0.0, 1.0);
        VolumeController().setVolume(target);
        final percent = (target * 100).round();
        return 'Ses seviyesi yüzde $percent yapıldı efendim.';
      }
      return 'Mevcut ses seviyesi yüzde ${(current * 100).round()} efendim.';
    } catch (e) {
      debugPrint('[PhoneControl] Ses kontrol hatası: $e');
      return 'Ses seviyesi ayarlanamadı.';
    }
  }

  /// Uygulama Başlatıcı (WhatsApp, YouTube, Spotify, Kamera, Harita, vb.)
  Future<String> openApplication(String appName) async {
    final lower = appName.toLowerCase().trim();

    try {
      // 1. WhatsApp
      if (lower.contains('whatsapp') || lower.contains('vatsap')) {
        final uri = Uri.parse('whatsapp://send');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return 'WhatsApp açılıyor efendim.';
        } else {
          return await _openStoreOrWeb('https://web.whatsapp.com', 'WhatsApp');
        }
      }

      // 2. YouTube
      if (lower.contains('youtube') || lower.contains('yutub')) {
        final appUri = Uri.parse('vnd.youtube://');
        if (await canLaunchUrl(appUri)) {
          await launchUrl(appUri, mode: LaunchMode.externalApplication);
          return 'YouTube açılıyor efendim.';
        }
        final webUri = Uri.parse('https://www.youtube.com');
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        return 'YouTube açılıyor efendim.';
      }

      // 3. Spotify
      if (lower.contains('spotify') || lower.contains('spotifay')) {
        final uri = Uri.parse('spotify://');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return 'Spotify açılıyor efendim.';
        }
        final webUri = Uri.parse('https://open.spotify.com');
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        return 'Spotify açılıyor efendim.';
      }

      // 4. Haritalar / Navigasyon
      if (lower.contains('harita') || lower.contains('maps') || lower.contains('navigasyon')) {
        final uri = Uri.parse('geo:0,0?q=');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return 'Haritalar açılıyor efendim.';
        }
        final webUri = Uri.parse('https://maps.google.com');
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        return 'Haritalar açılıyor efendim.';
      }

      // 5. Telefon / Arama
      if (lower.contains('ara') || lower.contains('telefon') || lower.contains('çağrı')) {
        final uri = Uri.parse('tel:');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return 'Arama ekranı açılıyor efendim.';
        }
      }

      // 6. Tarayıcı / Google
      if (lower.contains('chrome') || lower.contains('tarayıcı') || lower.contains('google')) {
        final uri = Uri.parse('https://www.google.com');
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return 'Tarayıcı açılıyor efendim.';
      }

      // 7. E-Posta / Gmail
      if (lower.contains('mail') || lower.contains('eposta') || lower.contains('gmail')) {
        final uri = Uri.parse('mailto:');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return 'E-posta uygulamanız açılıyor efendim.';
        }
      }

      return '$appName uygulaması cihazınızda bulunamadı efendim.';
    } catch (e) {
      debugPrint('[PhoneControl] Uygulama açma hatası: $e');
      return '$appName açılamadı efendim.';
    }
  }

  /// Telefon Araması Yap
  Future<String> makePhoneCall(String target) async {
    try {
      final cleanNum = target.replaceAll(RegExp(r'[^0-9+]'), '');
      final uri = Uri.parse('tel:$cleanNum');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return '${cleanNum.isNotEmpty ? cleanNum : 'Arama ekranı'} aranıyor efendim.';
      }
      return 'Arama başlatılamadı efendim.';
    } catch (e) {
      debugPrint('[PhoneControl] Arama hatası: $e');
      return 'Arama açılamadı.';
    }
  }

  Future<String> _openStoreOrWeb(String webUrl, String name) async {
    final uri = Uri.parse(webUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return '$name açılıyor efendim.';
    }
    return '$name cihazınızda bulunamadı.';
  }
}
