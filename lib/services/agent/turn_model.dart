/// Gemini'nin **native function calling** protokolünün saf Dart modeli.
///
/// Bu dosya bilerek Flutter'a bağımlı değildir: ajan döngüsü, araç kayıt
/// defteri ve testler `flutter test` olmadan da çalışabilsin diye.
library;

/// Modelin bir turda ürettiği tek bir araç çağrısı.
class ModelFunctionCall {
  final String id;
  final String name;
  final Map<String, dynamic> args;

  const ModelFunctionCall({
    required this.id,
    required this.name,
    required this.args,
  });

  @override
  String toString() => '$name(${args.keys.join(', ')})';
}

/// Modelden dönen bir tur: ya metin, ya araç çağrısı(ları), ya ikisi.
class ModelTurn {
  final String text;
  final List<ModelFunctionCall> calls;
  final int promptTokens;
  final int completionTokens;

  const ModelTurn({
    this.text = '',
    this.calls = const [],
    this.promptTokens = 0,
    this.completionTokens = 0,
  });

  bool get hasCalls => calls.isNotEmpty;
  int get totalTokens => promptTokens + completionTokens;
}

/// Sohmet geçmişindeki tek bir içerik bloğu (Gemini `content` nesnesi).
class TurnContent {
  /// 'user' | 'model'
  final String role;

  /// String -> `[{'text': ...}]`, Map -> doğrudan part (functionCall /
  /// functionResponse / inline_data).
  final List<dynamic> parts;

  TurnContent.user(this.parts) : role = 'user';
  TurnContent.model(this.parts) : role = 'model';

  Map<String, dynamic> toJson() => {
        'role': role,
        'parts': parts.map((part) {
          if (part is String) return {'text': part};
          if (part is Map) return Map<String, dynamic>.from(part);
          return {'text': part.toString()};
        }).toList(),
      };
}

/// Gemini `tools` alanı için function declaration listesi üretir.
List<Map<String, dynamic>> buildToolDeclarations(
  Iterable<Map<String, dynamic>> schemas,
) {
  final declarations = schemas.where((s) => s['name'] != null).toList();
  if (declarations.isEmpty) return const [];
  return [
    {'function_declarations': declarations},
  ];
}

/// Model çağrısı için functionCall part'ı.
Map<String, dynamic> functionCallPart(ModelFunctionCall call) => {
      'functionCall': {
        'id': call.id,
        'name': call.name,
        'args': call.args,
      },
    };

/// Araç sonucunu modele geri göndermek için functionResponse part'ı.
Map<String, dynamic> functionResponsePart({
  required String callId,
  required String name,
  required String output,
  bool ok = true,
}) =>
    {
      'functionResponse': {
        'id': callId,
        'name': name,
        'response': {
          'ok': ok,
          'output': output,
        },
      },
    };

/// Araç çıktısını modele göndermeden önce kısaltır. Uzun `ls`/dosya çıktıları
/// bağlam penceresini bir turda doldurmasın diye.
String truncateToolOutput(String value, {int maxChars = 12000}) {
  if (value.length <= maxChars) return value;
  final head = value.substring(0, (maxChars * 0.7).round());
  final tail = value.substring(value.length - (maxChars * 0.2).round());
  final skipped = value.length - head.length - tail.length;
  return '$head\n\n… [ortadan $skipped karakter kısaltıldı] …\n\n$tail';
}
