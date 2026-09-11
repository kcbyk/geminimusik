import 'package:dio/dio.dart';

/// Uygulamanın, yetkili bir agent yürütücüsüne bağlanmasını sağlar.
/// Telefonun içinde doğrudan kabuk açmak yerine komut, kullanıcının işlettiği
/// güvenilir bir yerel/uzak yürütücüye gönderilir.
class AgentTerminalService {
  static const _executorUrl =
      String.fromEnvironment('AGENT_EXECUTOR_URL', defaultValue: '');

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 90),
  ));

  bool get isConfigured => _executorUrl.trim().isNotEmpty;

  Future<String> run(String command) async {
    if (!isConfigured) {
      return 'Yürütücü bağlı değil. Güvenli terminal çalıştırmak için uygulamayı '
          '--dart-define=AGENT_EXECUTOR_URL=https://sunucunuz/execute ile başlatın.';
    }
    if (command.trim().isEmpty) return 'Komut boş olamaz.';
    if (command.length > 4000) return 'Komut en fazla 4000 karakter olabilir.';

    try {
      final response = await _dio.post<dynamic>(
        _executorUrl,
        data: {'command': command.trim()},
        options: Options(headers: const {'Content-Type': 'application/json'}),
      );
      final data = response.data;
      if (data is Map) {
        return data['output']?.toString() ??
            data['message']?.toString() ??
            'Komut tamamlandı; yürütücü çıktı döndürmedi.';
      }
      return data?.toString() ?? 'Komut tamamlandı.';
    } on DioException catch (_) {
      return 'Terminal yürütücüsüne ulaşılamadı. Adresi ve bağlantıyı kontrol edin.';
    }
  }
}
