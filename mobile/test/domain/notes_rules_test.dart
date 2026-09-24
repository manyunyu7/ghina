// Parity with the server's notes module (`src/lib/notes.ts`), mirroring the
// cases of `scripts/test-notes.mjs` that apply on the device (docs/notes.md).
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/core/result.dart';
import 'package:ghina/data/models/notes_content_mappers.dart';
import 'package:ghina/data/models/notes_content_wire.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import 'fakes.dart';

void main() {
  final now = DateTime(2026, 9, 24, 10);
  late FakeNoteRepository repo;
  late CreateNote create;

  setUp(() {
    repo = FakeNoteRepository();
    create = CreateNote(repo, FixedClock(now));
  });

  Future<Note> ok(NoteInput i) async => (await create(i)).valueOrThrow;
  Future<String?> err(NoteInput i) async => switch (await create(i)) {
    Ok() => null,
    Err(:final failure) => failure.message,
  };

  group('note input (server noteSchema)', () {
    test(
      'a blank note is refused on the device (the editor discards it)',
      () async {
        final r = await create(const NoteInput());
        expect((r.failureOrNull! as ValidationFailure).field, 'empty');
      },
    );

    test('full note normalizes like the server', () async {
      final n = await ok(
        const NoteInput(
          title: '  Belanja\nbulanan  ',
          body: 'Beli **beras**\r\nlihat https://toko.id/beras.',
          checklist: [
            ChecklistItem(id: 'a', text: ' telur ', done: true),
            ChecklistItem(id: 'b', text: ''),
          ],
          labelIds: ['l1', 'l1', 'l2'],
          color: 'yellow',
          pinned: true,
          photos: [
            TransactionPhoto.remote('/uploads/abc.jpg'),
            TransactionPhoto.remote('/uploads/abc.jpg'),
          ],
          audio: [
            NoteAudio.remote(
              '/uploads/v1.m4a',
              durationSec: 12,
              transcript: '  halo  ',
            ),
          ],
          links: [NoteLink(url: 'https://x.id/a', title: 'A')],
          source: NoteSource.share,
        ),
      );
      expect(n.title, 'Belanja bulanan');
      expect(n.body, 'Beli **beras**\nlihat https://toko.id/beras.');
      expect(n.checklist, const [
        ChecklistItem(id: 'a', text: 'telur', done: true),
        ChecklistItem(id: 'b', text: ''),
      ]);
      expect(n.labelIds, ['l1', 'l2']);
      expect(n.photos, [const TransactionPhoto.remote('/uploads/abc.jpg')]);
      expect(n.audio.single.transcript, 'halo');
      expect(n.links, const [
        NoteLink(url: 'https://x.id/a', title: 'A'),
        NoteLink(url: 'https://toko.id/beras'),
      ]);
      expect(n.source, NoteSource.share);
      expect(n.color, 'yellow');
      expect(n.pinned, isTrue);
    });

    test('control characters are dropped from the body', () async {
      expect(
        (await ok(const NoteInput(body: 'a\u0000b\u0007c\td'))).body,
        'abc\td',
      );
    });

    test('limits', () async {
      expect(
        await err(NoteInput(title: 'x' * 201)),
        contains('Judul terlalu panjang'),
      );
      expect(await err(NoteInput(body: 'x' * 50000)), isNull);
      expect(await err(NoteInput(body: 'x' * 50001)), isNotNull);
      expect(
        await err(const NoteInput(body: 'a', color: '#ff0000')),
        'Warna catatan tidak valid',
      );
      final items = [
        for (var i = 0; i < 200; i++) ChecklistItem(id: 'i$i', text: 'x'),
      ];
      expect(await err(NoteInput(checklist: items)), isNull);
      expect(
        await err(
          NoteInput(
            checklist: [
              ...items,
              const ChecklistItem(id: 'z', text: 'x'),
            ],
          ),
        ),
        contains('Maksimal 200'),
      );
      expect(
        await err(
          NoteInput(
            body: 'a',
            photos: [
              for (var i = 0; i < 11; i++)
                TransactionPhoto.remote('/uploads/p$i.png'),
            ],
          ),
        ),
        contains('Maksimal 10 foto'),
      );
      expect(
        await err(
          const NoteInput(
            body: 'a',
            audio: [NoteAudio.remote('/uploads/a.m4a', durationSec: 611)],
          ),
        ),
        'Rekaman maksimal 10 menit',
      );
      expect(
        await err(
          const NoteInput(
            body: 'a',
            audio: [NoteAudio.remote('/uploads/a.m4a', durationSec: 605)],
          ),
        ),
        isNull,
      );
      expect(
        await err(
          NoteInput(
            body: 'a',
            audio: [
              for (var i = 0; i < 6; i++)
                NoteAudio.remote('/uploads/a$i.m4a', durationSec: 1),
            ],
          ),
        ),
        contains('Maksimal 5'),
      );
      expect(
        await err(
          NoteInput(body: 'a', labelIds: [for (var i = 0; i < 21; i++) 'l$i']),
        ),
        contains('Maksimal 20 label'),
      );
    });

    test('duplicate clip url kept once', () async {
      final n = await ok(
        const NoteInput(
          audio: [
            NoteAudio.remote('/uploads/a.m4a', durationSec: 1),
            NoteAudio.remote('/uploads/a.m4a', durationSec: 1),
          ],
        ),
      );
      expect(n.audio, hasLength(1));
    });

    test('checklist: duplicate / invalid ids never reach the server', () {
      // The server rejects them; the device keeps the first and drops bad ids.
      expect(
        normalizeChecklist(const [
          ChecklistItem(id: 'a', text: '1'),
          ChecklistItem(id: 'a', text: '2'),
          ChecklistItem(id: 'a b', text: '3'),
        ]),
        const [ChecklistItem(id: 'a', text: '1')],
      );
    });

    test('body URLs capped so links ≤ 20 (sent first)', () async {
      final body = [for (var i = 0; i < 25; i++) 'https://b.id/$i'].join(' ');
      final n = await ok(
        NoteInput(
          body: body,
          links: const [NoteLink(url: 'https://shared.id/', title: 'S')],
        ),
      );
      expect(n.links, hasLength(20));
      expect(n.links.first.url, 'https://shared.id/');
    });

    test(
      'update: body URLs removed from the body leave the links; shared stay',
      () async {
        final n = await ok(
          const NoteInput(
            body: 'a https://a.id/x b',
            links: [NoteLink(url: 'https://shared.id/', title: 'S')],
          ),
        );
        final u = (await UpdateNote(
          repo,
          FixedClock(now.add(const Duration(minutes: 1))),
        )(n.id, const NoteInput(body: 'baru https://b.id/y'))).valueOrThrow;
        expect(u.links.map((l) => l.url), [
          'https://shared.id/',
          'https://b.id/y',
        ]);
        expect(u.links.first.title, 'S');
      },
    );
  });

  group('wire (server upload paths)', () {
    test('photos must be image upload paths, audio must be audio paths', () {
      expect(
        wireMediaPhotos(const [
          TransactionPhoto.remote('/uploads/a.m4a'),
          TransactionPhoto.remote('/uploads/../x.png'),
          TransactionPhoto.remote('https://evil/a.png'),
          TransactionPhoto.remote('/uploads/ok-1.heic'),
          TransactionPhoto.local('/tmp/p.jpg'),
        ], 10),
        ['/uploads/ok-1.heic'],
      );
      expect(
        wireAudio(const [
          NoteAudio.remote('/uploads/a.png', durationSec: 1),
          NoteAudio.remote(
            '/uploads/abc-1.m4a',
            durationSec: 700,
            transcript: ' x ',
          ),
          NoteAudio.local('/tmp/r.m4a', durationSec: 3),
        ]),
        [
          {'url': '/uploads/abc-1.m4a', 'durationSec': 610, 'transcript': 'x'},
        ],
      );
      expect(uploadAudioRe.hasMatch('/uploads/abc-1.m4a'), isTrue);
      expect(uploadAudioRe.hasMatch('/uploads/abc.png'), isFalse);
      expect(uploadImageRe.hasMatch('/uploads/a.heic'), isTrue);
      expect(uploadImageRe.hasMatch('/uploads/a.svg'), isFalse);
    });

    test('stored column parsing is lenient', () {
      expect(decodeChecklist('{oops'), isEmpty);
      expect(decodeAudio(null), isEmpty);
      expect(decodeAudio('[{"url":"/uploads/a.ogg","durationSec":3}]'), [
        const NoteAudio.remote('/uploads/a.ogg', durationSec: 3),
      ]);
      final n = noteFromWire({
        'id': 'n1',
        'photos': ['/uploads/a.png', 5, 'local:/x.jpg'],
        'labels': '["l1","l1",3]',
        'checklist': [
          {'id': 'a', 'text': 'x'},
          {'text': 'no id'},
        ],
        'createdAt': '2026-09-24T00:00:00.000Z',
      });
      expect(n.photos, [const TransactionPhoto.remote('/uploads/a.png')]);
      expect(n.labelIds, ['l1']);
      expect(n.checklist, const [ChecklistItem(id: 'a', text: 'x')]);
      expect(n.body, '');
      expect(n.pinned, isFalse);
    });
  });

  group('URL extraction', () {
    test('markdown link + parens + punctuation', () {
      expect(
        extractUrls(
          'Lihat [ini](https://a.id/x) dan (https://b.id/y), juga '
          'https://c.id/z?q=1&r=2! https://wiki.id/Foo_(bar).',
        ),
        [
          'https://a.id/x',
          'https://b.id/y',
          'https://c.id/z?q=1&r=2',
          'https://wiki.id/Foo_(bar)',
        ],
      );
    });
    test('dedupe, order of appearance', () {
      expect(extractUrls('https://a.id https://b.id https://a.id'), [
        'https://a.id',
        'https://b.id',
      ]);
    });
    test('ignores non-http and bare domains', () {
      expect(extractUrls('ftp://x.id www.y.id mailto:a@b.id'), isEmpty);
    });
    test('mergeLinks keeps stored titles', () {
      expect(
        mergeLinks(
          const [NoteLink(url: 'https://a.id')],
          'https://b.id',
          stored: const [
            NoteLink(url: 'https://a.id', title: 'A'),
            NoteLink(url: 'https://b.id', title: 'B'),
          ],
        ),
        const [
          NoteLink(url: 'https://a.id', title: 'A'),
          NoteLink(url: 'https://b.id', title: 'B'),
        ],
      );
    });
    test('javascript: / credentials are not http URLs', () {
      expect(isHttpUrl('javascript:alert(1)'), isFalse);
      expect(isHttpUrl('https://u:p@x.id/'), isFalse);
      expect(isHttpUrl('https://x.id/a'), isTrue);
    });
  });

  group('labels', () {
    final l = NoteLabel(
      id: 'a',
      name: 'Ide Konten',
      createdAt: now,
      updatedAt: now,
    );
    test('name trimmed, 1–30, unique case-insensitively', () {
      expect(validateLabelName('  Kerjaan ', const []), 'Kerjaan');
      expect(
        () => validateLabelName('  ', const []),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => validateLabelName('x' * 31, const []),
        throwsA(isA<ValidationFailure>()),
      );
      expect(labelNameTaken([l], 'ide konten'), isTrue);
      expect(labelNameTaken([l], 'IDE KONTEN', exceptId: 'a'), isFalse);
    });
    test('stripLabel removes the id, keeps order', () {
      expect(stripLabel(['a', 'b', 'c'], 'b'), ['a', 'c']);
    });
    test('default label', () {
      final d = defaultNoteLabel('u1', now);
      expect(
        [d.id, d.name, d.color, d.pinnedTab, d.sortOrder],
        ['label-ide-konten-u1', 'Ide Konten', '#CE82FF', true, 0],
      );
      expect(defaultLabelId('u1'), 'label-ide-konten-u1');
      expect(findIdeaLabel([l]), l);
      expect(findIdeaLabel([d, l]), d);
    });
    test('toggle', () {
      expect(toggleLabelId(['a'], 'b'), ['a', 'b']);
      expect(toggleLabelId(['a', 'b'], 'a'), ['b']);
    });
  });

  group('checklist ops', () {
    const a = ChecklistItem(id: 'a', text: 'Satu');
    const b = ChecklistItem(id: 'b', text: 'Dua', done: true);
    test('add / toggle / text / remove / move / reorder / clear', () {
      var l = checklistAdd(const [a], ' Tiga\nbaris ', id: 'c');
      expect(l.last, const ChecklistItem(id: 'c', text: 'Tiga baris'));
      expect(checklistAdd(const [a], '', id: 'd', index: 0).first.text, '');
      l = checklistToggle([a, b], 'a');
      expect(l.first.done, isTrue);
      expect(checklistSetText([a], 'a', 'Baru').single.text, 'Baru');
      expect(checklistRemove([a, b], 'a'), [b]);
      expect(checklistMove([a, b], 0, 1), [b, a]);
      expect(checklistReorder([a, b], ['b']), [b, a]);
      expect(checklistClearDone([a, b]), [a]);
      expect(checklistUncheckAll([a, b]).every((c) => !c.done), isTrue);
      expect(
        () => checklistAdd(
          [for (var i = 0; i < 200; i++) ChecklistItem(id: '$i', text: 'x')],
          'y',
          id: 'z',
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => checklistSetText([a], 'a', 'x' * 1001),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('search / titles / sorting', () {
    final note = Note(
      id: 'n',
      title: 'Resep',
      body: 'Nasi **goreng**',
      checklist: const [ChecklistItem(id: 'a', text: 'Kecap manis')],
      audio: const [
        NoteAudio.remote(
          '/uploads/a.m4a',
          durationSec: 1,
          transcript: 'pakai telur',
        ),
      ],
      links: const [NoteLink(url: 'https://x.id', title: 'Dapur Umami')],
      createdAt: now,
      updatedAt: now,
    );
    test('title/body/checklist/transcript/link title; every word', () {
      for (final q in [
        'resep',
        'GORENG',
        'kecap',
        'telur',
        'umami',
        'nasi kecap',
      ]) {
        expect(noteMatches(note, q), isTrue, reason: q);
      }
      expect(noteMatches(note, 'sate'), isFalse);
      expect(noteMatches(note, '  '), isTrue);
    });
    test('firstLine strips markdown', () {
      expect(
        firstLine('\n\n## **Ide** [video](https://x.id) baru\nlain'),
        'Ide video baru',
      );
    });
    test('display/action title fallbacks', () {
      final n = Note(
        id: 'x',
        checklist: const [ChecklistItem(id: 'a', text: 'Beli susu')],
        createdAt: now,
        updatedAt: now,
      );
      expect(noteActionTitle(n), 'Beli susu');
      expect(
        noteActionTitle(Note(id: 'y', createdAt: now, updatedAt: now)),
        'Catatan',
      );
      expect(Note(id: 'y', createdAt: now, updatedAt: now).displayTitle, '');
    });
    test('bodyExcerpt', () {
      expect(
        bodyExcerpt('# Judul\n- satu\n- dua\n\n> kutip'),
        'Judul\nsatu\ndua\nkutip',
      );
    });
    test('compareNotes: pinned first then newest', () {
      Note n(String id, bool pinned, DateTime at) =>
          Note(id: id, pinned: pinned, createdAt: at, updatedAt: at);
      final a = n('a', false, DateTime.utc(2026, 9, 24, 10));
      final b = n('b', true, DateTime.utc(2026, 9, 1));
      final c = n('c', false, DateTime.utc(2026, 9, 24, 11));
      expect(([a, b, c]..sort(compareNotes)).map((x) => x.id), ['b', 'c', 'a']);
    });
  });

  group('amount parsing (→ Transaksi)', () {
    const cases = <(String, double?)>[
      ('Bayar listrik Rp 250.000', 250000),
      ('Rp1.250.000,50 untuk servis', 1250000.5),
      ('Rp 25rb parkir', 25000),
      ('jajan Rp. 15k', 15000),
      ('beli hp 1,5jt', 1500000),
      ('total 125000', 125000),
      ('total 125.000 tgl 12/09/2026 jam 10:30', 125000),
      ('Rp 10.000 dan Rp 20.000', null),
      ('Rp 10.000 lalu Rp10.000 lagi', 10000),
      ('2 kali 3 buah', null),
      ('tanggal 2026-09-12', null),
      ('beli 3 barang 45000 dan 60000', null),
    ];
    for (final (text, want) in cases) {
      test(
        'parseAmount("$text") = $want',
        () => expect(parseAmount(text), want),
      );
    }

    test('noteTransactionDraft: amount, title, first 5 photos', () {
      final n = Note(
        id: 'n',
        title: 'Parkir',
        body: 'Rp 5.000',
        photos: [
          for (var i = 0; i < 7; i++)
            TransactionPhoto.remote('/uploads/p$i.jpg'),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final d = noteTransactionDraft(n);
      expect(d.amount, 5000);
      expect(d.note, 'Parkir');
      expect(d.photos, hasLength(5));
    });
  });

  test('note colors: 11 palette ids with light/dark shades', () {
    expect(noteColors.map((c) => c.id), [
      'red',
      'orange',
      'yellow',
      'green',
      'teal',
      'blue',
      'darkblue',
      'purple',
      'pink',
      'brown',
      'gray',
    ]);
    expect(noteColorById('yellow')!.light, '#FFF8B8');
    expect(noteColorById('#fff'), isNull);
  });
}
