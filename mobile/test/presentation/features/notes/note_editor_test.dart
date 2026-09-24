import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';

import '_notes_harness.dart';

Future<void> tapKey(WidgetTester t, String key, [int frames = 4]) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.tap(f);
  await settle(t, frames);
}

void main() {
  group('NoteEditorPage', () {
    testWidgets('new note: autosave creates it, shows Tersimpan', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      await pumpNotes(t, h, location: '/notes/new');
      expect(h.allNotes, isEmpty);
      await t.enterText(find.byKey(const ValueKey('note-title')), 'Belanja');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Menyimpan…'), findsOneWidget);
      expect(h.allNotes, isEmpty); // debounced
      await autosave(t);
      expect(h.allNotes.single.title, 'Belanja');
      expect(find.text('Tersimpan'), findsOneWidget);

      // Later edits update the same note.
      await t.enterText(
        find.byKey(const ValueKey('note-body')),
        '- Telur\n- Susu',
      );
      await autosave(t);
      expect(h.allNotes, hasLength(1));
      expect(h.allNotes.single.body, '- Telur\n- Susu');
    });

    testWidgets('blank new note is discarded on back', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      await pumpNotes(t, h, location: '/notes/new');
      await tapKey(t, 'note-back');
      expect(find.text('HOME'), findsOneWidget);
      expect(h.allNotes, isEmpty);
    });

    testWidgets('back saves pending edits right away', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.notes.s.put(note('a', title: 'Lama', body: 'isi'));
      await pumpNotes(t, h, location: '/notes/a');
      expect(find.text('Lama'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('note-title')), 'Baru');
      await t.pump(const Duration(milliseconds: 50));
      await tapKey(t, 'note-back');
      expect(find.text('HOME'), findsOneWidget);
      expect(h.noteById('a')!.title, 'Baru');
    });

    testWidgets('an existing note emptied out is deleted on back', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.notes.s.put(note('a', title: 'Hapus aku'));
      await pumpNotes(t, h, location: '/notes/a');
      await t.enterText(find.byKey(const ValueKey('note-title')), '');
      await tapKey(t, 'note-back');
      expect(h.noteById('a'), isNull);
    });

    testWidgets('toolbar formats the body; preview renders markdown', (
      t,
    ) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      await pumpNotes(t, h, location: '/notes/new');
      await t.enterText(find.byKey(const ValueKey('note-body')), 'penting');
      final body = find.byKey(const ValueKey('note-body'));
      final field = t.widget<TextField>(body);
      field.controller!.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 7,
      );
      await tapKey(t, 'fmt-bold', 2);
      expect(field.controller!.text, '**penting**');
      await tapKey(t, 'fmt-bullet', 2);
      expect(field.controller!.text, '- **penting**');
      await tapKey(t, 'fmt-preview', 2);
      expect(find.byKey(const ValueKey('note-preview')), findsOneWidget);
      expect(find.text('penting'), findsOneWidget); // rendered, no markers
      await autosave(t);
      expect(h.allNotes.single.body, '- **penting**');
    });

    testWidgets('pin, color, archive', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.notes.s.put(note('a', title: 'Catatan'));
      await pumpNotes(t, h, location: '/notes/a');
      await tapKey(t, 'note-pin');
      await autosave(t);
      expect(h.noteById('a')!.pinned, isTrue);

      await tapKey(t, 'act-color');
      await tapKey(t, 'note-color-blue');
      await t.tapAt(const Offset(10, 10)); // dismiss sheet
      await autosave(t);
      expect(h.noteById('a')!.color, 'blue');

      await tapKey(t, 'note-more');
      await t.tap(find.text('Arsipkan'));
      await settle(t, 8);
      expect(h.noteById('a')!.archived, isTrue);
      expect(h.noteById('a')!.pinned, isFalse);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('delete asks first', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.notes.s.put(note('a', title: 'Catatan'));
      await pumpNotes(t, h, location: '/notes/a');
      await tapKey(t, 'note-more');
      await t.tap(find.text('Hapus'));
      await settle(t, 4);
      expect(find.text('Hapus catatan ini?'), findsOneWidget);
      await t.tap(find.text('HAPUS'));
      await settle(t, 8);
      expect(h.noteById('a'), isNull);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('checklist: add, type, enter adds next, toggle, clear, '
        'remove', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.notes.s.put(note('a', title: 'Belanja'));
      await pumpNotes(t, h, location: '/notes/a');
      await tapKey(t, 'act-checklist');
      expect(find.byKey(const ValueKey('check-text-0')), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('check-text-0')), 'Telur');
      await t.testTextInput.receiveAction(TextInputAction.next);
      await settle(t, 2);
      await t.enterText(find.byKey(const ValueKey('check-text-1')), 'Susu');
      await tapKey(t, 'check-add', 2);
      await t.enterText(find.byKey(const ValueKey('check-text-2')), 'Roti');
      await autosave(t);
      expect(h.noteById('a')!.checklist.map((c) => c.text), [
        'Telur',
        'Susu',
        'Roti',
      ]);

      await tapKey(t, 'check-toggle-0', 2);
      await autosave(t);
      expect(h.noteById('a')!.checklistDone, 1);

      await tapKey(t, 'check-clear-done', 2);
      await autosave(t);
      expect(h.noteById('a')!.checklist.map((c) => c.text), ['Susu', 'Roti']);

      await tapKey(t, 'check-remove-1', 2);
      await autosave(t);
      expect(h.noteById('a')!.checklist.map((c) => c.text), ['Susu']);
    });

    testWidgets('labels: pick existing and create one inline', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.labels.s.put(label('l1', 'Kerjaan'));
      h.notes.s.put(note('a', title: 'Rapat'));
      await pumpNotes(t, h, location: '/notes/a');
      await tapKey(t, 'note-labels');
      await tapKey(t, 'label-pick-l1', 2);
      await t.enterText(find.byKey(const ValueKey('label-new-name')), 'Urgent');
      await tapKey(t, 'label-new-add');
      await t.tapAt(const Offset(10, 10));
      await autosave(t);
      final n = h.noteById('a')!;
      expect(n.labelIds, hasLength(2));
      expect(n.labelIds.first, 'l1');
      final created = h.labels.s.items.values.firstWhere(
        (l) => l.name == 'Urgent',
      );
      expect(n.labelIds, contains(created.id));
      expect(find.text('Urgent'), findsOneWidget); // chip on the note
    });

    testWidgets('photos: add from picker creates the note', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      await pumpNotes(t, h, location: '/notes/new');
      await tapKey(t, 'act-photo');
      await t.tap(find.text('Galeri'));
      await settle(t, 6);
      final n = h.allNotes.single;
      expect(n.photos.single.localPath, '/tmp/p1.jpg');
      expect(find.byKey(const ValueKey('photo-thumb-0')), findsOneWidget);
    });

    testWidgets('links show titles', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.notes.s.put(
        note(
          'a',
          body: 'cek https://contoh.id/resep',
          links: const [
            NoteLink(url: 'https://contoh.id/resep', title: 'Resep Rendang'),
            NoteLink(url: 'https://www.youtube.com/watch?v=1'),
          ],
        ),
      );
      await pumpNotes(t, h, location: '/notes/a');
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('link-1')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Resep Rendang'), findsOneWidget);
      expect(find.text('youtube.com'), findsOneWidget);
    });
  });
}
