import 'package:flutter/material.dart';
import '../../../models/generative_ui/ui_action_model.dart';
import '../../../models/generative_ui/ui_component_model.dart';
import '../../../theme/gemini_colors.dart';
import 'ui_buttons_widget.dart';

class UiAppMockupWidget extends StatefulWidget {
  final UiComponent component;
  final void Function(UiAction action)? onAction;

  const UiAppMockupWidget({
    super.key,
    required this.component,
    this.onAction,
  });

  @override
  State<UiAppMockupWidget> createState() => _UiAppMockupWidgetState();
}

class _UiAppMockupWidgetState extends State<UiAppMockupWidget> {
  int _activeThemeIndex = 0;

  @override
  Widget build(BuildContext context) {
    final data = widget.component.data;
    final appName = (data['appName'] ?? widget.component.title ?? 'Mobil Uygulama').toString();
    final appType = (data['category'] ?? data['appType'] ?? 'Finans & Bankacılık').toString();
    final balance = (data['balance'] ?? '₺ 142.850,00').toString();
    final cardHolder = (data['cardHolder'] ?? 'AHMET YILMAZ').toString();
    final cardNumber = (data['cardNumber'] ?? '•••• •••• •••• 4892').toString();

    // Theme options
    final themes = (data['themes'] is List && (data['themes'] as List).isNotEmpty)
        ? (data['themes'] as List).whereType<Map<String, dynamic>>().toList()
        : [
            {
              'name': 'Gece Mavisi (Modern)',
              'primary': const Color(0xFF1E3A8A),
              'accent': const Color(0xFF38BDF8),
              'cardBg': const Color(0xFF0F172A),
            },
            {
              'name': 'Zümrüt Yeşil (Neo Bank)',
              'primary': const Color(0xFF065F46),
              'accent': const Color(0xFF34D399),
              'cardBg': const Color(0xFF064E3B),
            },
            {
              'name': 'Obsidyen Mor (Premium)',
              'primary': const Color(0xFF581C87),
              'accent': const Color(0xFFA855F7),
              'cardBg': const Color(0xFF3B0764),
            },
          ];

    final currentTheme = themes[_activeThemeIndex.clamp(0, themes.length - 1)];
    final primaryColor = currentTheme['primary'] is Color
        ? currentTheme['primary'] as Color
        : _parseColor(currentTheme['primary']?.toString()) ?? const Color(0xFF1E3A8A);
    final accentColor = currentTheme['accent'] is Color
        ? currentTheme['accent'] as Color
        : _parseColor(currentTheme['accent']?.toString()) ?? const Color(0xFF38BDF8);
    final cardBgColor = currentTheme['cardBg'] is Color
        ? currentTheme['cardBg'] as Color
        : _parseColor(currentTheme['cardBg']?.toString()) ?? const Color(0xFF0F172A);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header / Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: GeminiColors.geminiBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.phone_android_rounded,
                      size: 18, color: GeminiColors.geminiCyan),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        appType,
                        style: const TextStyle(
                          color: GeminiColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // Theme picker chips
                if (themes.length > 1) ...[
                  Row(
                    children: List.generate(themes.length, (idx) {
                      final isSelected = idx == _activeThemeIndex;
                      final t = themes[idx];
                      final c = t['primary'] is Color
                          ? t['primary'] as Color
                          : _parseColor(t['primary']?.toString()) ?? Colors.blue;

                      return GestureDetector(
                        onTap: () => setState(() => _activeThemeIndex = idx),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(left: 6),
                          width: isSelected ? 22 : 16,
                          height: isSelected ? 22 : 16,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ],
            ),
          ),

          // Mobil Ekran Çerçevesi (Wireframe / Prototype Mockup)
          Center(
            child: Container(
              width: 320,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF090A0F),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Phone Notch & Status bar
                  Container(
                    height: 28,
                    color: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '09:41',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          width: 60,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1F20),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const Row(
                          children: [
                            Icon(Icons.wifi, size: 11, color: Colors.white),
                            SizedBox(width: 4),
                            Icon(Icons.battery_full, size: 12, color: Colors.white),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // In-App Content
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // App top bar
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Hoş geldiniz 👋',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 10)),
                                Text(
                                  cardHolder,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.notifications_none,
                                  size: 14, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Kredi Kartı / Bakiye Kartı
                        Container(
                          height: 120,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [primaryColor, cardBgColor],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: primaryColor.withValues(alpha: 0.4),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    appName.toUpperCase(),
                                    style: TextStyle(
                                      color: accentColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const Icon(Icons.contactless,
                                      size: 16, color: Colors.white70),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Toplam Varlık',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 9)),
                                  Text(
                                    balance,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    cardNumber,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const Text(
                                    '12/28',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Hızlı İşlem Düğmeleri
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildAppActionButton(Icons.send_rounded, 'Transfer', accentColor),
                            _buildAppActionButton(Icons.qr_code_scanner, 'QR Öde', accentColor),
                            _buildAppActionButton(Icons.account_balance_wallet, 'Yatır', accentColor),
                            _buildAppActionButton(Icons.more_horiz, 'Diğer', accentColor),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Son İşlemler
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Son Hareketler',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Tümü',
                              style: TextStyle(
                                color: GeminiColors.geminiCyan,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _buildTxItem('Market Harcaması', 'Bugün 14:20', '-₺ 420,50', Colors.redAccent),
                        _buildTxItem('Maaş Ödemesi', 'Dün 09:00', '+₺ 65.000,00', Colors.greenAccent),
                      ],
                    ),
                  ),

                  // Phone Bottom Navigation Bar
                  Container(
                    height: 38,
                    color: const Color(0xFF131416),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Icon(Icons.home_filled, size: 16, color: accentColor),
                        const Icon(Icons.credit_card, size: 16, color: Colors.white54),
                        const Icon(Icons.pie_chart, size: 16, color: Colors.white54),
                        const Icon(Icons.person, size: 16, color: Colors.white54),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Actions
          if (widget.component.actions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: UiButtonsWidget(
                actions: widget.component.actions,
                onAction: widget.onAction,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAppActionButton(IconData icon, String label, Color accent) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: accent),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 9),
        ),
      ],
    );
  }

  Widget _buildTxItem(String title, String date, String amount, Color amountColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  amount.startsWith('-') ? Icons.shopping_bag_outlined : Icons.account_balance,
                  size: 12,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 10)),
                  Text(date, style: const TextStyle(color: Colors.white38, fontSize: 8)),
                ],
              ),
            ],
          ),
          Text(
            amount,
            style: TextStyle(
              color: amountColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color? _parseColor(String? hexString) {
    if (hexString == null || hexString.isEmpty) return null;
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return null;
    }
  }
}
