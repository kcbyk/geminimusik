import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/generative_ui/ui_action_model.dart';
import '../../models/generative_ui/ui_component_model.dart';
import 'components/ui_accordion_widget.dart';
import 'components/ui_app_mockup_widget.dart';
import 'components/ui_buttons_widget.dart';
import 'components/ui_card_widget.dart';
import 'components/ui_chart_widget.dart';
import 'components/ui_code_block_widget.dart';
import 'components/ui_color_palette_widget.dart';
import 'components/ui_comparison_widget.dart';
import 'components/ui_dashboard_widget.dart';
import 'components/ui_form_widget.dart';
import 'components/ui_gallery_widget.dart';
import 'components/ui_map_widget.dart';
import 'components/ui_product_card_widget.dart';
import 'components/ui_progress_widget.dart';
import 'components/ui_table_widget.dart';

class GenerativeUiRenderer extends StatelessWidget {
  final UiComponent component;
  final void Function(String prompt)? onActionPrompt;
  final void Function(String text)? onActionCopy;
  final void Function(String url)? onActionUrl;
  final void Function(Map<String, dynamic> data, String promptText)? onFormSubmit;

  const GenerativeUiRenderer({
    super.key,
    required this.component,
    this.onActionPrompt,
    this.onActionCopy,
    this.onActionUrl,
    this.onFormSubmit,
  });

  void _handleAction(BuildContext context, UiAction action) async {
    switch (action.type) {
      case 'prompt':
        final p = action.value ?? action.label;
        onActionPrompt?.call(p);
        break;
      case 'url':
        final urlStr = action.value ?? '';
        if (urlStr.isNotEmpty) {
          final uri = Uri.tryParse(urlStr);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
        onActionUrl?.call(urlStr);
        break;
      case 'copy':
        final text = action.value ?? action.label;
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$text kopyalandı'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
        onActionCopy?.call(text);
        break;
      case 'select':
      default:
        if (action.value != null && action.value!.isNotEmpty) {
          onActionPrompt?.call(action.value!);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildComponent(context, component);
  }

  Widget _buildComponent(BuildContext context, UiComponent comp) {
    switch (comp.type) {
      case 'card':
        return UiCardWidget(
          component: comp,
          onAction: (act) => _handleAction(context, act),
        );
      case 'gallery':
        return UiGalleryWidget(component: comp);
      case 'product_card':
        return UiProductCardWidget(
          component: comp,
          onAction: (act) => _handleAction(context, act),
        );
      case 'app_mockup':
        return UiAppMockupWidget(
          component: comp,
          onAction: (act) => _handleAction(context, act),
        );
      case 'chart':
        return UiChartWidget(component: comp);
      case 'table':
        return UiTableWidget(component: comp);
      case 'progress':
        return UiProgressWidget(component: comp);
      case 'buttons':
        return UiButtonsWidget(
          actions: comp.actions,
          onAction: (act) => _handleAction(context, act),
        );
      case 'accordion':
        return UiAccordionWidget(component: comp);
      case 'form':
        return UiFormWidget(
          component: comp,
          onSubmit: onFormSubmit,
        );
      case 'dashboard':
        return UiDashboardWidget(
          component: comp,
          onAction: (act) => _handleAction(context, act),
        );
      case 'code_block':
        return UiCodeBlockWidget(component: comp);
      case 'map':
        return UiMapWidget(component: comp);
      case 'comparison':
        return UiComparisonWidget(
          component: comp,
          onAction: (act) => _handleAction(context, act),
        );
      case 'color_palette':
        return UiColorPaletteWidget(component: comp);
      case 'column':
      case 'container':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: comp.children.map((c) => _buildComponent(context, c)).toList(),
        );
      case 'row':
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: comp.children
                .map((c) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildComponent(context, c),
                    ))
                .toList(),
          ),
        );
      default:
        // Safe fallback: render as a card
        return UiCardWidget(
          component: comp,
          onAction: (act) => _handleAction(context, act),
        );
    }
  }
}
