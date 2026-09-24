// Notes + content planner over the real drift DB and the fake server
// (docs/notes.md, docs/content.md, docs/mobile-sync.md).
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/models/notes_content_mappers.dart';
import 'package:ghina/di/game_overrides.dart' show contentActivityEventsFrom;
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/game/activity.dart';
import 'package:ghina/domain/usecases/usecases.dart';

import '../harness.dart';

void main() {
  late Harness h;

  setUp(() => h = Harness());
  tearDown(() => h.close());

  Future<void> setOwner(String userId) =>
      h.db.updateMeta(SyncMetaCompanion(userId: Value(userId)));

  Future<Note> note(NoteInput i) async {
    h.tick();
    return (await h.createNote(i)).valueOrThrow;
  }

  Future<String> account(
    String handle, {
    SocialPlatform p = SocialPlatform.instagram,
    int? target,
  }) async {
    h.tick();
    return (await h.createAccount(
      SocialAccountInput(platform: p, handle: handle, targetPerWeek: target),
    )).valueOrThrow.id;
  }

  Future<ContentItem> contentItem(String title, {String? pillar}) async {
    h.tick();
    return (await h.createItem(
      ContentItemInput(title: title, pillar: pillar),
    )).valueOrThrow;
  }

  Json row(String entity, String id) => h.server.rows[entity]![id]!;

  group('notes sync', () {
    test(
      'offline note with photo + voice clip: uploads first, JSON on the wire',
      () async {
        h.server.online = false;
        final l = (await h.createLabel(
          const NoteLabelInput(name: 'Belanja'),
        )).valueOrThrow;
        final n = await note(
          NoteInput(
            title: 'Belanja',
            body: 'Lihat https://toko.id/a',
            checklist: const [ChecklistItem(id: 'c1', text: 'Telur')],
            labelIds: [l.id],
            color: 'green',
            photos: const [TransactionPhoto.local('/tmp/foto1.jpg')],
            audio: const [
              NoteAudio.local(
                '/tmp/rec1.m4a',
                durationSec: 42,
                transcript: 'beli telur',
              ),
            ],
            source: NoteSource.voice,
          ),
        );
        expect((await h.notes.getById(n.id))!.hasPendingUploads, isTrue);
        await expectLater(h.engine.syncNow(), throwsA(isA<NetworkFailure>()));
        expect(h.server.pushed, isEmpty);

        h.server.online = true;
        await h.engine.syncNow();
        final s = row(SyncEntity.notes, n.id);
        expect(s['photos'], ['/uploads/0-foto1.jpg']);
        expect(s['audio'], [
          {
            'url': '/uploads/1-rec1.m4a',
            'durationSec': 42,
            'transcript': 'beli telur',
          },
        ]);
        expect(s['checklist'], [
          {'id': 'c1', 'text': 'Telur', 'done': false},
        ]);
        expect(s['labels'], [l.id]);
        expect(s['links'], [
          {'url': 'https://toko.id/a', 'title': null},
        ]);
        expect(s['color'], 'green');
        expect(s['source'], 'voice');
        final local = (await h.notes.getById(n.id))!;
        expect(local.photos, [
          const TransactionPhoto.remote('/uploads/0-foto1.jpg'),
        ]);
        expect(local.audio.single.url, '/uploads/1-rec1.m4a');
        expect(local.audio.single.transcript, 'beli telur');
        expect(
          h.photos.deleted,
          containsAll(['/tmp/foto1.jpg', '/tmp/rec1.m4a']),
        );
        expect(await h.outboxCount(), 0);
        // Label upsert went before the note.
        final order = [for (final m in h.server.pushed) m.entity];
        expect(
          order.indexOf(SyncEntity.noteLabels),
          lessThan(order.indexOf(SyncEntity.notes)),
        );
      },
    );

    test('a clip added to a synced note is uploaded and pushed', () async {
      final n = await note(const NoteInput(body: 'Rapat'));
      await h.engine.syncNow();
      h.tick();
      await h.addNoteAudio(
        n.id,
        const NoteAudioInput(path: '/tmp/r2.m4a', durationSec: 5),
      );
      await h.engine.syncNow();
      expect(
        (row(SyncEntity.notes, n.id)['audio'] as List).single['url'],
        '/uploads/0-r2.m4a',
      );
      expect(h.server.rejected, isEmpty);
    });

    test(
      'server refuses a clip (4xx) → dropped with an error, transcript kept in the body',
      () async {
        h.server.uploadErrors['/tmp/bad.m4a'] = const ValidationFailure(
          'File type not allowed',
        );
        final n = await note(
          const NoteInput(
            body: 'Catatan',
            audio: [
              NoteAudio.local(
                '/tmp/bad.m4a',
                durationSec: 3,
                transcript: 'jangan hilang',
              ),
            ],
          ),
        );
        await h.engine.syncNow();
        final s = row(SyncEntity.notes, n.id);
        expect(s['audio'], isEmpty);
        expect(s['body'], 'Catatan\n\njangan hilang');
        expect((await h.notes.getById(n.id))!.audio, isEmpty);
        expect(
          (await h.db.getMeta()).lastError,
          contains('Rekaman suara gagal diunggah'),
        );
      },
    );

    test('an image returned where audio was expected is dropped', () async {
      h.server.uploadAs['/tmp/fake.m4a'] = '/uploads/x.jpg';
      final n = await note(
        const NoteInput(
          body: 'x',
          audio: [NoteAudio.local('/tmp/fake.m4a', durationSec: 1)],
        ),
      );
      await h.engine.syncNow();
      expect(row(SyncEntity.notes, n.id)['audio'], isEmpty);
      expect((await h.db.getMeta()).lastError, contains('jenis file'));
    });

    test(
      'a missing local file is dropped instead of blocking the push',
      () async {
        h.photos.missing.add('/tmp/gone.jpg');
        final n = await note(
          const NoteInput(
            body: 'x',
            photos: [TransactionPhoto.local('/tmp/gone.jpg')],
          ),
        );
        await h.engine.syncNow();
        expect(row(SyncEntity.notes, n.id)['photos'], isEmpty);
        expect((await h.db.getMeta()).lastError, contains('hilang'));
      },
    );

    test('a 5xx keeps the clip pending and retries', () async {
      h.server.uploadErrors['/tmp/a.m4a'] = const UnknownFailure(
        'Server bermasalah (500)',
      );
      final n = await note(
        const NoteInput(
          body: 'x',
          audio: [NoteAudio.local('/tmp/a.m4a', durationSec: 1)],
        ),
      );
      await expectLater(h.engine.syncNow(), throwsA(isA<UnknownFailure>()));
      expect((await h.notes.getById(n.id))!.audio.single.isPending, isTrue);
      expect(h.server.pushed, isEmpty);
      h.server.uploadErrors.clear();
      await h.engine.syncNow();
      expect(row(SyncEntity.notes, n.id)['audio'], hasLength(1));
    });

    test('pull keeps pending clips/photos of the local row', () async {
      final n = await note(const NoteInput(body: 'x'));
      await h.engine.syncNow();
      h.server.online = false;
      h.tick();
      await h.addNotePhotos(n.id, ['/tmp/p9.jpg']);
      // Simulate a pull of the server row while the photo waits (no pending
      // entry after a crash): drop the outbox, pull.
      await h.db.delete(h.db.outbox).go();
      h.server.online = true;
      h.server.web(SyncEntity.notes, n.id, {
        ...row(SyncEntity.notes, n.id),
        'title': 'Web',
      });
      await h.engine.pullOnly();
      final local = (await h.notes.getById(n.id))!;
      expect(local.title, 'Web');
      expect(local.photos, [const TransactionPhoto.local('/tmp/p9.jpg')]);
    });

    test(
      'pulled rows from the web land locally, JSON fields and all',
      () async {
        h.server.web(SyncEntity.noteLabels, 'lab', {
          'name': 'Kerja',
          'color': '#123456',
          'pinnedTab': true,
          'sortOrder': 2,
        });
        h.server.web(SyncEntity.notes, 'nw', {
          'title': 'Dari web',
          'body': 'Isi',
          'checklist': [
            {'id': 'x', 'text': 'Satu', 'done': true},
          ],
          'labels': ['lab'],
          'color': 'blue',
          'pinned': true,
          'archived': false,
          'photos': ['/uploads/a.jpg'],
          'audio': [
            {
              'url': '/uploads/b.m4a',
              'durationSec': 12.5,
              'transcript': 'halo',
            },
          ],
          'links': [
            {'url': 'https://x.id', 'title': 'X'},
          ],
          'source': 'share',
          'linkedTaskId': null,
          'linkedContentId': null,
          'linkedTransactionId': null,
        });
        await h.engine.syncNow();
        final n = (await h.notes.getById('nw'))!;
        expect(n.checklist.single.done, isTrue);
        expect(n.labelIds, ['lab']);
        expect(n.audio.single.durationSec, 13);
        expect(n.audio.single.transcript, 'halo');
        expect(n.links.single.title, 'X');
        expect(n.source, NoteSource.share);
        expect((await h.labels.getById('lab'))!.pinnedTab, isTrue);
        // Search in SQL: transcript + link title.
        final found = await WatchNotes(h.notes, h.labels)(
          const NoteFilter(search: 'HALO x'),
        ).first;
        expect(found.single.labels.single.name, 'Kerja');
      },
    );

    test(
      'search: every word, title/body/checklist/transcript; label + archive filters',
      () async {
        final l = (await h.createLabel(
          const NoteLabelInput(name: 'Resep'),
        )).valueOrThrow;
        await note(
          NoteInput(
            title: 'Nasi goreng',
            labelIds: [l.id],
            checklist: const [ChecklistItem(id: 'a', text: 'Kecap 100% manis')],
          ),
        );
        await note(const NoteInput(body: 'Sate', archived: true));
        await note(
          const NoteInput(
            body: 'lain',
            audio: [
              NoteAudio.remote(
                '/uploads/a.m4a',
                durationSec: 1,
                transcript: 'pakai telur',
              ),
            ],
          ),
        );
        Future<List<String>> q(NoteFilter f) async => [
          for (final v in await WatchNotes(h.notes, h.labels)(f).first)
            v.note.displayTitle,
        ];
        expect(await q(const NoteFilter(search: 'goreng kecap')), [
          'Nasi goreng',
        ]);
        expect(await q(const NoteFilter(search: '100%')), ['Nasi goreng']);
        expect(await q(const NoteFilter(search: '_')), isEmpty);
        expect(await q(const NoteFilter(search: 'telur')), ['lain']);
        expect(await q(const NoteFilter(search: 'sate')), isEmpty);
        expect(await q(const NoteFilter(search: 'sate', archived: null)), [
          'Sate',
        ]);
        expect(await q(NoteFilter.label(l.id)), ['Nasi goreng']);
        expect(await q(NoteFilter.archive), ['Sate']);
      },
    );

    test(
      'old server (no notes keys): local notes kept, nothing seeded',
      () async {
        await setOwner('u1');
        h.server.preNotes = true;
        // A note stored earlier (already pushed elsewhere): a full pull from an
        // old server leaves the unknown entity alone.
        final now = h.clock.now();
        await h.db
            .into(h.db.notes)
            .insert(
              Note(
                id: 'n1',
                body: 'offline',
                createdAt: now,
                updatedAt: now,
              ).toCompanion(),
            );
        await h.db.updateMeta(
          const SyncMetaCompanion(fullPullRequired: Value(true)),
        );
        await h.engine.syncNow();
        expect(await h.notes.getAll(), hasLength(1));
        expect((await h.db.getMeta()).notesSeeded, isFalse);
        expect(await h.labels.getAll(), isEmpty);
      },
    );

    test(
      'label name clash (duplicate): the note moves to the server label',
      () async {
        h.server.web(SyncEntity.noteLabels, 'srvL', {
          'name': 'kerja',
          'color': '#58CC02',
          'pinnedTab': false,
          'sortOrder': 0,
        });
        final l = (await h.createLabel(
          const NoteLabelInput(name: 'Kerja'),
        )).valueOrThrow;
        final n = await note(NoteInput(body: 'x', labelIds: [l.id]));
        await h.engine.syncNow();
        await h.engine.syncNow();
        expect(await h.labels.getById(l.id), isNull);
        expect((await h.notes.getById(n.id))!.labelIds, ['srvL']);
        expect(row(SyncEntity.notes, n.id)['labels'], ['srvL']);
        expect(await h.outboxCount(), 0);
      },
    );
  });

  group('default label and pillars', () {
    test(
      'the server seeds; after a notes-aware pull the app never seeds',
      () async {
        await setOwner('u1');
        h.server.seedNotesFor = 'u1';
        h.server.seedAreasFor = 'u1';
        await h.engine.syncNow();
        expect((await h.labels.getAll()).single.id, 'label-ide-konten-u1');
        expect((await h.pillars.getAll()).map((p) => p.name), [
          'Edukasi',
          'Hiburan',
          'Promo',
          'Behind the scene',
          'Personal',
        ]);
        final meta = await h.db.getMeta();
        expect([meta.notesSeeded, meta.contentSeeded], [true, true]);
        expect([
          for (final o in await h.outbox.all()) '${o.entity}/${o.entityId}',
        ], isEmpty);

        // The user deletes the default label and all pillars: they stay gone.
        h.tick();
        await h.deleteLabel('label-ide-konten-u1');
        for (final p in await h.pillars.getAll()) {
          h.tick();
          await h.deletePillar(p.id);
        }
        await h.engine.syncNow();
        expect((await h.seedLabel('u1')).valueOrThrow, 0);
        expect((await h.seedPillars('u1')).valueOrThrow, 0);
        await h.engine.syncNow();
        expect(await h.labels.getAll(), isEmpty);
        expect(await h.pillars.getAll(), isEmpty);
        expect(h.server.rows[SyncEntity.noteLabels], isEmpty);
      },
    );

    test(
      'offline fallback before the first pull; the server copy wins',
      () async {
        await setOwner('u1');
        expect((await h.seedLabel('u1')).valueOrThrow, 1);
        expect((await h.seedLabel('u1')).valueOrThrow, 0);
        expect((await h.seedPillars('u1')).valueOrThrow, 5);
        final l = (await h.labels.getById('label-ide-konten-u1'))!;
        expect([l.name, l.color, l.pinnedTab], ['Ide Konten', '#CE82FF', true]);
        // The server already seeded (and the user renamed a pillar on the web).
        h.server.seedNotesFor = 'u1';
        h.server.web(SyncEntity.contentPillars, 'pillar-promo-u1', {
          'name': 'Jualan',
          'color': '#FF4B4B',
          'sortOrder': 2,
        });
        await h.engine.syncNow(); // push: skipped (older) → full pull
        await h.engine.syncNow();
        expect((await h.pillars.getById('pillar-promo-u1'))!.name, 'Jualan');
        expect(h.server.rows[SyncEntity.contentPillars], hasLength(5));
        expect(h.server.rows[SyncEntity.noteLabels], hasLength(1));
        expect(await h.outboxCount(), 0);
      },
    );

    test(
      'fallback seed of a default the user deleted on the web does not resurrect it',
      () async {
        await setOwner('u1');
        h.server.web(SyncEntity.noteLabels, 'label-ide-konten-u1', {
          'name': 'Ide Konten',
          'color': '#CE82FF',
          'pinnedTab': true,
          'sortOrder': 0,
        });
        h.server.webDelete(SyncEntity.noteLabels, 'label-ide-konten-u1');
        expect((await h.seedLabel('u1')).valueOrThrow, 1);
        await h.engine.syncNow();
        await h.engine.syncNow();
        expect(await h.labels.getAll(), isEmpty);
        expect(h.server.rows[SyncEntity.noteLabels], isEmpty);
      },
    );
  });

  group('content sync', () {
    test(
      'account, item (sponsor/photos), post: order, JSON, auto-advance pushed',
      () async {
        h.server.online = false;
        final a = await account('ghina', target: 3);
        final i = await contentItem('Review HP', pillar: 'Edukasi');
        h.tick();
        await h.addContentPhotos(i.id, ['/tmp/thumb.jpg']);
        h.tick();
        await h.setSponsor(
          i.id,
          SponsorInput(
            brand: 'Kopi',
            amount: 1500000,
            due: DateTime(2026, 10, 1),
          ),
        );
        h.tick();
        final p = (await h.createPost(
          i.id,
          ContentPostInput(
            accountId: a,
            caption: 'Halo',
            hashtags: '#a',
            scheduledAt: DateTime(2026, 9, 25, 19),
            remindBefore: 30,
          ),
        )).valueOrThrow;
        expect((await h.items.getById(i.id))!.stage, ContentStage.terjadwal);
        h.server.online = true;
        await h.engine.syncNow();
        final si = row(SyncEntity.contentItems, i.id);
        expect(si['stage'], 'terjadwal');
        expect(si['photos'], ['/uploads/0-thumb.jpg']);
        expect(si['sponsor'], {
          'brand': 'Kopi',
          'amount': 1500000.0,
          'currency': 'IDR',
          'due': '2026-10-01',
          'paid': false,
          'transactionId': null,
        });
        expect(si['pillar'], 'Edukasi');
        final sp = row(SyncEntity.contentPosts, p.id);
        expect(sp['status'], 'scheduled');
        expect(
          sp['scheduledAt'],
          DateTime(2026, 9, 25, 19).toUtc().toIso8601String(),
        );
        expect(sp['metrics'], isEmpty);
        expect(row(SyncEntity.socialAccounts, a)['targetPerWeek'], 3);
        final order = [for (final m in h.server.pushed) m.entity];
        expect(
          order.indexOf(SyncEntity.socialAccounts),
          lessThan(order.indexOf(SyncEntity.contentPosts)),
        );
        expect(
          order.indexOf(SyncEntity.contentItems),
          lessThan(order.indexOf(SyncEntity.contentPosts)),
        );
        expect(h.server.rejected, isEmpty);

        // Posted on every account → tayang; metrics.
        h.tick();
        await h.markPosted(p.id, url: 'https://instagram.com/p/x');
        h.tick();
        await SetPostMetrics(h.posts, h.clock)(
          p.id,
          const PostMetrics(views: 100, likes: 7),
        );
        await h.engine.syncNow();
        expect(row(SyncEntity.contentItems, i.id)['stage'], 'tayang');
        expect(row(SyncEntity.contentPosts, p.id)['metrics'], {
          'views': 100,
          'likes': 7,
        });
        expect(row(SyncEntity.contentPosts, p.id)['postedAt'], isNotNull);
        final log = (await h.items.getById(i.id))!.stageReachedAt;
        expect(
          log.keys,
          containsAll([ContentStage.terjadwal, ContentStage.tayang]),
        );
      },
    );

    test(
      'pulled rows land locally; stages first seen by a pull get updatedAt',
      () async {
        h.server.web(SyncEntity.socialAccounts, 'sa', {
          'platform': 'tiktok',
          'platformName': null,
          'handle': '@g',
          'color': '#FE2C55',
          'targetPerWeek': 2,
          'archived': false,
          'sortOrder': 0,
        });
        h.server.web(SyncEntity.contentItems, 'ci', {
          'title': 'Web',
          'stage': 'siap',
          'format': 'reel',
          'pillar': 'Promo',
          'idea': '',
          'noteId': null,
          'checklist': [],
          'photos': [],
          'assetLinks': [
            {'url': 'https://canva.com/x', 'label': null},
          ],
          'sponsor': {
            'brand': 'B',
            'amount': 0,
            'currency': 'IDR',
            'due': null,
            'paid': false,
            'transactionId': null,
          },
        });
        h.server.web(SyncEntity.contentPosts, 'cp', {
          'contentId': 'ci',
          'accountId': 'sa',
          'caption': 'c',
          'hashtags': '',
          'scheduledAt': null,
          'remindBefore': null,
          'status': 'posted',
          'postedAt': '2026-09-22T12:00:00.000Z',
          'url': null,
          'metrics': {'views': 5},
          'metricsAt': null,
        });
        await h.engine.syncNow();
        final v = (await WatchContentItem(
          h.items,
          h.posts,
          h.accounts,
          h.notes,
        )('ci').first)!;
        expect(v.item.format, ContentFormat.reel);
        expect(v.item.sponsor!.amount, 0);
        expect(v.item.assetLinks.single.label, isNull);
        expect(v.posts.single.code, 'TT');
        expect(v.posts.single.post.metrics.views, 5);
        final updatedAt = DateTime.parse(
          row(SyncEntity.contentItems, 'ci')['updatedAt'] as String,
        ).toLocal();
        expect(v.item.stageReachedAt[ContentStage.siap], updatedAt);
        expect(v.item.stageReachedAt.containsKey(ContentStage.tayang), isFalse);
      },
    );

    test(
      'a post whose account is missing on the server is rejected, then restored',
      () async {
        final a = await account('x');
        final i = await contentItem('A');
        await h.engine.syncNow();
        h.server.webDelete(SyncEntity.socialAccounts, a);
        h.tick();
        await h.createPost(i.id, ContentPostInput(accountId: a));
        await h.engine.syncNow();
        expect(h.server.rejected.single.$2, 'Akun tidak ditemukan');
        await h.engine.syncNow();
        expect(await h.posts.getAll(), isEmpty);
        expect(await h.accounts.getAll(), isEmpty);
      },
    );
  });

  group('conversions', () {
    test('note → content in the same offline batch keeps both links', () async {
      h.server.online = false;
      final n = await note(
        const NoteInput(
          title: 'Ide reel',
          body: 'Hook dulu',
          checklist: [ChecklistItem(id: 'a', text: 'Rekam')],
          photos: [TransactionPhoto.local('/tmp/n1.jpg')],
        ),
      );
      h.tick();
      final r = (await h.noteToContent(
        n.id,
        format: ContentFormat.reel,
      )).valueOrThrow;
      expect(r.item.noteId, n.id);
      expect(r.item.title, 'Ide reel');
      expect(r.item.idea, 'Hook dulu');
      expect(r.item.checklist, n.checklist);
      expect(r.note.linkedContentId, r.item.id);
      // Idempotent.
      expect((await h.noteToContent(n.id)).valueOrThrow.item.id, r.item.id);
      h.server.online = true;
      await h.engine.syncNow();
      await h.engine.syncNow(); // the re-queued note (forward link)
      expect(row(SyncEntity.contentItems, r.item.id)['noteId'], n.id);
      expect(row(SyncEntity.notes, n.id)['linkedContentId'], r.item.id);
      expect(row(SyncEntity.contentItems, r.item.id)['photos'], hasLength(1));
      expect(await h.outboxCount(), 0);
      // Idea inbox: converted notes leave it.
      final lab = (await h.createLabel(
        const NoteLabelInput(name: 'Ide Konten'),
      )).valueOrThrow;
      final idea = await note(NoteInput(body: 'baru', labelIds: [lab.id]));
      h.tick();
      await SetNoteLabels(h.notes, h.clock)(n.id, [lab.id]);
      final inbox = await WatchIdeaInbox(h.notes, h.labels)().first;
      expect(inbox.map((x) => x.id), [idea.id]);
    });

    test(
      'note → task: title, plain-text note, linked; deleting the task unlinks',
      () async {
        final area = (await h.createArea(
          const TaskAreaInput(name: 'Kerja', code: 'KERJA'),
        )).valueOrThrow;
        final n = await note(
          const NoteInput(body: '# Kirim **revisi**\n- cek font'),
        );
        h.tick();
        final r = (await h.noteToTask(
          n.id,
          NoteTaskInput(areaId: area.id, bucket: TaskBucket.fire),
        )).valueOrThrow;
        expect(r.task.title, 'Kirim revisi');
        expect(r.task.note, 'Kirim revisi\ncek font');
        expect(r.note.linkedTaskId, r.task.id);
        await h.engine.syncNow();
        expect(row(SyncEntity.notes, n.id)['linkedTaskId'], r.task.id);
        h.tick();
        await DeleteTask(h.tasks)(r.task.id);
        expect((await h.notes.getById(n.id))!.linkedTaskId, isNull);
        await h.engine.syncNow();
        expect(row(SyncEntity.notes, n.id)['linkedTaskId'], isNull);
      },
    );

    test(
      'note → transaction: prefill, photos shared, linked; tx delete unlinks',
      () async {
        final w = await h.newWallet('Tunai', 100000);
        final n = await note(
          const NoteInput(
            title: 'Parkir',
            body: 'Rp 5.000',
            photos: [TransactionPhoto.local('/tmp/bon.jpg')],
          ),
        );
        final d = noteTransactionDraft(n);
        expect(d.amount, 5000);
        h.tick();
        final r = (await h.noteToTx(
          n.id,
          TransactionInput(
            type: TxType.expense,
            amount: d.amount!,
            walletId: w,
            note: d.note,
            date: h.clock.now(),
            photos: d.photos,
          ),
        )).valueOrThrow;
        expect(r.note.linkedTransactionId, r.transaction.id);
        expect(r.transaction.photos.single.isPending, isTrue);
        await h.engine.syncNow();
        expect(
          row(SyncEntity.notes, n.id)['linkedTransactionId'],
          r.transaction.id,
        );
        expect(
          row(SyncEntity.transactions, r.transaction.id)['photos'],
          hasLength(1),
        );
        h.tick();
        await h.deleteTx(r.transaction.id);
        expect((await h.notes.getById(n.id))!.linkedTransactionId, isNull);
      },
    );

    test(
      'sponsor paid → income transaction linked; tx delete keeps paid',
      () async {
        final w = await h.newWallet('BCA', 0);
        final i = await contentItem('Endorse');
        h.tick();
        await h.setSponsor(
          i.id,
          const SponsorInput(brand: 'Kopi Kita', amount: 250000),
        );
        h.tick();
        final r = (await h.markSponsorPaid(
          i.id,
          record: SponsorPayment(walletId: w),
        )).valueOrThrow;
        expect(r.transaction!.type, TxType.income);
        expect(r.transaction!.note, 'Endorse Kopi Kita');
        expect(r.item.sponsor!.paid, isTrue);
        expect(r.item.sponsor!.transactionId, r.transaction!.id);
        expect((await h.wallet(w)).balance, 250000);
        // Never a second transaction.
        h.tick();
        expect(
          (await h.markSponsorPaid(
            i.id,
            record: SponsorPayment(walletId: w),
          )).valueOrThrow.transaction,
          isNull,
        );
        await h.engine.syncNow();
        expect(
          (row(SyncEntity.contentItems, i.id)['sponsor']
              as Map)['transactionId'],
          r.transaction!.id,
        );
        h.server.webDelete(SyncEntity.transactions, r.transaction!.id);
        await h.engine.syncNow();
        final s = (await h.items.getById(i.id))!.sponsor!;
        expect([s.paid, s.transactionId], [true, null]);
        // A bad record rolls everything back.
        final j = await contentItem('Lain');
        h.tick();
        await h.setSponsor(j.id, const SponsorInput(brand: 'B', amount: 0));
        final bad = await h.markSponsorPaid(
          j.id,
          record: SponsorPayment(walletId: w),
        );
        expect(bad.failureOrNull, isA<ValidationFailure>());
        expect((await h.items.getById(j.id))!.sponsor!.paid, isFalse);
      },
    );
  });

  group('cascades', () {
    test(
      'local deletes: label, item, account, note, pillar (+ rename)',
      () async {
        final l = (await h.createLabel(
          const NoteLabelInput(name: 'Tag'),
        )).valueOrThrow;
        final n = await note(NoteInput(body: 'x', labelIds: [l.id]));
        final a = await account('a');
        final b = await account('b');
        h.tick();
        final pill = (await h.createPillar(
          const ContentPillarInput(name: 'Edukasi'),
        )).valueOrThrow;
        final i = await contentItem('I', pillar: 'edukasi');
        h.tick();
        await h.createPost(i.id, ContentPostInput(accountId: a));
        h.tick();
        await h.createPost(i.id, ContentPostInput(accountId: b));
        h.tick();
        final conv = (await h.noteToContent(n.id)).valueOrThrow;
        await h.engine.syncNow();

        h.tick();
        await h.deleteLabel(l.id);
        expect((await h.notes.getById(n.id))!.labelIds, isEmpty);
        h.tick();
        await h.deleteAccount(b);
        expect((await h.posts.getAll()).map((p) => p.accountId), [a]);
        h.tick();
        await h.updatePillar(
          pill.id,
          const ContentPillarInput(name: 'Tutorial'),
        );
        expect((await h.items.getById(i.id))!.pillar, 'Tutorial');
        h.tick();
        await h.deletePillar(pill.id);
        expect((await h.items.getById(i.id))!.pillar, isNull);
        h.tick();
        await h.deleteItem(i.id);
        expect(await h.posts.getAll(), isEmpty);
        h.tick();
        await h.deleteNote(n.id);
        expect((await h.items.getById(conv.item.id))!.noteId, isNull);
        await h.engine.syncNow();
        expect(h.server.rows[SyncEntity.contentPosts], isEmpty);
        expect(row(SyncEntity.contentItems, conv.item.id)['noteId'], isNull);
        expect(h.server.rejected, isEmpty);
        expect(await h.outboxCount(), 0);
      },
    );

    test('tombstones from the web apply the same cascades', () async {
      final l = (await h.createLabel(
        const NoteLabelInput(name: 'Tag'),
      )).valueOrThrow;
      final n = await note(NoteInput(body: 'x', labelIds: [l.id]));
      final a = await account('a');
      final i = await contentItem('I', pillar: 'Promo');
      h.tick();
      await h.createPillar(const ContentPillarInput(name: 'Promo'));
      h.tick();
      await h.createPost(i.id, ContentPostInput(accountId: a));
      h.tick();
      final conv = (await h.noteToContent(n.id)).valueOrThrow;
      await h.engine.syncNow();
      await h.engine.syncNow();

      h.server.webDelete(SyncEntity.noteLabels, l.id);
      h.server.webDelete(SyncEntity.socialAccounts, a);
      final pillarId = h.server.rows[SyncEntity.contentPillars]!.keys.single;
      h.server.webDelete(SyncEntity.contentPillars, pillarId);
      h.server.webDelete(SyncEntity.contentItems, conv.item.id);
      await h.engine.syncNow();
      expect((await h.notes.getById(n.id))!.labelIds, isEmpty);
      expect((await h.notes.getById(n.id))!.linkedContentId, isNull);
      expect(await h.posts.getAll(), isEmpty);
      expect((await h.items.getById(i.id))!.pillar, isNull);
      expect(await h.items.getById(conv.item.id), isNull);
      h.server.webDelete(SyncEntity.notes, n.id);
      await h.engine.syncNow();
      expect(await h.notes.getById(n.id), isNull);
    });
  });

  group('reminders + game events', () {
    test(
      'post reminders merge with task reminders: ≤ 60, soonest first',
      () async {
        final area = (await h.createArea(
          const TaskAreaInput(name: 'Kerja', code: 'KERJA'),
        )).valueOrThrow;
        final now = h.clock.now();
        for (var d = 1; d <= 50; d++) {
          final day = DateTime(now.year, now.month, now.day + d);
          h.tick();
          await h.createTask(
            TaskInput(
              areaId: area.id,
              title: 'T$d',
              dueDate: day,
              dueTime: '09:00',
              remindBefore: 0,
            ),
          );
        }
        final a = await account('ig');
        for (var d = 0; d < 20; d++) {
          final i = await contentItem('Konten $d');
          h.tick();
          await h.createPost(
            i.id,
            ContentPostInput(
              accountId: a,
              scheduledAt: DateTime(now.year, now.month, now.day + d + 1, 8),
              remindBefore: 0,
            ),
          );
        }
        final r = await WatchReminders(
          h.tasks,
          h.taskAreas,
          h.ticks,
          posts: h.posts,
          items: h.items,
          accounts: h.accounts,
        )().first;
        expect(r, hasLength(60));
        expect(r.first.title, '[IG-TAYANG] Konten 0');
        expect(r[1].title, startsWith('[KERJA-'));
        for (var k = 1; k < r.length; k++) {
          expect(r[k].fireAt.isBefore(r[k - 1].fireAt), isFalse);
        }
        expect(
          r.where((x) => x.key.startsWith('content-post-')),
          hasLength(20),
        );
        // Without content repos: tasks only (old behaviour).
        expect(
          await WatchReminders(h.tasks, h.taskAreas, h.ticks)().first,
          hasLength(50),
        );
      },
    );

    test(
      'content activity events: stages, posted (on schedule), weekly target, sponsor',
      () async {
        final w = await h.newWallet('BCA', 0);
        final a = await account('ig', target: 1);
        final i = await contentItem('A');
        h.tick();
        await h.moveStage(i.id, ContentStage.produksi);
        h.tick();
        final p = (await h.createPost(
          i.id,
          ContentPostInput(
            accountId: a,
            scheduledAt: h.clock.now().add(const Duration(hours: 2)),
          ),
        )).valueOrThrow;
        h.tick();
        await h.markPosted(p.id);
        h.tick();
        await h.setSponsor(i.id, const SponsorInput(brand: 'K', amount: 100));
        h.tick();
        final paid = (await h.markSponsorPaid(
          i.id,
          record: SponsorPayment(walletId: w),
        )).valueOrThrow;
        // Moving back and forth never changes when a stage was reached.
        final item = (await h.items.getById(i.id))!;
        final reached = item.stageReachedAt[ContentStage.naskah]!;
        h.tick();
        await h.moveStage(i.id, ContentStage.ide);
        h.tick();
        await h.moveStage(i.id, ContentStage.tayang);
        final after = (await h.items.getById(i.id))!;
        expect(after.stageReachedAt[ContentStage.naskah], reached);

        final events = contentActivityEventsFrom(
          [after],
          await h.posts.getAll(),
          await h.accounts.getAll(),
          transactions: [paid.transaction!],
        );
        final stages = events
            .where((e) => e.contentType == ContentEventType.stage)
            .toList();
        expect(stages.map((e) => e.contentStage), [
          'naskah',
          'produksi',
          'siap',
          'terjadwal',
          'tayang',
        ]);
        expect(stages.map((e) => e.contentStageXp), [3, 4, 5, 6, 10]);
        expect(stages.first.id, '${i.id}:naskah');
        expect(stages.first.at, reached);
        expect(stages.every((e) => e.kind == ActivityKind.content), isTrue);
        final posted = events.singleWhere(
          (e) => e.contentType == ContentEventType.posted,
        );
        expect(
          [posted.id, posted.contentOnSchedule, posted.contentPlatform],
          [p.id, true, 'instagram'],
        );
        final target = events.singleWhere(
          (e) => e.contentType == ContentEventType.weeklyTarget,
        );
        expect(target.contentTarget, 1);
        final sponsor = events.singleWhere(
          (e) => e.contentType == ContentEventType.sponsorPaid,
        );
        expect(sponsor.at, paid.transaction!.createdAt);
        expect(sponsor.amount, 100);
      },
    );
  });

  test(
    'v3 → v4 upgrade: the forced full pull brings notes the web already had',
    () async {
      h.server.web(SyncEntity.notes, 'old', {
        'title': 'Dari web',
        'body': '',
        'labels': [],
      });
      // The v3 app's cursor is past the note; the migration sets fullPullRequired.
      await h.db.updateMeta(
        SyncMetaCompanion(
          cursor: Value(
            h.clock.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
          ),
          epoch: const Value('epoch-1'),
        ),
      );
      await h.engine.pullOnly();
      expect(await h.notes.getAll(), isEmpty); // an incremental pull misses it
      await h.db.updateMeta(
        const SyncMetaCompanion(fullPullRequired: Value(true)),
      );
      await h.engine.pullOnly();
      expect((await h.notes.getById('old'))!.title, 'Dari web');
      expect((await h.db.getMeta()).fullPullRequired, isFalse);
    },
  );
}

typedef Json = Map<String, dynamic>;
