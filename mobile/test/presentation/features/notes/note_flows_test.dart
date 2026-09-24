import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/services/services.dart';

import '_notes_harness.dart';

Future<void> tapKey(WidgetTester t, String key, [int frames = 4]) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.tap(f);
  await settle(t, frames);
}

void main() {
  group('convert', () {
    testWidgets('→ Tugas: area + bucket sheet, links the note', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.areas.s
        ..put(area('kerja', 'Kerjaan', 'KERJA'))
        ..put(area('life', 'Keseharian', 'LIFE', order: 1));
      h.notes.s.put(note('a', title: 'Kirim invoice', body: 'ke klien A'));
      await pumpNotes(t, h, location: '/notes/a');
      await tapKey(t, 'note-convert');
      await tapKey(t, 'convert-task');
      expect(find.text('Jadikan tugas'), findsWidgets);
      await tapKey(t, 'convert-area-life', 2);
      await t.tap(find.text('🔥 FIRE'));
      await settle(t, 2);
      await tapKey(t, 'convert-task-save', 8);
      final task = h.tasks.s.items.values.single;
      expect(task.title, 'Kirim invoice');
      expect(task.areaId, 'life');
      expect(task.bucket, TaskBucket.fire);
      expect(task.note, 'ke klien A');
      expect(h.noteById('a')!.linkedTaskId, task.id);
      await settle(t, 20);
      expect(find.byKey(const ValueKey('linked-task')), findsOneWidget);
      await tapKey(t, 'linked-task');
      expect(find.text('route:/tasks/${task.id}'), findsOneWidget);
    });

    testWidgets('→ Konten: creates the idea and offers to open it', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.notes.s.put(note('a', title: 'Video tips hemat', body: 'Hook: …'));
      await pumpNotes(t, h, location: '/notes/a');
      await tapKey(t, 'note-convert');
      await tapKey(t, 'convert-content', 8);
      final item = h.contentItems.s.items.values.single;
      expect(item.title, 'Video tips hemat');
      expect(item.stage, ContentStage.ide);
      expect(h.noteById('a')!.linkedContentId, item.id);
      expect(find.text('Jadi ide konten! 🎬'), findsOneWidget);
      await tapKey(t, 'open-content', 6);
      expect(find.text('route:/content/${item.id}'), findsOneWidget);
    });

    testWidgets('→ Transaksi: prefilled amount + photos, links the note', (
      t,
    ) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.wallets.s.put(wallet('w1', 'Tunai'));
      h.notes.s.put(
        note(
          'a',
          title: 'Makan siang tim',
          body: 'Total Rp 125.000 di warung',
          photos: const [TransactionPhoto.local('/tmp/struk.jpg')],
        ),
      );
      await pumpNotes(t, h, location: '/notes/a');
      await tapKey(t, 'note-convert');
      await tapKey(t, 'convert-transaction');
      expect(find.text('125.000'), findsOneWidget);
      expect(find.text('1 foto ikut dilampirkan'), findsOneWidget);
      await tapKey(t, 'convert-tx-save', 20);
      final tx = h.transactions.s.items.values.single;
      expect(tx.amount, 125000);
      expect(tx.type, TxType.expense);
      expect(tx.walletId, 'w1');
      expect(tx.note, 'Makan siang tim');
      expect(tx.photos.single.localPath, '/tmp/struk.jpg');
      expect(h.noteById('a')!.linkedTransactionId, tx.id);
    });

    testWidgets('→ Transaksi without an amount asks for it', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.wallets.s.put(wallet('w1', 'Tunai'));
      h.notes.s.put(note('a', title: 'Beli sesuatu'));
      await pumpNotes(t, h, location: '/notes/a');
      await tapKey(t, 'note-convert');
      await tapKey(t, 'convert-transaction');
      await tapKey(t, 'convert-tx-save');
      expect(find.text('Isi nominalnya dulu, ya'), findsOneWidget);
      expect(h.transactions.s.items, isEmpty);
    });

    testWidgets('linked rows open the target instead', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.notes.s.put(note('a', title: 'X').copyWith(linkedContentId: 'k1'));
      await pumpNotes(t, h, location: '/notes/a');
      await tapKey(t, 'note-convert');
      expect(find.text('Sudah jadi konten'), findsWidgets);
      await tapKey(t, 'convert-content', 6);
      expect(find.text('route:/content/k1'), findsOneWidget);
    });
  });

  group('share', () {
    testWidgets('a shared payload becomes a note with the share sheet', (
      t,
    ) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.labels.s.put(label('l1', 'Ide Konten', color: '#ce82ff', tab: true));
      await pumpNotes(t, h, location: '/', withShareListener: true);
      h.share.share(
        const SharedPayload(
          title: 'Cara bikin kopi susu',
          text: 'Resep enak banget',
          urls: ['https://contoh.id/kopi'],
        ),
      );
      await settle(t, 8);
      expect(find.byKey(const ValueKey('share-sheet')), findsOneWidget);
      final n = h.allNotes.single;
      expect(n.source, NoteSource.share);
      expect(n.title, 'Cara bikin kopi susu');
      expect(n.body, contains('https://contoh.id/kopi'));
      expect(n.links.single.url, 'https://contoh.id/kopi');

      await tapKey(t, 'share-label-l1');
      expect(h.noteById(n.id)!.labelIds, ['l1']);

      await tapKey(t, 'share-content', 8);
      expect(h.contentItems.s.items, hasLength(1));
      expect(h.noteById(n.id)!.linkedContentId, isNotNull);
    });

    testWidgets('open from the sheet; shares wait for sign-in', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      await pumpNotes(t, h, location: '/', withShareListener: true);
      await h.session.signOut();
      await settle(t, 2);
      h.share.share(const SharedPayload(text: 'nanti'));
      await settle(t, 4);
      // Signed out: kept pending, nothing created yet.
      expect(h.allNotes, isEmpty);
      await h.session.signIn('a', 'b');
      await settle(t, 8);
      expect(h.allNotes.single.body, 'nanti');
      await tapKey(t, 'share-done', 6);
      h.share.share(const SharedPayload(text: 'Beli token listrik'));
      await settle(t, 8);
      expect(h.allNotes, hasLength(2));
      await tapKey(t, 'share-open', 6);
      expect(find.byKey(const ValueKey('note-body')), findsOneWidget);
    });
  });

  group('voice', () {
    testWidgets('record in the editor: start → waveform → save attaches', (
      t,
    ) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.recorder.durationOf = () => const Duration(seconds: 12);
      h.notes.s.put(note('a', title: 'Ide podcast'));
      await pumpNotes(t, h, location: '/notes/a');
      await tapKey(t, 'act-record');
      expect(find.text('Rekam suara'), findsOneWidget);
      await tapKey(t, 'rec-start');
      expect(h.recorder.calls, ['start']);
      expect(find.byKey(const ValueKey('rec-save')), findsOneWidget);
      h.recorder.emitLevel(0.8);
      h.recorder.emitLevel(0.3);
      await settle(t, 2);
      await tapKey(t, 'rec-save', 8);
      expect(h.recorder.calls, ['start', 'stop']);
      final clip = h.noteById('a')!.audio.single;
      expect(clip.durationSec, 12);
      expect(clip.isPending, isTrue);
      // The note stores its own copy; the recorder's file is cleaned up.
      expect(h.recorder.deleted, ['/fake/voice/0.m4a']);
      expect(find.byKey(const ValueKey('clip-0')), findsOneWidget);
      expect(find.text('0:12'), findsOneWidget);
    });

    testWidgets('cancel discards the clip', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.notes.s.put(note('a', title: 'x'));
      await pumpNotes(t, h, location: '/notes/a');
      await tapKey(t, 'act-record');
      await tapKey(t, 'rec-start');
      await tapKey(t, 'rec-cancel', 6);
      expect(h.recorder.calls, ['start', 'cancel']);
      expect(h.noteById('a')!.audio, isEmpty);
      expect(find.text('Rekam suara'), findsNothing);
    });

    testWidgets('auto-stops at the limit and keeps the clip', (t) async {
      final h = NotesHarness(maxVoice: const Duration(seconds: 2))
        ..seed.notesSeeded = true;
      h.recorder.durationOf = () => const Duration(seconds: 2);
      h.notes.s.put(note('a', title: 'x'));
      await pumpNotes(t, h, location: '/notes/a');
      await tapKey(t, 'act-record');
      await tapKey(t, 'rec-start');
      await t.pump(const Duration(seconds: 3));
      await settle(t, 8);
      expect(h.recorder.calls, ['start', 'stop']);
      expect(h.noteById('a')!.audio.single.durationSec, 2);
    });

    testWidgets('long-press FAB records a voice note right away', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.recorder.durationOf = () => const Duration(seconds: 5);
      await pumpNotes(t, h);
      await t.longPress(find.byKey(const ValueKey('notes-fab')));
      await settle(t, 4);
      expect(h.recorder.calls, ['start']);
      await tapKey(t, 'rec-save', 10);
      final n = h.allNotes.single;
      expect(n.source, NoteSource.voice);
      expect(n.audio.single.durationSec, 5);
      expect(find.byKey(const ValueKey('clip-0')), findsOneWidget);
    });

    testWidgets('mic permission: explain → request; blocked → settings', (
      t,
    ) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.mic
        ..current = MicPermissionStatus.denied
        ..afterRequest = MicPermissionStatus.granted;
      h.notes.s.put(note('a', title: 'x'));
      await pumpNotes(t, h, location: '/notes/a');
      await tapKey(t, 'act-record');
      await tapKey(t, 'rec-start');
      expect(find.text('Izinkan mikrofon, ya'), findsOneWidget);
      await tapKey(t, 'mic-allow', 6);
      expect(h.mic.requests, 1);
      expect(h.recorder.calls, ['start']);
      await tapKey(t, 'rec-cancel', 6);

      h.mic.current = MicPermissionStatus.permanentlyDenied;
      await tapKey(t, 'act-record');
      await tapKey(t, 'rec-start');
      expect(find.text('Mikrofon masih diblokir'), findsOneWidget);
      await tapKey(t, 'mic-settings', 4);
      expect(h.mic.settingsOpened, 1);
    });
  });

  group('dictation', () {
    testWidgets('partial preview, final text lands in the body', (t) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.notes.s.put(note('a', title: 'Ide', body: 'Awal'));
      await pumpNotes(t, h, location: '/notes/a');
      await tapKey(t, 'act-dictate');
      expect(find.byKey(const ValueKey('dictation-bar')), findsOneWidget);
      expect(h.transcriber.starts, 1);
      h.transcriber.partial('halo');
      await settle(t, 1);
      expect(find.text('halo'), findsOneWidget);
      h.transcriber.finalResult('halo dunia');
      await settle(t, 1);
      final body = t.widget<TextField>(find.byKey(const ValueKey('note-body')));
      expect(body.controller!.text, 'Awal halo dunia');
      await tapKey(t, 'dictation-stop', 4);
      expect(find.byKey(const ValueKey('dictation-bar')), findsNothing);
      await autosave(t);
      expect(h.noteById('a')!.body, 'Awal halo dunia');
    });

    testWidgets('unavailable offline → hint with Unduh, no mic prompt', (
      t,
    ) async {
      final h = NotesHarness()..seed.notesSeeded = true;
      h.transcriber.available = const SpeechAvailability(
        recognizerAvailable: true,
        offline: OfflineSpeechSupport.downloadable,
      );
      h.notes.s.put(note('a', title: 'x'));
      await pumpNotes(t, h, location: '/notes/a');
      await tapKey(t, 'act-dictate');
      expect(find.text('Dikte belum bisa dipakai'), findsOneWidget);
      expect(h.transcriber.starts, 0);
      expect(h.mic.requests, 0);
      await tapKey(t, 'dictation-download', 4);
      expect(h.transcriber.calls, contains('download:id-ID'));
    });
  });
}
