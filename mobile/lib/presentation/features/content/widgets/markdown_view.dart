import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../design_system/design_system.dart';

/// Read-only preview of an item's idea/script (Markdown), styled like the
/// Notes preview. Safe: `flutter_markdown_plus` never renders raw HTML, images
/// become a small placeholder (no loads from the text), and only http(s)
/// links reach [onLink].
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.text, this.onLink});

  final String text;
  final ValueChanged<String>? onLink;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final fg = g.textPrimary;
    final base = GhinaType.body.copyWith(color: fg, height: 1.45);
    return MarkdownBody(
      data: text,
      softLineBreak: false,
      onTapLink: (_, href, _) {
        final uri = href == null ? null : Uri.tryParse(href);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          onLink?.call(href!);
        }
      },
      styleSheet: MarkdownStyleSheet(
        p: base,
        h1: GhinaType.h2.w(900).copyWith(color: fg),
        h2: GhinaType.h3.w(900).copyWith(color: fg),
        h3: GhinaType.bodyL.w(900).copyWith(color: fg),
        h4: base.w(800),
        h5: base.w(800),
        h6: base.w(800),
        strong: const TextStyle(fontWeight: FontWeight.w800),
        em: const TextStyle(fontStyle: FontStyle.italic),
        a: base.copyWith(
          color: GhinaColors.blue.base,
          decoration: TextDecoration.underline,
          decorationColor: GhinaColors.blue.base,
        ),
        code: GhinaType.bodyS.copyWith(
          color: fg,
          fontFamily: 'monospace',
          backgroundColor: g.surfaceAlt,
        ),
        listBullet: base,
        blockquote: base.copyWith(color: g.textSecondary),
        blockquoteDecoration: BoxDecoration(
          color: g.surfaceAlt.withValues(alpha: 0.6),
          border: Border(
            left: BorderSide(color: GhinaColors.purple.base, width: 4),
          ),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        codeblockDecoration: BoxDecoration(
          color: g.surfaceAlt,
          borderRadius: GhinaRadii.rMd,
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: g.border, width: 2)),
        ),
        blockSpacing: 8,
      ),
      imageBuilder: (uri, title, alt) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 16, color: g.textMuted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              (alt ?? '').isEmpty ? 'gambar' : alt!,
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
