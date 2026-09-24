/// Editor save-chain races: a slow first create (photo/clip copy) must not
/// double-create, drop edits typed meanwhile, survive a delete, or be thrown
/// away as "blank" on back.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/presentation/features/notes/pages/note_editor_page.dart';

import '../../../domain/fakes.dart';
import '_notes_harness.dart';

/// Holds every `save` until [gate] completes (null = pass through).
class GatedNoteRepository extends FakeNoteRepository {
  Completer<void>? gate;
  int saves = 0;

  @override
  Future<void> save(Note note) async {
    saves++;
    final g = gate;
    if (g != null) await g.future;
    return super.save(note);
  }
}

class GatedNotesHarness extends NotesHarness {
  final _gated = GatedNoteRepository();
  @override
  GatedNoteRepository get notes => _gated;
}

Future<void> tapKey(WidgetTester t, String key, [int frames = 4]) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.tap(f);
  await settle(t, frames);
}

Future<void> addPhotoFromGallery(WidgetTester t) async {
  await tapKey(t, 'act-photo');
  await t.tap(find.text('Galeri'));
  await settle(t, 2);
}

void main() {
  testWidgets('typing while a photo creates the note: one note, edit kept', (
    t,
  ) async {
    final h = GatedNotesHarness()..seed.notesSeeded = true;
    await pumpNotes(t, h, location: '/notes/new');
    h.notes.gate = Completer<void>();
    await addPhotoFromGallery(t); // create is now held
    await t.enterText(find.byKey(const ValueKey('note-title')), 'Struk');
    await t.pump(NoteEditorPage.autosaveDelay); // autosave fires meanwhile
    await settle(t, 2);
    h.notes.gate!.complete();
    h.notes.gate = null;
    await settle(t, 4);
    await autosave(t);

    expect(h.allNotes, hasLength(1));
    final n = h.allNotes.single;
    expect(n.photos, hasLength(1));
    expect(n.title, 'Struk');
  });

  testWidgets('delete while the first create is in flight removes the note', (
    t,
  ) async {
    final h = GatedNotesHarness()..seed.notesSeeded = true;
    await pumpNotes(t, h, location: '/notes/new');
    h.notes.gate = Completer<void>();
    await t.enterText(find.byKey(const ValueKey('note-title')), 'Salah');
    await autosave(t); // create started, held
    expect(h.notes.saves, 1);

    await tapKey(t, 'note-more');
    await t.tap(find.text('Hapus'));
    await settle(t, 4);
    await t.tap(find.text('HAPUS'));
    await settle(t, 2);
    h.notes.gate!.complete();
    h.notes.gate = null;
    await settle(t, 8);

    expect(h.allNotes, isEmpty);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('back right after a photo-only note is created keeps it', (
    t,
  ) async {
    final h = GatedNotesHarness()..seed.notesSeeded = true;
    await pumpNotes(t, h, location: '/notes/new');
    h.notes.gate = Completer<void>();
    await addPhotoFromGallery(t);
    // Back while the create is still running…
    final back = find.byKey(const ValueKey('note-back'));
    await t.tap(back);
    await t.pump();
    h.notes.gate!.complete();
    h.notes.gate = null;
    await settle(t, 8);

    expect(find.text('HOME'), findsOneWidget);
    expect(h.allNotes, hasLength(1));
    expect(h.allNotes.single.photos, hasLength(1));
  });
}
