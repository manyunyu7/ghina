/// Plain-text Markdown editing helpers for the note body toolbar (bold,
/// italic, heading, lists, quote, link) and dictation inserts. Pure functions
/// over [TextEditingValue] so they're easy to test.
library;

import 'package:flutter/services.dart';

/// Toolbar actions.
enum MdAction { bold, italic, heading, bullet, numbered, quote, link }

TextSelection _sel(TextEditingValue v) {
  final s = v.selection;
  if (!s.isValid) return TextSelection.collapsed(offset: v.text.length);
  return s;
}

/// Applies a toolbar [action] to [v].
TextEditingValue applyMarkdown(TextEditingValue v, MdAction action) =>
    switch (action) {
      MdAction.bold => wrapSelection(v, '**'),
      MdAction.italic => wrapSelection(v, '_'),
      MdAction.heading => toggleLinePrefix(v, '## '),
      MdAction.bullet => toggleLinePrefix(v, '- '),
      MdAction.numbered => toggleLinePrefix(v, '1. ', numbered: true),
      MdAction.quote => toggleLinePrefix(v, '> '),
      MdAction.link => insertLink(v),
    };

/// Wraps the selection with [marker] (e.g. `**`). Already wrapped → unwraps.
/// Nothing selected → inserts `marker marker` with the cursor in between.
TextEditingValue wrapSelection(TextEditingValue v, String marker) {
  final s = _sel(v);
  final text = v.text;
  final start = s.start, end = s.end;
  final selected = text.substring(start, end);
  final m = marker.length;
  // Unwrap when the markers sit just outside the selection.
  if (start >= m &&
      end + m <= text.length &&
      text.substring(start - m, start) == marker &&
      text.substring(end, end + m) == marker) {
    final out = text
        .replaceRange(end, end + m, '')
        .replaceRange(start - m, start, '');
    return TextEditingValue(
      text: out,
      selection: TextSelection(baseOffset: start - m, extentOffset: end - m),
    );
  }
  final out = text.replaceRange(start, end, '$marker$selected$marker');
  return TextEditingValue(
    text: out,
    selection: selected.isEmpty
        ? TextSelection.collapsed(offset: start + m)
        : TextSelection(baseOffset: start + m, extentOffset: end + m),
  );
}

final _prefixRe = RegExp(r'^(#{1,6}\s+|>\s?|[-*+]\s+|\d+[.)]\s+)');

/// Toggles [prefix] on every line touched by the selection. When all those
/// lines already start with it, it's removed; otherwise any other block
/// prefix is replaced. [numbered] numbers the lines 1., 2., …
TextEditingValue toggleLinePrefix(
  TextEditingValue v,
  String prefix, {
  bool numbered = false,
}) {
  final s = _sel(v);
  final text = v.text;
  final lineStart = s.start == 0 ? 0 : text.lastIndexOf('\n', s.start - 1) + 1;
  var lineEnd = text.indexOf('\n', s.end);
  if (lineEnd < 0) lineEnd = text.length;
  final block = text.substring(lineStart, lineEnd);
  final lines = block.split('\n');

  bool has(String l) =>
      numbered ? RegExp(r'^\d+[.)]\s+').hasMatch(l) : l.startsWith(prefix);
  final allHave = lines.every((l) => l.trim().isEmpty || has(l));
  final out = <String>[];
  var n = 0;
  for (final l in lines) {
    if (allHave) {
      out.add(l.replaceFirst(_prefixRe, ''));
    } else if (l.trim().isEmpty && lines.length > 1) {
      out.add(l);
    } else {
      n++;
      final bare = l.replaceFirst(_prefixRe, '');
      out.add('${numbered ? '$n. ' : prefix}$bare');
    }
  }
  final replaced = out.join('\n');
  final newText = text.replaceRange(lineStart, lineEnd, replaced);
  final delta = replaced.length - block.length;
  return TextEditingValue(
    text: newText,
    selection: s.isCollapsed
        ? TextSelection.collapsed(
            offset: (s.start + (lines.length == 1 ? delta : 0)).clamp(
              lineStart,
              lineStart + replaced.length,
            ),
          )
        : TextSelection(
            baseOffset: lineStart,
            extentOffset: lineStart + replaced.length,
          ),
  );
}

/// `[selection](https://)` with the URL part selected (to type/paste over).
TextEditingValue insertLink(TextEditingValue v) {
  final s = _sel(v);
  final text = v.text;
  final label = text.substring(s.start, s.end);
  final isUrl = RegExp(r'^https?://\S+$').hasMatch(label.trim());
  final shown = isUrl ? 'tautan' : (label.isEmpty ? 'teks' : label);
  final url = isUrl ? label.trim() : 'https://';
  final md = '[$shown]($url)';
  final out = text.replaceRange(s.start, s.end, md);
  final urlStart = s.start + shown.length + 3;
  return TextEditingValue(
    text: out,
    selection: isUrl || label.isNotEmpty
        ? TextSelection(
            baseOffset: isUrl ? s.start + 1 : urlStart,
            extentOffset: isUrl
                ? s.start + 1 + shown.length
                : urlStart + url.length,
          )
        : TextSelection(
            baseOffset: s.start + 1,
            extentOffset: s.start + 1 + shown.length,
          ),
  );
}

/// Inserts [insert] at the cursor (replacing a selection), adding a space
/// before/after when needed so dictated words don't glue to typed ones.
TextEditingValue insertAtCursor(TextEditingValue v, String insert) {
  final t = insert.trim();
  if (t.isEmpty) return v;
  final s = _sel(v);
  final text = v.text;
  final before = text.substring(0, s.start);
  final after = text.substring(s.end);
  final lead = before.isEmpty || RegExp(r'\s$').hasMatch(before) ? '' : ' ';
  final trail = after.isEmpty || RegExp(r'^[\s.,!?;:]').hasMatch(after)
      ? ''
      : ' ';
  final piece = '$lead$t$trail';
  return TextEditingValue(
    text: '$before$piece$after',
    selection: TextSelection.collapsed(
      offset: before.length + lead.length + t.length,
    ),
  );
}
