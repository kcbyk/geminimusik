import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/jarvis_brain_service.dart';
import '../services/jarvis_tts_service.dart';

class JarvisSiriOverlay extends StatefulWidget {
  final VoidCallback? onClose;
  const JarvisSiriOverlay({super.key, this.onClose});

  @override
  State<JarvisSiriOverlay> createState() => _JarvisSiriOverlayState();
}

class _JarvisSiriOverlayState extends State<JarvisSiriOverlay>
    with TickerProviderStateMixin {
  late AnimationController _orbAnimController;
  late AnimationController _waveAnimController;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isSpeechInitialized = false;
  bool _isListening = false;
  String _liveSpeechText = '';

  final brain = JarvisBrainService.instance;

  @override
  void initState() {
    super.initState();

    _orbAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _waveAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _startListeningFlow();
  }

  Future<void> _startListeningFlow() async {
    try {
      if (!_isSpeechInitialized) {
        _isSpeechInitialized = await _speech.initialize(
          onStatus: (status) {
            if (status == 'done' || status == 'notListening') {
              if (mounted && _liveSpeechText.isNotEmpty && _isListening) {
                _onSpeechComplete();
              }
            }
          },
          onError: (val) {
            debugPrint('[JarvisOverlay] STT hatası: ${val.errorMsg}');
          },
        );
      }

      if (_isSpeechInitialized) {
        setState(() {
          _isListening = true;
          _liveSpeechText = '';
        });
        brain.statusNotifier.value = JarvisStatus.listening;

        await _speech.listen(
          listenOptions: stt.SpeechListenOptions(
            localeId: 'tr_TR',
            listenFor: const Duration(seconds: 15),
            pauseFor: const Duration(seconds: 3),
          ),
          onResult: (val) {
            if (mounted) {
              setState(() {
                _liveSpeechText = val.recognizedWords;
              });
              brain.userSpeechNotifier.value = val.recognizedWords;
            }
          },
        );
      }
    } catch (e) {
      debugPrint('[JarvisOverlay] Dinleme başlatılamadı: $e');
    }
  }

  void _onSpeechComplete() {
    _speech.stop();
    setState(() => _isListening = false);
    if (_liveSpeechText.trim().isNotEmpty) {
      brain.processCommand(_liveSpeechText.trim());
    }
  }

  void _toggleListening() {
    if (_isListening) {
      _onSpeechComplete();
    } else {
      _startListeningFlow();
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _orbAnimController.dispose();
    _waveAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Yarı saydam arka plan karartısı (dokunulduğunda kapanır)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                brain.hideOverlay();
                widget.onClose?.call();
              },
              child: Container(
                color: Colors.black.withValues(alpha: 0.65),
              ),
            ),
          ),

          // Siri Tarzı Alt Panel (Frosted Glass & Glowing Effect)
          SafeArea(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF16181D).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00F2FE).withValues(alpha: 0.18),
                    blurRadius: 36,
                    spreadRadius: 2,
                    offset: const Offset(0, -6),
                  ),
                  BoxShadow(
                    color: const Color(0xFF9B51E0).withValues(alpha: 0.22),
                    blurRadius: 42,
                    spreadRadius: 4,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Üst Bar: Kapatma Butonu & Asistan Başlığı
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF00F2FE),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xFF00F2FE),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'J.A.R.V.I.S.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          brain.hideOverlay();
                          widget.onClose?.call();
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Kullanıcının Söylediği Metin (Canlı)
                  ValueListenableBuilder<String>(
                    valueListenable: brain.userSpeechNotifier,
                    builder: (context, userText, _) {
                      final displayText = _liveSpeechText.isNotEmpty
                          ? _liveSpeechText
                          : (userText.isNotEmpty ? userText : 'Sizi dinliyorum efendim...');
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          displayText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _liveSpeechText.isNotEmpty || userText.isNotEmpty
                                ? Colors.white
                                : Colors.white54,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Siri Tarzı Büyüleyici Glowing Orb & Ses Dalgaları
                  GestureDetector(
                    onTap: _toggleListening,
                    child: _buildSiriGlowingOrb(),
                  ),

                  const SizedBox(height: 16),

                  // Jarvis'in Yanıtı ve TTS Göstergesi
                  ValueListenableBuilder<String>(
                    valueListenable: brain.jarvisResponseNotifier,
                    builder: (context, response, _) {
                      if (response.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1015),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                color: Color(0xFF00F2FE),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  response,
                                  style: const TextStyle(
                                    color: Color(0xFFECEFF1),
                                    fontSize: 14.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              ValueListenableBuilder<bool>(
                                valueListenable: JarvisTtsService.instance.isSpeakingNotifier,
                                builder: (context, isSpeaking, _) {
                                  if (!isSpeaking) return const SizedBox.shrink();
                                  return Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFF1E222B),
                                    ),
                                    child: const Icon(
                                      Icons.volume_up_rounded,
                                      color: Color(0xFF00F2FE),
                                      size: 16,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // Hızlı Komut Önerileri (Pill Buttons)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildQuickActionChip('🔦 Feneri Aç', () => brain.processCommand('feneri aç')),
                        const SizedBox(width: 8),
                        _buildQuickActionChip('🔋 Pil Durumu', () => brain.processCommand('pil durumu')),
                        const SizedBox(width: 8),
                        _buildQuickActionChip('💬 WhatsApp Aç', () => brain.processCommand('whatsapp aç')),
                        const SizedBox(width: 8),
                        _buildQuickActionChip('▶️ YouTube Aç', () => brain.processCommand('youtube aç')),
                        const SizedBox(width: 8),
                        _buildQuickActionChip('🎵 Tarkan Çal', () => brain.processCommand('tarkan çal')),
                        const SizedBox(width: 8),
                        _buildQuickActionChip('🔊 Sesi Fulle', () => brain.processCommand('sesi fulle')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Siri Tarzı Parlayan Canlı Küre (Glowing Siri Orb)
  Widget _buildSiriGlowingOrb() {
    return AnimatedBuilder(
      animation: Listenable.merge([_orbAnimController, _waveAnimController]),
      builder: (context, _) {
        final rot = _orbAnimController.value * 2 * math.pi;
        final pulse = 1.0 + (_waveAnimController.value * 0.12);

        return Stack(
          alignment: Alignment.center,
          children: [
            // Arka Parlama Halesi (Outer Glow)
            Container(
              width: 110 * pulse,
              height: 110 * pulse,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00F2FE).withValues(alpha: 0.4),
                    const Color(0xFF9B51E0).withValues(alpha: 0.25),
                    Colors.transparent,
                  ],
                  stops: const [0.2, 0.6, 1.0],
                ),
              ),
            ),

            // Dönen Siri Küresi
            Transform.rotate(
              angle: rot,
              child: Container(
                width: 76 * pulse,
                height: 76 * pulse,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const SweepGradient(
                    colors: [
                      Color(0xFF00F2FE),
                      Color(0xFF4FACFE),
                      Color(0xFF9B51E0),
                      Color(0xFFFF0844),
                      Color(0xFF00F2FE),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00F2FE).withValues(alpha: 0.6),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),

            // İç Merkez Kristali / Mikrofon İkonu
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0F1015).withValues(alpha: 0.88),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
              ),
              child: Icon(
                _isListening ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                color: _isListening ? const Color(0xFF00F2FE) : Colors.white,
                size: 26,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickActionChip(String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFE0E0E0),
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
