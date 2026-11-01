import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_music_hub/models/generative_ui/ui_component_model.dart';
import 'package:ai_music_hub/services/generative_ui/generative_ui_parser.dart';
import 'package:ai_music_hub/widgets/generative_ui/generative_message_view.dart';
import 'package:ai_music_hub/widgets/generative_ui/generative_ui_renderer.dart';
import 'package:ai_music_hub/widgets/generative_ui/components/ui_app_mockup_widget.dart';
import 'package:ai_music_hub/widgets/generative_ui/components/ui_color_palette_widget.dart';
import 'package:ai_music_hub/widgets/generative_ui/components/ui_form_widget.dart';

void main() {
  group('GenerativeUiParser Tests', () {
    test('Düz metin mesajlarını yalnızca TextSegment olarak ayıklar', () {
      const text = 'Merhaba! Size nasıl yardımcı olabilirim?';
      final segments = GenerativeUiParser.parse(text);

      expect(segments.length, 1);
      expect(segments.first, isA<TextSegment>());
      expect((segments.first as TextSegment).text, text);
    });

    test('```ui ... ``` bloğunu GenerativeUiSegment olarak çözümler', () {
      const content = '''
İşte istediğiniz kart:
```ui
{
  "type": "card",
  "title": "Finans Uygulaması",
  "description": "Modern banka paneli",
  "badge": "Yeni"
}
```
Başka bir işlem yapmak ister misiniz?
''';

      final segments = GenerativeUiParser.parse(content);
      expect(segments.length, 3);
      expect(segments[0], isA<TextSegment>());
      expect(segments[1], isA<GenerativeUiSegment>());
      expect(segments[2], isA<TextSegment>());

      final ui = (segments[1] as GenerativeUiSegment).component;
      expect(ui.type, 'card');
      expect(ui.title, 'Finans Uygulaması');
      expect(ui.description, 'Modern banka paneli');
      expect(ui.data['badge'], 'Yeni');
    });

    test('Bozuk JSON içeren UI bloğunda çökmez, güvenli fallback üretir', () {
      const content = '''
```ui
{ "type": "card", title: bozuk_json }
```
''';
      final segments = GenerativeUiParser.parse(content);
      expect(segments.isNotEmpty, true);
      expect(segments.first, isA<TextSegment>());
    });

    test('Saf JSON mesajını doğrudan Generative UI olarak çözümler', () {
      const jsonStr = '''
{
  "type": "app_mockup",
  "title": "Neo Bank",
  "appName": "Neo Bank Pro",
  "balance": "₺ 150.000,00"
}
''';
      final segments = GenerativeUiParser.parse(jsonStr);
      expect(segments.length, 1);
      expect(segments.first, isA<GenerativeUiSegment>());
      final ui = (segments.first as GenerativeUiSegment).component;
      expect(ui.type, 'app_mockup');
      expect(ui.title, 'Neo Bank');
    });

    test('Modern banka uygulaması tasarımı çoklu UI bloklarını doğru sıralar', () {
      const bankResponse = '''
Sizin için modern bir banka uygulaması tasarımı hazırladım:

```ui
{
  "type": "app_mockup",
  "title": "NovaBank Mobil",
  "balance": "₺ 250.000",
  "cardHolder": "SENOL K.",
  "actions": [
    {"type": "prompt", "label": "Karanlık Mod", "value": "Karanlık mod detayları"}
  ]
}
```

Uygulamanın kurumsal renk paleti:
```ui
{
  "type": "color_palette",
  "title": "Fintech Renk Uyumu",
  "colors": [
    {"hex": "#1E3A8A", "name": "Lacivert", "role": "Primary"},
    {"hex": "#38BDF8", "name": "Açık Mavi", "role": "Accent"}
  ]
}
```
''';
      final segments = GenerativeUiParser.parse(bankResponse);
      expect(segments.length, 4);
      expect(segments[0], isA<TextSegment>());
      expect(segments[1], isA<GenerativeUiSegment>());
      expect(segments[2], isA<TextSegment>());
      expect(segments[3], isA<GenerativeUiSegment>());

      final comp1 = (segments[1] as GenerativeUiSegment).component;
      expect(comp1.type, 'app_mockup');
      expect(comp1.actions.length, 1);

      final comp2 = (segments[3] as GenerativeUiSegment).component;
      expect(comp2.type, 'color_palette');
    });
  });

  group('Generative UI Widget Render & Etkileşim Testleri', () {
    testWidgets('UiAppMockupWidget ekranda telefon çerçevesini ve bakiyeyi gösterir', (tester) async {
      const comp = UiComponent(
        type: 'app_mockup',
        title: 'Banka Paneli',
        data: {
          'appName': 'NeoBank',
          'balance': '₺ 99.999,00',
          'cardHolder': 'CANBERK YILMAZ',
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UiAppMockupWidget(component: comp),
          ),
        ),
      );

      expect(find.text('NeoBank'), findsWidgets);
      expect(find.text('₺ 99.999,00'), findsOneWidget);
      expect(find.text('CANBERK YILMAZ'), findsOneWidget);
    });

    testWidgets('UiColorPaletteWidget renk kutularını ve hex kodlarını listeler', (tester) async {
      const comp = UiComponent(
        type: 'color_palette',
        title: 'Palet',
        data: {
          'colors': [
            {'hex': '#1E3A8A', 'name': 'Derin Lacivert', 'role': 'Primary'},
            {'hex': '#38BDF8', 'name': 'Camgöbeği', 'role': 'Accent'},
          ],
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UiColorPaletteWidget(component: comp),
          ),
        ),
      );

      expect(find.text('Palet'), findsOneWidget);
      expect(find.text('Derin Lacivert'), findsOneWidget);
      expect(find.text('#1E3A8A'), findsOneWidget);
    });

    testWidgets('UiComparisonWidget alternatifleri ve seçim butonlarını gösterir', (tester) async {
      String? selectedPrompt;

      const comp = UiComponent(
        type: 'comparison',
        title: 'Tasarım Kıyaslama',
        data: {
          'items': [
            {
              'title': 'Minimalist',
              'features': ['Hızlı erişim'],
              'action': {
                'type': 'prompt',
                'label': 'Minimalist Seç',
                'value': 'Minimalist tasarımı seçtim',
              },
            },
          ],
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GenerativeUiRenderer(
              component: comp,
              onActionPrompt: (p) => selectedPrompt = p,
            ),
          ),
        ),
      );

      expect(find.text('Tasarım Kıyaslama'), findsOneWidget);
      expect(find.text('Minimalist'), findsOneWidget);
      expect(find.text('Minimalist Seç'), findsOneWidget);

      await tester.tap(find.text('Minimalist Seç'));
      await tester.pump();

      expect(selectedPrompt, 'Minimalist tasarımı seçtim');
    });

    testWidgets('UiFormWidget veri toplayıp onSubmit çağrısını tetikler', (tester) async {
      Map<String, dynamic>? submittedData;
      String? submittedPrompt;

      const comp = UiComponent(
        type: 'form',
        title: 'Geri Bildirim',
        data: {
          'submitText': 'Tamamla',
          'fields': [
            {
              'name': 'username',
              'label': 'Adınız',
              'type': 'text',
              'placeholder': 'Adınızı girin',
            },
            {
              'name': 'experience',
              'label': 'Deneyim',
              'type': 'select',
              'options': ['Harika', 'Orta', 'Kötü'],
            },
          ],
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UiFormWidget(
              component: comp,
              onSubmit: (data, prompt) {
                submittedData = data;
                submittedPrompt = prompt;
              },
            ),
          ),
        ),
      );

      expect(find.text('Geri Bildirim'), findsOneWidget);
      expect(find.text('Adınız'), findsOneWidget);

      // Ad gir
      await tester.enterText(find.byType(TextField), 'Ahmet');
      await tester.pump();

      // Gönder butonuna tıkla
      await tester.tap(find.text('Tamamla'));
      await tester.pump();

      expect(submittedData, isNotNull);
      expect(submittedData!['username'], 'Ahmet');
      expect(submittedPrompt, contains('Ahmet'));
    });

    testWidgets('GenerativeMessageView hem metni hem UI bileşenlerini birlikte render eder', (tester) async {
      const message = '''
Merhabalar! İşte istediğiniz dashboard:

```ui
{
  "type": "chart",
  "title": "Haftalık İstatistikler",
  "metrics": [
    {"label": "Kullanıcı", "value": "12.450"}
  ],
  "series": [
    {"label": "Pzt", "value": 100},
    {"label": "Sal", "value": 200}
  ]
}
```

Devam etmek ister misiniz?
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GenerativeMessageView(
                content: message,
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('İşte istediğiniz dashboard'), findsOneWidget);
      expect(find.text('Haftalık İstatistikler'), findsOneWidget);
      expect(find.text('12.450'), findsOneWidget);
      expect(find.textContaining('Devam etmek ister misiniz?'), findsOneWidget);
    });

    testWidgets('UiGalleryWidget ve UiProductCardWidget sorunsuz render edilir', (tester) async {
      const galleryComp = UiComponent(
        type: 'gallery',
        title: 'Örnek Galeri',
        data: {
          'images': [
            {'url': 'https://example.com/img1.jpg', 'caption': 'Foto 1'},
            {'url': 'https://example.com/img2.jpg', 'caption': 'Foto 2'},
          ],
        },
      );

      const productComp = UiComponent(
        type: 'product_card',
        title: 'Akıllı Saat Pro',
        description: 'Tüm gün sağlık takibi ve AMOLED ekran',
        data: {
          'price': '4.999',
          'currency': '₺',
          'rating': 4.8,
          'badge': '%20 İndirim',
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  GenerativeUiRenderer(component: galleryComp),
                  GenerativeUiRenderer(component: productComp),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Örnek Galeri'), findsOneWidget);
      expect(find.text('Akıllı Saat Pro'), findsOneWidget);
      expect(find.text('4.999 ₺'), findsOneWidget);
      expect(find.text('%20 İndirim'), findsOneWidget);
    });

    testWidgets('UiProgressWidget, UiAccordionWidget ve UiMapWidget render edilir', (tester) async {
      const progressComp = UiComponent(
        type: 'progress',
        title: 'Geliştirme Süreci',
        data: {
          'steps': [
            {'title': 'Tasarım', 'status': 'completed'},
            {'title': 'Kodlama', 'status': 'active'},
            {'title': 'Test', 'status': 'pending'},
          ],
        },
      );

      const accordionComp = UiComponent(
        type: 'accordion',
        title: 'Sıkça Sorulan Sorular',
        data: {
          'items': [
            {'title': 'Kredi kartı aidatı var mı?', 'content': 'Hayır, aidatsız kart sunulmaktadır.'},
          ],
        },
      );

      const mapComp = UiComponent(
        type: 'map',
        title: 'Genel Merkez Şubesi',
        data: {
          'address': 'Levent, Büyükdere Cad. No:190 İstanbul',
          'lat': 41.08,
          'lng': 29.01,
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  GenerativeUiRenderer(component: progressComp),
                  GenerativeUiRenderer(component: accordionComp),
                  GenerativeUiRenderer(component: mapComp),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Geliştirme Süreci'), findsOneWidget);
      expect(find.text('Tasarım'), findsOneWidget);
      expect(find.text('Kodlama'), findsOneWidget);
      expect(find.text('Sıkça Sorulan Sorular'), findsOneWidget);
      expect(find.text('Kredi kartı aidatı var mı?'), findsOneWidget);
      expect(find.text('Genel Merkez Şubesi'), findsWidgets);
      expect(find.text('Haritada Aç'), findsOneWidget);
    });
  });
}
