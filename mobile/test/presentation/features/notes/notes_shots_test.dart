// Screenshots of the Catatan screens for visual review:
// GHINA_SHOTS_DIR=/some/dir flutter test test/presentation/features/notes/notes_shots_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/services/services.dart';

import '../../design_system/_helpers.dart';
import '_notes_harness.dart';

const _key = ValueKey('shot');

NotesHarness _seeded() {
  final h = NotesHarness()..seed.notesSeeded = true;
  h.labels.s
    ..put(label('ide', 'Ide Konten', color: '#ce82ff', tab: true))
    ..put(label('blj', 'Belanja', color: '#58cc02', tab: true, order: 1))
    ..put(label('krj', 'Kerjaan', color: '#1cb0f6', tab: true, order: 2));
  h.wallets.s.put(wallet('w1', 'Tunai'));
  h.areas.s.put(area('kerja', 'Kerjaan', 'KERJA'));
  h.notes.s
    ..put(
      note(
        'a',
        title: 'Konten: 5 tips hemat anak kos',
        body:
            '## Hook\nPernah nggak **gaji habis** di tengah bulan?\n\n'
            '- Masak sendiri\n- Catat pengeluaran\n- Pakai *budget* mingguan',
        labels: ['ide'],
        color: 'purple',
        pinned: true,
        links: const [
          NoteLink(
            url: 'https://contoh.id/tips-hemat',
            title: '10 Cara Hemat ala Mahasiswa',
          ),
        ],
        audio: const [NoteAudio.local('/tmp/a.m4a', durationSec: 47)],
      ),
    )
    ..put(
      note(
        'b',
        title: 'Belanja mingguan',
        labels: ['blj'],
        color: 'yellow',
        checklist: const [
          ChecklistItem(id: 'c1', text: 'Telur 1 kg'),
          ChecklistItem(id: 'c2', text: 'Susu UHT', done: true),
          ChecklistItem(id: 'c3', text: 'Sabun cuci'),
          ChecklistItem(id: 'c4', text: 'Beras 5 kg', done: true),
        ],
        ageMinutes: 30,
      ),
    )
    ..put(
      note(
        'c',
        title: 'Rapat klien A',
        body: 'Deadline revisi Jumat. Budget Rp 2.500.000',
        labels: ['krj'],
        ageMinutes: 60,
      ),
    )
    ..put(
      note(
        'd',
        body: 'Ide nama toko: Kopi Senja, Rumah Kopi, Kopi Kita',
        color: 'teal',
        ageMinutes: 90,
      ),
    )
    ..put(
      note(
        'e',
        title: 'Rekaman ide podcast',
        audio: const [
          NoteAudio.local('/tmp/b.m4a', durationSec: 185),
          NoteAudio.local('/tmp/c.m4a', durationSec: 40),
        ],
        ageMinutes: 120,
      ),
    );
  return h;
}

Future<void> _shot(
  WidgetTester tester,
  String name,
  String location, {
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  NotesHarness? harness,
  bool share = false,
  Future<void> Function(WidgetTester t, NotesHarness h)? act,
}) async {
  await loadGhinaFonts();
  final h = harness ?? _seeded();
  await pumpNotes(
    tester,
    h,
    location: location,
    dark: dark,
    size: size,
    textScale: textScale,
    boundaryKey: _key,
    withShareListener: share,
  );
  if (act != null) await act(tester, h);
  await settle(tester, 6);
  await saveShot(tester, _key, name);
  expect(tester.takeException(), isNull);
}

Future<void> _tap(WidgetTester t, String key) async {
  await t.tap(find.byKey(ValueKey(key)));
  await settle(t, 6);
}

void main() {
  const small = Size(360, 640);
  testWidgets('list light', (t) => _shot(t, 'notes_list_light', '/notes'));
  testWidgets(
    'list dark',
    (t) => _shot(t, 'notes_list_dark', '/notes', dark: true),
  );
  testWidgets(
    'list small',
    (t) => _shot(t, 'notes_list_small', '/notes', size: small, textScale: 1.3),
  );
  testWidgets(
    'list mode',
    (t) => _shot(
      t,
      'notes_list_rows',
      '/notes',
      act: (t, _) => _tap(t, 'notes-layout'),
    ),
  );
  testWidgets(
    'empty',
    (t) => _shot(t, 'notes_empty', '/notes', harness: NotesHarness()),
  );
  testWidgets(
    'editor light',
    (t) => _shot(t, 'notes_editor_light', '/notes/a'),
  );
  testWidgets(
    'editor dark',
    (t) => _shot(t, 'notes_editor_dark', '/notes/a', dark: true),
  );
  testWidgets(
    'editor checklist small',
    (t) =>
        _shot(t, 'notes_editor_small', '/notes/b', size: small, textScale: 1.3),
  );
  testWidgets(
    'editor checklist dark',
    (t) => _shot(t, 'notes_editor_checklist_dark', '/notes/b', dark: true),
  );
  testWidgets(
    'editor preview',
    (t) => _shot(
      t,
      'notes_editor_preview',
      '/notes/a',
      act: (t, _) => _tap(t, 'fmt-preview'),
    ),
  );
  testWidgets(
    'recorder',
    (t) => _shot(
      t,
      'notes_recorder',
      '/notes/c',
      act: (t, h) async {
        await _tap(t, 'act-record');
        await _tap(t, 'rec-start');
        for (var i = 0; i < 48; i++) {
          h.recorder.emitLevel(0.2 + 0.7 * ((i * 37) % 11) / 10);
        }
        await settle(t, 3);
      },
    ),
  );
  testWidgets(
    'recorder small dark',
    (t) => _shot(
      t,
      'notes_recorder_small_dark',
      '/notes/c',
      dark: true,
      size: small,
      textScale: 1.3,
      act: (t, h) async {
        await _tap(t, 'act-record');
        await _tap(t, 'rec-start');
        for (var i = 0; i < 30; i++) {
          h.recorder.emitLevel(((i * 29) % 10) / 10);
        }
        await settle(t, 3);
      },
    ),
  );
  testWidgets(
    'dictation',
    (t) => _shot(
      t,
      'notes_dictation',
      '/notes/c',
      act: (t, h) async {
        h.transcriber.available = const SpeechAvailability(
          recognizerAvailable: true,
          offline: OfflineSpeechSupport.unknown,
        );
        await _tap(t, 'act-dictate');
        h.transcriber.finalResult('lalu kirim draf ke tim');
        h.transcriber.partial('dan jadwalkan rapat');
        await settle(t, 2);
      },
    ),
  );
  testWidgets(
    'convert menu',
    (t) => _shot(
      t,
      'notes_convert_menu',
      '/notes/c',
      act: (t, _) => _tap(t, 'note-convert'),
    ),
  );
  testWidgets(
    'convert task',
    (t) => _shot(
      t,
      'notes_convert_task',
      '/notes/c',
      act: (t, _) async {
        await _tap(t, 'note-convert');
        await _tap(t, 'convert-task');
      },
    ),
  );
  testWidgets(
    'convert tx small',
    (t) => _shot(
      t,
      'notes_convert_tx_small',
      '/notes/c',
      size: small,
      textScale: 1.3,
      act: (t, _) async {
        await _tap(t, 'note-convert');
        await _tap(t, 'convert-transaction');
      },
    ),
  );
  testWidgets(
    'share sheet',
    (t) => _shot(
      t,
      'notes_share_sheet',
      '/',
      share: true,
      act: (t, h) async {
        h.share.share(
          const SharedPayload(
            title: 'Cara bikin kopi susu gula aren',
            text: 'Resep simpel buat jualan',
            urls: ['https://contoh.id/kopi'],
          ),
        );
        await settle(t, 8);
      },
    ),
  );
  testWidgets(
    'share sheet dark small',
    (t) => _shot(
      t,
      'notes_share_sheet_small_dark',
      '/',
      share: true,
      dark: true,
      size: small,
      textScale: 1.3,
      act: (t, h) async {
        h.share.share(
          const SharedPayload(
            title: 'Cara bikin kopi susu gula aren',
            text: 'Resep simpel buat jualan',
            urls: ['https://contoh.id/kopi'],
          ),
        );
        await settle(t, 8);
      },
    ),
  );
  testWidgets('labels', (t) => _shot(t, 'notes_labels', '/notes/labels'));
  testWidgets(
    'labels small dark',
    (t) => _shot(
      t,
      'notes_labels_small_dark',
      '/notes/labels',
      dark: true,
      size: small,
      textScale: 1.3,
    ),
  );
}
