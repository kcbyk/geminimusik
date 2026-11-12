import 'package:flutter/material.dart';

/// Sohbet arayüzünün tek merkezden yönetilen tasarım jetonları.
///
/// Amaç: ChatGPT tarzı sakin, yüksek okunabilirlikli bir sohbet yüzeyi.
/// Tüm yeni bileşenler (markdown, görsel kolajı, kaynak çipleri, aksiyon
/// satırı, albüm kartları) renk/tipografi değerlerini buradan alır.
/// Böylece temayı değiştirmek için tek dosya yeterli olur.
class ChatUi {
  const ChatUi._();

  // ---------------------------------------------------------------------------
  // Renkler
  // ---------------------------------------------------------------------------

  /// Sohbet zemini (OLED siyah).
  static const Color bg = Color(0xFF000000);

  /// Kart / panel yüzeyi.
  static const Color surface = Color(0xFF141414);

  /// Yükseltilmiş yüzey (hover, kod bloğu başlığı, tablo başlığı).
  static const Color surfaceRaised = Color(0xFF1C1C1C);

  /// Kullanıcı baloncuğu.
  static const Color userBubble = Color(0xFF262626);

  static const Color border = Color(0xFF2F2F2F);
  static const Color borderSoft = Color(0xFF242424);

  static const Color textPrimary = Color(0xFFECECEC);
  static const Color textSecondary = Color(0xFFB4B4B4);
  static const Color textMuted = Color(0xFF8F8F8F);

  /// Marka vurgusu (Gemini mavisi) - bağlantı, odak, birincil buton.
  static const Color accent = Color(0xFF6BA6FF);
  static const Color accentSoft = Color(0xFF1B2A45);

  static const Color codeBg = Color(0xFF171717);
  static const Color codeText = Color(0xFFE4E4E4);

  // ---------------------------------------------------------------------------
  // Ölçüler
  // ---------------------------------------------------------------------------

  static const double screenPadding = 16;
  static const double blockGap = 12;
  static const double bubbleRadius = 20;
  static const double cardRadius = 16;
  static const double imageRadius = 16;
  static const double collageGap = 2;

  // ---------------------------------------------------------------------------
  // Tipografi
  // ---------------------------------------------------------------------------

  /// Gövde metni: ChatGPT ile aynı ritim (16 px / 1.62).
  static const TextStyle body = TextStyle(
    color: textPrimary,
    fontSize: 16,
    height: 1.62,
    letterSpacing: 0.02,
  );

  static const TextStyle h1 = TextStyle(
    color: textPrimary,
    fontSize: 23,
    height: 1.35,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  static const TextStyle h2 = TextStyle(
    color: textPrimary,
    fontSize: 19.5,
    height: 1.4,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
  );

  static const TextStyle h3 = TextStyle(
    color: textPrimary,
    fontSize: 17,
    height: 1.45,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle listBullet = TextStyle(
    color: textMuted,
    fontSize: 16,
    height: 1.62,
  );

  static const TextStyle link = TextStyle(
    color: accent,
    fontSize: 16,
    height: 1.62,
    decoration: TextDecoration.underline,
    decorationColor: accent,
  );

  static const TextStyle caption = TextStyle(
    color: textMuted,
    fontSize: 12.5,
    height: 1.4,
  );

  static const TextStyle label = TextStyle(
    color: textSecondary,
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w600,
  );

  /// Ortak yuvarlatılmış kart dekorasyonu.
  static BoxDecoration cardDecoration({
    Color? color,
    double radius = cardRadius,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: color ?? surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? borderSoft, width: 0.8),
    );
  }
}
