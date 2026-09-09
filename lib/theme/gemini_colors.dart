import 'package:flutter/material.dart';

class GeminiColors {
  // Zemin: Tam Siyah #000000 (OLED / Pitch Black)
  static const Color background = Color(0xFF000000);
  static const Color sidebarBackground = Color(0xFF0D0D0D);
  static const Color inputBackground = Color(0xFF141414);
  static const Color inputHover = Color(0xFF1C1C1C);
  static const Color cardBackground = Color(0xFF111111);
  static const Color cardHover = Color(0xFF1A1A1A);
  static const Color userBubbleBackground = Color(0xFF1A1A1A);

  // Çizgiler ve ayırıcılar (Siyah zemin için ince zarif tonlar)
  static const Color border = Color(0xFF222222);
  static const Color divider = Color(0xFF1A1A1A);

  // Metin renkleri
  static const Color textPrimary = Color(0xFFF0F0F0);
  static const Color textSecondary = Color(0xFFCCCCCC);
  static const Color textMuted = Color(0xFF7E7E7E);

  // Gemini ikon ve gradyan vurgu renkleri
  static const Color geminiBlue = Color(0xFF4285F4);
  static const Color geminiPurple = Color(0xFF9B72CB);
  static const Color geminiRed = Color(0xFFD96570);
  static const Color geminiCyan = Color(0xFF4DAAF6);

  // Gemini Karşılama Gradyanı
  static const LinearGradient welcomeGradient = LinearGradient(
    colors: [
      Color(0xFF4285F4),
      Color(0xFF9B72CB),
      Color(0xFFD96570),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sparkGradient = LinearGradient(
    colors: [
      Color(0xFF4285F4),
      Color(0xFF9B72CB),
    ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
