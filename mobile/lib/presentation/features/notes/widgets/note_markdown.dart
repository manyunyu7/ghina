import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../design_system/design_system.dart';
import 'link_open.dart';

/// Read-only preview of a note body (the docs/notes.md Markdown subset).
///
/// Safe by construction: `flutter_markdown_plus` never renders raw HTML, images
/// are replaced by a small placeholder (no remote/file loads from note text),
/// and links only open after the user sees the URL ([confirmOpenLink]).
class NoteMarkdown extends StatelessWidget {
  const NoteMarkdown({super.key, required this.data, this.textColor});

  final String data;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final fg = textColor ?? g.textPrimary;
    final base = GhinaType.bodyL.copyWith(color: fg, height: 1.45);
    return MarkdownBody(
      data: data,
      softLineBreak: false,
      styleSheet: MarkdownStyleSheet(
        p: base,
        h1: GhinaType.h1.w(900).copyWith(color: fg),
        h2: GhinaType.h2.w(900).copyWith(color: fg),
        h3: GhinaType.h3.w(900).copyWith(color: fg),
        h4: GhinaType.h3.w(800).copyWith(color: fg),
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
            left: BorderSide(color: GhinaColors.green.base, width: 4),
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
        blockSpacing: 10,
      ),
      imageBuilder: (uri, title, alt) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: g.surfaceAlt,
          borderRadius: GhinaRadii.rSm,
        ),
        child: Row(
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
      ),
      onTapLink: (text, href, title) {
        if (href != null) confirmOpenLink(context, href);
      },
    );
  }
}
