import 'package:flutter_test/flutter_test.dart';

import 'package:ai_music_hub/services/agent/turn_model.dart';
import 'package:ai_music_hub/services/gemini_service.dart';

void main() {
  group('Gemini içerik kodlaması', () {
    test('metin part\'ı {"text": ...} biçimine döner', () {
      final content = TurnContent.user(['merhaba']);
      expect(content.toJson(), {
        'role': 'user',
        'parts': [
          {'text': 'merhaba'}
        ],
      });
    });

    test('functionCall / functionResponse part\'ları olduğu gibi geçer', () {
      const call =
          ModelFunctionCall(id: 'c1', name: 'shell', args: {'command': 'ls'});
      final content = TurnContent.model([functionCallPart(call)]);
      final json = content.toJson();
      expect(json['role'], 'model');
      expect((json['parts'] as List).single, {
        'functionCall': {
          'id': 'c1',
          'name': 'shell',
          'args': {'command': 'ls'},
        },
      });
    });

    test('functionResponse ok bayrağını taşır', () {
      final part = functionResponsePart(
        callId: 'c9',
        name: 'read_file',
        output: 'içerik',
        ok: false,
      );
      expect(part['functionResponse'], {
        'id': 'c9',
        'name': 'read_file',
        'response': {'ok': false, 'output': 'içerik'},
      });
    });
  });

  group('araç bildirimleri', () {
    test('boş şema listesi tools alanı üretmez', () {
      expect(buildToolDeclarations(const []), isEmpty);
    });

    test('şemalar function_declarations altına sarılır', () {
      final declarations = buildToolDeclarations([
        {
          'name': 'shell',
          'description': 'kabuk',
          'parameters': {'type': 'OBJECT'},
        },
        {'description': 'adı olmayan şema elenir'},
      ]);
      expect(declarations, hasLength(1));
      final list = declarations.single['function_declarations'] as List;
      expect(list, hasLength(1));
      expect((list.single as Map)['name'], 'shell');
    });
  });

  group('GeminiService yapılandırması', () {
    test('anahtar tanımlanmadığında açık hata verir', () async {
      // Test ortamında --dart-define verilmediği için anahtar listesi boştur:
      // ajan döngüsü sessizce boş yanıt almak yerine bunu görmeli.
      final service = GeminiService();
      expect(
        () => service.sendTurn(
          contents: [
            TurnContent.user(['selam'])
          ],
          systemPrompt: 'test',
        ),
        throwsA(isA<GeminiConfigurationException>()),
      );
    });

    test('GeminiResponse functionCalls taşıyabilir', () {
      const response = GeminiResponse(
        text: '',
        usedKeyLabel: 'gemini-2.5-flash',
        functionCalls: [ModelFunctionCall(id: 'a', name: 'web', args: {})],
        promptTokens: 10,
        completionTokens: 5,
      );
      expect(response.hasFunctionCalls, isTrue);
      expect(response.functionCalls.single.name, 'web');
    });
  });
}
