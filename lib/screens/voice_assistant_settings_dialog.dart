import 'package:flutter/material.dart';
import 'package:porcupine_flutter/porcupine.dart';
import '../services/voice_assistant_service.dart';

class VoiceAssistantSettingsDialog extends StatefulWidget {
  const VoiceAssistantSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const VoiceAssistantSettingsDialog(),
    );
  }

  @override
  State<VoiceAssistantSettingsDialog> createState() => _VoiceAssistantSettingsDialogState();
}

class _VoiceAssistantSettingsDialogState extends State<VoiceAssistantSettingsDialog> {
  final _service = VoiceAssistantService.instance;
  late TextEditingController _keyController;
  late bool _isEnabled;
  late BuiltInKeyword _selectedKeyword;

  @override
  void initState() {
    super.initState();
    _isEnabled = _service.isEnabled;
    _selectedKeyword = _service.selectedKeyword;
    _keyController = TextEditingController(text: _service.accessKey);
    _service.addListener(_onServiceUpdate);
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _saveAndApply() async {
    await _service.saveSettings(
      enabled: _isEnabled,
      key: _keyController.text,
      keyword: _selectedKeyword,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEnabled
              ? '✅ Sesli Asistan aktif edildi (${_selectedKeyword.name}).'
              : '⏹️ Sesli Asistan kapatıldı.'),
          backgroundColor: const Color(0xFF1E1F20),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF16181B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: _isEnabled
              ? const Color(0xFF4285F4).withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.08),
          width: 1.2,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Başlık & Kapatma Butonu
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4285F4).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF4285F4).withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Icon(
                      Icons.keyboard_voice_rounded,
                      color: Color(0xFF00E5FF),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Sesli Asistan & Wake-Word',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Kilit ekranında & arka planda müzik çal',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Canlı Durum Kartı
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2228),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _service.isListeningWakeWord || _service.isListeningCommand
                        ? const Color(0xFF00E5FF).withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _service.isListeningWakeWord || _service.isListeningCommand
                            ? const Color(0xFF00E676)
                            : (_isEnabled ? Colors.amber : Colors.grey),
                        boxShadow: [
                          if (_service.isListeningWakeWord || _service.isListeningCommand)
                            BoxShadow(
                              color: const Color(0xFF00E676).withValues(alpha: 0.6),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Durum: ${_service.lastStatus}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_service.lastRecognizedText.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Son algılanan: "${_service.lastRecognizedText}"',
                              style: const TextStyle(
                                color: Color(0xFF00E5FF),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                          if (_service.errorMessage != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              _service.errorMessage!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Anahtar: Asistanı Etkinleştir / Devre Dışı Bırak
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: const Color(0xFF00E5FF),
                activeTrackColor: const Color(0xFF4285F4).withValues(alpha: 0.5),
                inactiveThumbColor: Colors.white38,
                inactiveTrackColor: Colors.white10,
                title: const Text(
                  'Arka Planda Dinleme (Wake-Word)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Uygulama arka plandayken veya telefon kilitliyken sesli komutla şarkı açar.',
                  style: TextStyle(color: Colors.white54, fontSize: 11.5),
                ),
                value: _isEnabled,
                onChanged: (val) => setState(() => _isEnabled = val),
              ),
              const Divider(color: Colors.white12, height: 26),

              // Uyandırma Kelimesi Seçimi
              const Text(
                'Uyandırma Kelimesi (Wake-Word):',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2228),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<BuiltInKeyword>(
                    value: _selectedKeyword,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF22262C),
                    icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF00E5FF)),
                    items: const [
                      DropdownMenuItem(
                        value: BuiltInKeyword.JARVIS,
                        child: Text('Jarvis (Önerilen)', style: TextStyle(color: Colors.white)),
                      ),
                      DropdownMenuItem(
                        value: BuiltInKeyword.PORCUPINE,
                        child: Text('Porcupine', style: TextStyle(color: Colors.white)),
                      ),
                      DropdownMenuItem(
                        value: BuiltInKeyword.BUMBLEBEE,
                        child: Text('Bumblebee', style: TextStyle(color: Colors.white)),
                      ),
                      DropdownMenuItem(
                        value: BuiltInKeyword.HEY_GOOGLE,
                        child: Text('Hey Google', style: TextStyle(color: Colors.white)),
                      ),
                      DropdownMenuItem(
                        value: BuiltInKeyword.ALEXA,
                        child: Text('Alexa', style: TextStyle(color: Colors.white)),
                      ),
                      DropdownMenuItem(
                        value: BuiltInKeyword.COMPUTER,
                        child: Text('Computer', style: TextStyle(color: Colors.white)),
                      ),
                      DropdownMenuItem(
                        value: BuiltInKeyword.TERMINATOR,
                        child: Text('Terminator', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedKeyword = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Picovoice AccessKey Alanı (İsteğe Bağlı)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Icon(Icons.tips_and_updates_outlined, color: Color(0xFF00E5FF), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Siteye giriş yapamıyorsanız veya kayıt olmak istemiyorsanız burayı BOŞ BIRAKABİLİRSİNİZ. Asistan otomatik olarak telefonun dahili ses motoruyla çalışır.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    'Picovoice AccessKey (İsteğe Bağlı):',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'console.picovoice.ai',
                    style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11.5),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _keyController,
                obscureText: true,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'İsteğe bağlı: Boş bırakırsanız Yerel Mod çalışır',
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF1F2228),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Boş bırakırsanız doğrudan telefonun ses motoru kullanılır. Eğer Porcupine ile ultra düşük pil tüketimi isterseniz anahtarınızı girebilirsiniz.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 16),

              // Pil Optimizasyonu İstisnası Butonu
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                icon: const Icon(Icons.battery_charging_full_rounded, size: 18, color: Colors.amber),
                label: const Text(
                  'Pil Kısıtlamasını Kaldır (Arka Plan)',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: () async {
                  await _service.requestBatteryOptimizationException();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Pil optimizasyon ayarı kontrol ediliyor.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 22),

              // Kaydet & Uygula Butonları
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('İptal', style: TextStyle(color: Colors.white54)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: _saveAndApply,
                    child: const Text('Kaydet ve Uygula', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
