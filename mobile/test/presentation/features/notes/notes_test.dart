import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';
import 'package:ghina/presentation/features/notes/pages/notes_page.dart';

import '_notes_harness.dart';

void main() {
  group('NotesPage', () {
    testWidgets('empty: seeds Ide Konten tab and invites the first note', (
      t,
    ) async {
      final h = NotesHarness();
      await pumpNotes(t, h);
      expect(find.text('Belum ada catatan'), findsOneWidget);
      // Offline fallback seeding ran.
      expect(h.labels.s.items.keys, contains(defaultLabelId('u1')));
      expect(find.text('Ide Konten'), findsOneWidget);
      expect(find.text('Semua'), findsOneWidget);
      expect(find.text('Arsip'), findsOneWidget);
    });

    testWidgets('no seeding once the server seeded', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      await pumpNotes(t, h);
      expect(h.labels.s.items, isEmpty);
    });

    testWidgets('cards: pinned first, label tab, archive tab', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.labels.s.put(label('l1', 'Belanja', tab: true));
      h.notes.s
        ..put(note('a', title: 'Resep rendang', body: 'Daging 1 kg'))
        ..put(
          note(
            'b',
            title: 'Daftar belanja',
            labels: ['l1'],
            checklist: const [
              ChecklistItem(id: 'c1', text: 'Telur'),
              ChecklistItem(id: 'c2', text: 'Susu', done: true),
            ],
            color: 'yellow',
          ),
        )
        ..put(note('c', title: 'Penting banget', pinned: true, ageMinutes: 90))
        ..put(note('d', title: 'Lama', archived: true));
      await pumpNotes(t, h);

      expect(find.text('DISEMATKAN'), findsOneWidget);
      expect(find.text('LAINNYA'), findsOneWidget);
      expect(find.text('Resep rendang'), findsOneWidget);
      expect(find.text('Daftar belanja'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget); // checklist progress
      expect(find.text('Lama'), findsNothing);
      final pinnedY = t.getTopLeft(find.text('Penting banget')).dy;
      expect(pinnedY, lessThan(t.getTopLeft(find.text('Resep rendang')).dy));

      await t.tap(find.byKey(const ValueKey('notes-tab-l1')));
      await settle(t, 4);
      expect(find.text('Daftar belanja'), findsOneWidget);
      expect(find.text('Resep rendang'), findsNothing);

      await t.tap(find.byKey(const ValueKey('notes-tab-__archive__')));
      await settle(t, 4);
      expect(find.text('Lama'), findsOneWidget);
      expect(find.text('Daftar belanja'), findsNothing);

      // List mode.
      await t.tap(find.byKey(const ValueKey('notes-tab-__all__')));
      await t.tap(find.byKey(const ValueKey('notes-layout')));
      await settle(t, 4);
      expect(find.text('Resep rendang'), findsOneWidget);
    });

    testWidgets('search is debounced and matches body/checklist', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.notes.s
        ..put(note('a', title: 'Ide', body: 'Kopi susu gula aren'))
        ..put(
          note(
            'b',
            title: 'Belanja',
            checklist: const [ChecklistItem(id: 'x', text: 'Kopi bubuk')],
          ),
        )
        ..put(note('c', title: 'Olahraga', body: 'Lari pagi'))
        ..put(note('d', title: 'Arsip kopi', archived: true));
      await pumpNotes(t, h);
      await t.tap(find.byKey(const ValueKey('notes-search-toggle')));
      await settle(t, 2);
      await t.enterText(find.byKey(const ValueKey('notes-search')), 'kopi');
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Olahraga'), findsOneWidget); // not applied yet
      await t.pump(NotesPage.searchDebounce);
      await settle(t, 3);
      expect(find.text('Olahraga'), findsNothing);
      expect(find.text('Ide'), findsOneWidget);
      expect(find.text('Belanja'), findsOneWidget);
      // "Semua" searches the archive too, marked as such.
      expect(find.text('Arsip kopi'), findsOneWidget);
      expect(find.text('ARSIP'), findsOneWidget);
      expect(find.textContaining('3 catatan cocok'), findsOneWidget);

      await t.enterText(find.byKey(const ValueKey('notes-search')), 'zzz');
      await t.pump(NotesPage.searchDebounce);
      await settle(t, 3);
      expect(find.text('Nggak ketemu'), findsOneWidget);
    });

    testWidgets('FAB opens a new note; new note from a tab gets its label', (
      t,
    ) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.labels.s.put(label('l1', 'Kerjaan', tab: true));
      await pumpNotes(t, h);
      await t.tap(find.byKey(const ValueKey('notes-tab-l1')));
      await settle(t, 2);
      await t.tap(find.byKey(const ValueKey('notes-fab')));
      await settle(t);
      expect(find.byKey(const ValueKey('note-body')), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('note-body')), 'Rapat jam 3');
      await autosave(t);
      final n = h.allNotes.single;
      expect(n.body, 'Rapat jam 3');
      expect(n.labelIds, ['l1']);
      expect(n.source, NoteSource.quick);
    });

    testWidgets('long-press on a card: pin, archive', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.notes.s.put(note('a', title: 'Catatan A'));
      await pumpNotes(t, h);
      await t.longPress(find.byKey(const ValueKey('note-card-a')));
      await settle(t, 4);
      await t.tap(find.byKey(const ValueKey('qa-pin')));
      await settle(t, 4);
      expect(h.noteById('a')!.pinned, isTrue);
      await t.longPress(find.byKey(const ValueKey('note-card-a')));
      await settle(t, 4);
      await t.tap(find.byKey(const ValueKey('qa-archive')));
      await settle(t, 4);
      expect(h.noteById('a')!.archived, isTrue);
      expect(find.text('Catatan A'), findsNothing);
    });
  });
}
