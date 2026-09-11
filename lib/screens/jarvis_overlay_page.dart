import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/jarvis_brain_service.dart';
import '../widgets/jarvis_siri_overlay.dart';

/// Sadece Jarvis panelini gösteren seffaf sayfa.
/// Home tusuna uzun basildiginda acilir - tam uygulama degil.
class JarvisOverlayPage extends StatefulWidget {
  const JarvisOverlayPage({super.key});

  @override
  State<JarvisOverlayPage> createState() => _JarvisOverlayPageState();
}

class _JarvisOverlayPageState extends State<JarvisOverlayPage> {
  @override
  void initState() {
    super.initState();
    // Sayfa acilinca Jarvis overlay'i goster
    WidgetsBinding.instance.addPostFrameCallback((_) {
      JarvisBrainService.instance.showOverlay();
    });

    // Overlay kapaninca bu sayfayi da kapat
    JarvisBrainService.instance.isOverlayVisibleNotifier
        .addListener(_onOverlayVisibilityChanged);
  }

  void _onOverlayVisibilityChanged() {
    if (!JarvisBrainService.instance.isOverlayVisibleNotifier.value) {
      if (mounted) {
        // Activity'yi kapat - arka plana don
        SystemNavigator.pop();
      }
    }
  }

  @override
  void dispose() {
    JarvisBrainService.instance.isOverlayVisibleNotifier
        .removeListener(_onOverlayVisibilityChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ValueListenableBuilder<bool>(
        valueListenable: JarvisBrainService.instance.isOverlayVisibleNotifier,
        builder: (context, isVisible, _) {
          if (!isVisible) return const SizedBox.shrink();
          return JarvisSiriOverlay(
            onClose: () {
              JarvisBrainService.instance.hideOverlay();
            },
          );
        },
      ),
    );
  }
}
