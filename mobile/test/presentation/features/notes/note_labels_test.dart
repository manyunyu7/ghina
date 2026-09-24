import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/features/notes/markdown_edit.dart';

import '_notes_harness.dart';

TextEditingValue v(String text, int start, [int? end]) => TextEditingValue(
  text: text,
  selection: TextSelection(baseOffset: start, extentOffset: end ?? start),
);

void main() {
  group('NoteLabelsPage', () {
    testWidgets('rename, pin as tab, delete with a warning', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.labels.s
        ..put(label('l1', 'Belanja'))
        ..put(label('l2', 'Kerjaan', order: 1));
      h.notes.s
        ..put(note('a', labels: ['l1'], title: 'A'))
        ..put(note('b', labels: ['l1', 'l2'], title: 'B'));
      await pumpNotes(t, h, location: '/notes/labels');
      expect(find.text('2 catatan'), findsOneWidget);
      expect(find.text('1 catatan'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('label-tab-l2')));
      await settle(t, 3);
      expect(h.labels.s.items['l2']!.pinnedTab, isTrue);

      await t.tap(find.text('Kerjaan'));
      await settle(t, 4);
      await t.enterText(
        find.byKey(const ValueKey('label-form-name')),
        'Kantor',
      );
      await t.tap(find.byKey(const ValueKey('label-form-save')));
      await settle(t, 4);
      expect(h.labels.s.items['l2']!.name, 'Kantor');

      await t.tap(find.byKey(const ValueKey('label-delete-l1')));
      await settle(t, 4);
      expect(find.textContaining('dilepas dari 2 catatan'), findsOneWidget);
      await t.tap(find.text('HAPUS LABEL'));
      await settle(t, 4);
      expect(h.labels.s.items.containsKey('l1'), isFalse);
    });

    testWidgets('create a label', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      await pumpNotes(t, h, location: '/notes/labels');
      expect(find.text('Belum ada label'), findsOneWidget);
      await t.tap(find.text('BUAT LABEL'));
      await settle(t, 4);
      await t.enterText(
        find.byKey(const ValueKey('label-form-name')),
        'Belanja',
      );
      await t.tap(find.byKey(const ValueKey('label-form-tab')));
      await t.tap(find.byKey(const ValueKey('label-form-save')));
      await settle(t, 4);
      final l = h.labels.s.items.values.single;
      expect(l.name, 'Belanja');
      expect(l.pinnedTab, isTrue);
    });

    testWidgets('duplicate names are refused inline', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.labels.s.put(label('l1', 'Belanja'));
      await pumpNotes(t, h, location: '/notes/labels');
      await t.tap(find.byKey(const ValueKey('label-add')));
      await settle(t, 4);
      await t.enterText(
        find.byKey(const ValueKey('label-form-name')),
        'belanja',
      );
      await t.tap(find.byKey(const ValueKey('label-form-save')));
      await settle(t, 4);
      expect(h.labels.s.items, hasLength(1));
      expect(find.byKey(const ValueKey('label-form-name')), findsOneWidget);
    });
  });

  group('markdown edit helpers', () {
    test('wrap / unwrap / empty selection', () {
      expect(wrapSelection(v('a b c', 2, 3), '**').text, 'a **b** c');
      final unwrapped = wrapSelection(
        const TextEditingValue(
          text: 'a **b** c',
          selection: TextSelection(baseOffset: 4, extentOffset: 5),
        ),
        '**',
      );
      expect(unwrapped.text, 'a b c');
      final empty = wrapSelection(v('ab', 1), '_');
      expect(empty.text, 'a__b');
      expect(empty.selection.baseOffset, 2);
    });

    test('line prefixes toggle across the selected lines', () {
      final list = toggleLinePrefix(v('satu\ndua', 0, 8), '- ');
      expect(list.text, '- satu\n- dua');
      expect(toggleLinePrefix(v(list.text, 0, 12), '- ').text, 'satu\ndua');
      expect(
        applyMarkdown(v('a\nb', 0, 3), MdAction.numbered).text,
        '1. a\n2. b',
      );
      expect(applyMarkdown(v('- a', 1), MdAction.quote).text, '> a');
      expect(applyMarkdown(v('judul', 2), MdAction.heading).text, '## judul');
    });

    test('link wraps the selection and selects the URL part', () {
      final r = insertLink(v('baca ini', 5, 8));
      expect(r.text, 'baca [ini](https://)');
      expect(r.text.substring(r.selection.start, r.selection.end), 'https://');
    });

    test('dictated text gets spaces around it', () {
      expect(insertAtCursor(v('Halo', 4), 'dunia').text, 'Halo dunia');
      expect(insertAtCursor(v('Halo.', 4), 'dunia').text, 'Halo dunia.');
      expect(insertAtCursor(v('', 0), ' hai ').text, 'hai');
      expect(insertAtCursor(v('a b', 1), 'x').text, 'a x b');
    });
  });
}
