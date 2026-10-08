import 'dart:io';

import 'package:battery_plus/battery_plus.dart';

import '../../phone_control_service.dart';
import '../agent_models.dart';
import '../agent_paths.dart';

/// Telefon/donanım kontrolü: fener, pil, ses, uygulama açma, arama, cihaz bilgisi.
class PhoneTool extends AgentTool {
  PhoneTool({PhoneControlService? phone})
      : _phone = phone ?? PhoneControlService.instance;

  final PhoneControlService _phone;

  @override
  String get name => 'phone';

  @override
  String get description =>
      'Cihazı kontrol eder: flashlight (aç/kapat), battery, volume (yükselt/kıs/sessiz/maksimum), '
      'open_app (whatsapp, youtube, spotify, harita, kamera, mail, chrome), call (numara ara), device_info.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'OBJECT',
        'properties': {
          'action': {
            'type': 'STRING',
            'enum': [
              'flashlight',
              'battery',
              'volume',
              'open_app',
              'call',
              'device_info',
            ],
          },
          'value': {
            'type': 'STRING',
            'description':
                'flashlight: on/off/toggle; volume: up/down/mute/max; open_app: uygulama adı; call: telefon numarası.',
          },
        },
        'required': ['action'],
      };

  @override
  bool get speaksResult => true;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final action = args['action'] as String? ?? 'device_info';
    final value = (args['value'] as String?)?.trim() ?? '';

    switch (action) {
      case 'flashlight':
        final enable = switch (value.toLowerCase()) {
          'on' || 'aç' || 'yak' => true,
          'off' || 'kapat' || 'söndür' => false,
          _ => null,
        };
        return ToolResult(await _phone.toggleFlashlight(enable: enable));
      case 'battery':
        return ToolResult(await _phone.getBatteryInfo());
      case 'volume':
        return ToolResult(await _phone.adjustVolume(value));
      case 'open_app':
        if (value.isEmpty) {
          return ToolResult.error('open_app için value gerekli.');
        }
        return ToolResult(await _phone.openApplication(value));
      case 'call':
        if (value.isEmpty) return ToolResult.error('call için numara gerekli.');
        return ToolResult(await _phone.makePhoneCall(value));
      case 'device_info':
      default:
        final buffer = StringBuffer('platform: ${Platform.operatingSystem} '
            '${Platform.operatingSystemVersion}\n');
        try {
          buffer.writeln('pil: ${await Battery().batteryLevel}%');
        } catch (_) {
          buffer.writeln('pil: okunamadı');
        }
        buffer.writeln(
            'çalışma alanı: ${AgentPathPolicy.instance.effectiveRoot}');
        buffer.write('sınırsız dosya erişimi: '
            '${AgentPathPolicy.instance.allowUnrestrictedPaths ? 'açık' : 'kapalı'}');
        return ToolResult(buffer.toString());
    }
  }
}
