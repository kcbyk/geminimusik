import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../models/chat_message.dart';

class GeminiResponse {
  final String text;
  final String usedKeyLabel;

  GeminiResponse({required this.text, required this.usedKeyLabel});
}

class GeminiService {
  static final List<String> _apiKeys = [
    utf8.decode(base64Decode('QVEuQWI4Uk42Si05R2t0RXE1WWRoQ1QwdlZlUC0wZkVSZlJrTzFyTVE0cVFDRzByLVc3dGc=')), // Primary Key
    utf8.decode(base64Decode('QVEuQWI4Uk42SW4ydXpDa0kxWGZzQllocHNZbkNlYjBWZDVadC1sUTljZjQ1ZHBYNUd2OUE=')), // Backup Key 1
    utf8.decode(base64Decode('QVEuQWI4Uk42TEZjeFYzMkJBb19ZZ21QdEw3ZWE3dk1qbUszemVIV3p3ZUNoSnhveVdLYmc=')), // Backup Key 2
    utf8.decode(base64Decode('QVEuQWI4Uk42TFY5WlJuaFpTNG5zdFM3RVNsMDlnM3ZnSXlicGF6anVmS1ZUaUEzU2tuTWc=')), // Backup Key 3
    utf8.decode(base64Decode('QVEuQWI4Uk42SUQ4SEVfaUozMXBLRi03WEQ4ZlJ3MDQ0Ri1Hc25Sa0ZEaFJZR0U0aXVVUXc=')), // Backup Key 4
  ];

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 40),
    ),
  );

  static const String _systemPrompt = '''
Sen kullanıcıya yazılım, teknoloji, proje fikirleri, müzik ve günlük konularda yardımcı olan üst düzey bir yapay zeka asistanısın.

MÜZİK VE ŞARKI KOMUTLARI:
1. Kullanıcı bir şarkıyı indirmek istediğinde (örn: "şu şarkıyı indir", "kuzu kuzu indir", "mp3 indir"):
Cevabının en sonuna mutlaka şu formatta bir eylem etiketi ekle:
[ACTION:DOWNLOAD:Şarkı Adı ve Sanatçı]
Örnek: Harika bir seçim! Tarkan'ın Kuzu Kuzu şarkısını hemen indiriyorum.
[ACTION:DOWNLOAD:Tarkan Kuzu Kuzu]

2. Kullanıcı bir şarkıyı dinlemek / açmak / çalmak istediğinde (örn: "şu şarkıyı aç", "şarkıyı çal", "tarkan aç", "dinle"):
Cevabının en sonuna mutlaka şu formatta bir eylem etiketi ekle:
[ACTION:PLAY:Şarkı Adı ve Sanatçı]
Örnek: Elbette, hemen Tarkan - Kuzu Kuzu çalmaya başlıyor!
[ACTION:PLAY:Tarkan Kuzu Kuzu]

3. Kullanıcı müziği durdurmak / kapatmak / kesmek istediğinde (örn: "kapat", "durdur", "müziği kes", "şarkıyı kapat"):
Cevabının en sonuna mutlaka şu etiketi ekle:
[ACTION:STOP]
Örnek: Tamam, müziği durduruyorum!
[ACTION:STOP]

4. Kullanıcı çalan müziğin oynatıcısını/panelini gizlemek veya küçültmek istediğinde (müzik arka planda çalmaya devam ederken):
Cevabının en sonuna mutlaka şu etiketi ekle:
[ACTION:HIDE_PLAYER]
Örnek: Oynatıcıyı gizledim, müzik arka planda çalmaya devam ediyor!
[ACTION:HIDE_PLAYER]

5. Kullanıcı gizlenen oynatıcıyı tekrar açmak veya göstermek istediğinde:
Cevabının en sonuna mutlaka şu etiketi ekle:
[ACTION:SHOW_PLAYER]
Örnek: Oynatıcıyı tekrar açtım!
[ACTION:SHOW_PLAYER]

6. CANLI İNTERNET VE WEB ARAMASI (GÜNCEL BİLGİLER):
Sen canlı internete erişebilen bir yapay zekasın. Eğer kullanıcı güncel bir bilgi (döviz, altın, kripto kurları, son dakika haberleri, maç sonuçları, vizyondaki filmler, bugünün hava durumu, son gelişmeler veya belirli kişiler, sanatçılar, rapçiler veya bilgi dağarcığını aşan taze internet bilgisi) sorarsa veya "internetten bak", "webde ara", "kimdir", "haberler ne" gibi bir istekte bulunursa:
Cevabında YALNIZCA şu formatta arama komutunu ver (başka hiçbir metin ekleme):
[ACTION:SEARCH:arama terimi]
ÖNEMLİ ARAMA TERİMİ KURALLARI:
- Arama terimini genel ve gereksiz eklerden arındır, arama motorunun en iyi sonucu bulabileceği anahtar kelimeleri seç.
- Kişi veya sanatçı soruluyorsa mesleğini veya bilinen alanını da ekle (Örn: "wegh kimdir" -> [ACTION:SEARCH:wegh rapci kimdir], "lvbel c5 kimdir" -> [ACTION:SEARCH:lvbel c5 rapci kimdir]).
- Döviz/altın için: "Dolar bugün kaç TL?" -> [ACTION:SEARCH:dolar kuru bugun canli]
- Maç için: "Galatasaray maçı ne oldu?" -> [ACTION:SEARCH:galatasaray son mac sonucu]

ÖNEMLİ: Eğer sana kullanıcı mesajında [WEB_ARAMA_SONUCLARI] verildiyse, artık SEARCH etiketi üretme!
- Sağlanan web verilerindeki kaynakları dikkatlice oku.
- Kullanıcının asıl sorduğu kişi, konu veya olayı web verilerinden ayıkla (Örneğin Wegh sorulduğunda demiryolu şirketi veya radyo istasyonu değil, Türk rapçi/müzisyen Wegh ile ilgili bilgileri ön plana çıkar).
- Soruyu doğrudan, en güncel, net ve akıcı şekilde yanıtla.
- Döviz, altın veya borsa gibi finansal verilerde; sayfadaki 'Önceki Kapanış', 'Alış', 'Satış' veya 'Anlık Piyasa' gibi farklı rakamları birbirine karıştırma. Tek fiyat söyleyeceksen güncel anlık satış fiyatını net bir şekilde aktar.

7. Kullanıcı proje fikri istediğinde:
- Projenin amacını, hedef kitlesini
- Kullanılabilecek ideal teknoloji yığınını (Frontend, Backend, DB, AI)
- Temel ve fark yaratıcı benzersiz özellikleri (MVP kapsamı)
- Geliştirme aşamalarını adım adım ve ilham verici bir üslupla sun.
''';

  /// Mesaj gönderir ve çoklu anahtar (fallback) sistemini çalıştırır
  Future<GeminiResponse> sendMessage({
    required String prompt,
    required List<ChatMessage> history,
    String model = 'gemini-2.5-flash',
    Uint8List? imageBytes,
    String? mimeType,
  }) async {
    // Gemini API formatında conversation context'i oluştur
    final contents = <Map<String, dynamic>>[];

    // Oturumdaki önceki mesajları context olarak ekle (en fazla son 20 mesaj)
    final recentHistory = history.length > 20 ? history.sublist(history.length - 20) : history;
    for (final msg in recentHistory) {
      final parts = <Map<String, dynamic>>[];
      if (msg.imageBytes != null && msg.isUser) {
        parts.add({
          'inline_data': {
            'mime_type': msg.imageMimeType ?? 'image/jpeg',
            'data': base64Encode(msg.imageBytes!),
          }
        });
      }
      if (msg.content.isNotEmpty) {
        parts.add({'text': msg.content});
      }
      if (parts.isNotEmpty) {
        contents.add({
          'role': msg.isUser ? 'user' : 'model',
          'parts': parts,
        });
      }
    }

    // Yeni kullanıcı mesajını ve varsa görselini ekle
    final userParts = <Map<String, dynamic>>[];
    if (imageBytes != null) {
      userParts.add({
        'inline_data': {
          'mime_type': mimeType ?? 'image/jpeg',
          'data': base64Encode(imageBytes),
        }
      });
    }
    userParts.add({
      'text': prompt.isEmpty ? 'Bu görseli detaylı açıkla ve analiz et.' : prompt,
    });

    contents.add({
      'role': 'user',
      'parts': userParts,
    });

    final requestBody = {
      'system_instruction': {
        'parts': [
          {'text': _systemPrompt}
        ]
      },
      'contents': contents,
      'generationConfig': {
        'temperature': 0.75,
        'maxOutputTokens': 2048,
      }
    };

    dynamic lastError;

    // API anahtarlarını sırayla dene (Fallback mantığı)
    for (int i = 0; i < _apiKeys.length; i++) {
      final apiKey = _apiKeys[i];
      final keyLabel = '$model (Key ${i + 1})';
      final url =
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';

      try {
        final response = await _dio.post(
          url,
          options: Options(headers: {'Content-Type': 'application/json'}),
          data: jsonEncode(requestBody),
        );

        if (response.statusCode == 200 && response.data != null) {
          final candidates = response.data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'];
            final parts = content['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              final replyText = parts[0]['text'] as String? ?? '';
              return GeminiResponse(text: replyText.trim(), usedKeyLabel: keyLabel);
            }
          }
        }
      } catch (e) {
        lastError = e;
        // İlk key başarısız olursa (rate limit, quota vb.) döngü sonraki yedek key'e devam eder
      }
    }

    throw Exception(
        'Tüm Gemini API anahtarları denendi fakat yanıt alınamadı. Hata: $lastError');
  }
}
