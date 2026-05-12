import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

class PlanDescriptionWidget extends StatelessWidget {
  final String content;

  const PlanDescriptionWidget({
    super.key,
    required this.content,
  });

  String _normalizeContent(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final normalized = _normalizeContent(content);

    if (normalized.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 14,
          height: 1.5,
        ),
        child: HtmlWidget(
          normalized,
          textStyle: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 14,
            height: 1.5,
          ),
          renderMode: RenderMode.column,
        ),
      ),
    );
  }
}
