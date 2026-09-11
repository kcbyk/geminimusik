import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/chat_screen.dart';
import 'screens/music_screen.dart';
import 'screens/agent_screen.dart';
import 'screens/jarvis_overlay_page.dart';
import 'theme/gemini_colors.dart';
import 'widgets/gemini_sparkle.dart';
import 'services/chat_history_service.dart';
import 'services/jarvis_brain_service.dart';
import 'services/voice_assistant_service.dart';
import 'widgets/jarvis_siri_overlay.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GeminiApp());
}

class GeminiApp extends StatelessWidget {
  const GeminiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Google Gemini',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: GeminiColors.background,
        primaryColor: GeminiColors.geminiBlue,
        colorScheme: const ColorScheme.dark(
          primary: GeminiColors.geminiBlue,
          secondary: GeminiColors.geminiPurple,
          surface: GeminiColors.cardBackground,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: GeminiColors.textPrimary),
        ),
      ),
      home: const GeminiMainLayout(),
      routes: {
        '/jarvis_overlay': (context) => const JarvisOverlayPage(),
      },
    );
  }
}

class GeminiMainLayout extends StatefulWidget {
  const GeminiMainLayout({super.key});

  @override
  State<GeminiMainLayout> createState() => _GeminiMainLayoutState();
}

class _GeminiMainLayoutState extends State<GeminiMainLayout> {
  int _currentTabIndex = 0;
  bool _isSidebarOpen = true;
  bool _isNavExpanded = true;
  String? _forwardedSongQuery;
  MusicAutoAction _forwardedAction = MusicAutoAction.none;
  String? _activeSessionId;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    ChatHistoryService.instance.init();
    _setupJarvisChannel();
  }

  void _setupJarvisChannel() {
    const MethodChannel channel = MethodChannel('jarvis_assistant');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'openJarvis') {
        JarvisBrainService.instance.showOverlay();
      }
    });
  }

  @override
  Widget build(BuildContext context) {

    final isDesktopOrWebWide = MediaQuery.of(context).size.width > 768;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: GeminiColors.background,
      // Mobil cihazlar için sol drawer
      drawer: isDesktopOrWebWide ? null : _buildSidebar(isDrawer: true),
      body: Stack(
        children: [
          Row(
            children: [
              // Masaüstü / Web için Daraltılabilir Gemini Sol Menü (Sidebar)
              if (isDesktopOrWebWide && _isSidebarOpen)
                _buildSidebar(isDrawer: false),

              // Ana İçerik Ekranı (Chat veya Music)
              Expanded(
                child: IndexedStack(
                  index: _currentTabIndex,
                  children: [
                    ChatScreen(
                      onOpenSidebar: () {
                        if (isDesktopOrWebWide) {
                          setState(() => _isSidebarOpen = !_isSidebarOpen);
                        } else {
                          _scaffoldKey.currentState?.openDrawer();
                        }
                      },
                      onNavigateToMusicDownload: (song) {
                        setState(() {
                          _forwardedSongQuery = song;
                          _forwardedAction = MusicAutoAction.download;
                          _currentTabIndex = 1;
                        });
                      },
                      onNavigateToMusicPlay: (song) {
                        setState(() {
                          _forwardedSongQuery = song;
                          _forwardedAction = MusicAutoAction.play;
                          _currentTabIndex = 1;
                        });
                      },
                      activeSessionId: _activeSessionId,
                      onSessionChanged: (sessionId, messages) {
                        setState(() {
                          _activeSessionId = sessionId.isEmpty ? null : sessionId;
                        });
                      },
                    ),
                    MusicScreen(
                      key: ValueKey('${_forwardedSongQuery ?? 'gemini_music_tab'}_${_forwardedAction.name}'),
                      initialQuery: _forwardedSongQuery,
                      autoAction: _forwardedAction,
                      onOpenSidebar: () {
                        if (isDesktopOrWebWide) {
                          setState(() => _isSidebarOpen = !_isSidebarOpen);
                        } else {
                          _scaffoldKey.currentState?.openDrawer();
                        }
                      },
                    ),
                    AgentScreen(
                      onOpenSidebar: () {
                        if (isDesktopOrWebWide) {
                          setState(() => _isSidebarOpen = !_isSidebarOpen);
                        } else {
                          _scaffoldKey.currentState?.openDrawer();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 2. JARVIS SIRI OVERLAY (Hey Jarvis veya butona basıldığında açılır)
          ValueListenableBuilder<bool>(
            valueListenable: JarvisBrainService.instance.isOverlayVisibleNotifier,
            builder: (context, isVisible, _) {
              if (!isVisible) return const SizedBox.shrink();
              return Positioned.fill(
                child: JarvisSiriOverlay(
                  onClose: () => JarvisBrainService.instance.hideOverlay(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Orijinal Gemini Web Sol Kenar Çubuğu (Sidebar)
  Widget _buildSidebar({required bool isDrawer}) {
    return Container(
      width: 260,
      color: GeminiColors.sidebarBackground,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Üst Gemini Logo ve Daraltma Butonu
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const GeminiSparkleIcon(size: 22),
                  const SizedBox(width: 10),
                  const Text(
                    'Gemini',
                    style: TextStyle(
                      color: GeminiColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.menu_open, color: GeminiColors.textMuted, size: 20),
                    tooltip: 'Menüyü Kapat',
                    onPressed: () {
                      if (isDrawer) {
                        Navigator.pop(context);
                      } else {
                        setState(() => _isSidebarOpen = false);
                      }
                    },
                  ),
                ],
              ),
            ),

            // Yeni Sohbet Butonu (Gemini tarzı oval hap)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  if (isDrawer) Navigator.pop(context);
                  setState(() {
                    _activeSessionId = null;
                    _currentTabIndex = 0;
                  });
                },

                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF282A2C),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: GeminiColors.border, width: 0.5),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.add, color: GeminiColors.textSecondary, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Yeni sohbet',
                        style: TextStyle(
                          color: GeminiColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Aç/Kapat Toggle Butonu
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _isNavExpanded = !_isNavExpanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _isNavExpanded ? Icons.expand_less : Icons.expand_more,
                        color: GeminiColors.textMuted,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Menü',
                        style: TextStyle(
                          color: GeminiColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Menü Sekmeleri (gizlenebilir)
            if (_isNavExpanded) ...[
              _buildSidebarNavItem(
                icon: Icons.chat_bubble_outline,
                activeIcon: Icons.chat_bubble,
                label: 'Gemini Chat',
                subtitle: 'Sohbet & Proje Fikirleri',
                isSelected: _currentTabIndex == 0,
                onTap: () {
                  if (isDrawer) Navigator.pop(context);
                  setState(() => _currentTabIndex = 0);
                },
              ),
              _buildSidebarNavItem(
                icon: Icons.terminal_outlined,
                activeIcon: Icons.terminal,
                label: 'Agent',
                subtitle: 'Görev planı ve terminal',
                isSelected: _currentTabIndex == 2,
                onTap: () {
                  if (isDrawer) Navigator.pop(context);
                  setState(() => _currentTabIndex = 2);
                },
              ),
              _buildSidebarNavItem(
                icon: Icons.music_note_outlined,
                activeIcon: Icons.music_note,
                label: 'Müzik Hub',
                subtitle: '320kbps MP3 İndirici',
                isSelected: _currentTabIndex == 1,
                onTap: () {
                  if (isDrawer) Navigator.pop(context);
                  setState(() => _currentTabIndex = 1);
                },
              ),
            ],

            const Divider(color: GeminiColors.divider, height: 20, indent: 16, endIndent: 16),

            // Sohbet Geçmişi Başlığı
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: const Text(
                'Sohbet Geçmişi',
                style: TextStyle(
                  color: GeminiColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // Gerçek Sohbet Geçmişi Listesi
            Expanded(
              child: ValueListenableBuilder<List<ChatSession>>(
                valueListenable: ChatHistoryService.instance.sessionsNotifier,
                builder: (context, sessions, _) {
                  if (sessions.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Henüz sohbet yok',
                          style: TextStyle(
                            color: GeminiColors.textMuted,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final isActive = session.id == _activeSessionId;
                      return _buildHistoryItem(session, isActive, isDrawer);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(ChatSession session, bool isActive, bool isDrawer) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF004A77).withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isActive ? Border.all(color: GeminiColors.geminiBlue.withOpacity(0.3)) : null,
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(
          Icons.chat_bubble_outline,
          size: 14,
          color: isActive ? GeminiColors.geminiCyan : GeminiColors.textMuted,
        ),
        title: Text(
          session.title,
          style: TextStyle(
            color: isActive ? Colors.white : GeminiColors.textSecondary,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        subtitle: Text(
          _formatDate(session.createdAt),
          style: const TextStyle(color: GeminiColors.textMuted, fontSize: 10),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () {
          if (isDrawer) Navigator.pop(context);
          setState(() {
            _activeSessionId = session.id;
            _currentTabIndex = 0;
          });
        },
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 14, color: GeminiColors.textMuted),
          tooltip: 'Sil',
          onPressed: () async {
            await ChatHistoryService.instance.deleteSession(session.id);
            if (_activeSessionId == session.id) {
              setState(() {
                _activeSessionId = null;
              });
            }
          },
        ),
      ),
    );
  }


  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Az önce';
    if (diff.inHours < 1) return '${diff.inMinutes}dk önce';
    if (diff.inDays < 1) return '${diff.inHours}sa önce';
    if (diff.inDays < 7) return '${diff.inDays}g önce';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Widget _buildSidebarNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF004A77).withOpacity(0.3) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected ? Border.all(color: GeminiColors.geminiBlue.withOpacity(0.5)) : null,
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? GeminiColors.geminiCyan : GeminiColors.textMuted,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : GeminiColors.textSecondary,
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: GeminiColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
