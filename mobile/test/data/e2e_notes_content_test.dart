// End-to-end: notes + content planner on the real mobile data layer (drift in
// memory, outbox, sync engine, repositories, use cases) on two simulated devices
// against the REAL server (docs/notes.md, docs/content.md, docs/mobile-sync.md).
// Skipped unless GHINA_E2E_BASE_URL is set:
//   (cd .. && npx next dev -p 3100)
//   GHINA_E2E_BASE_URL=http://localhost:3100 flutter test test/data/e2e_notes_content_test.dart
// Throwaway users `mobile-test-dart-nc-*@example.test` and their upload files are
// removed at the end (`node scripts/e2e-helper.mjs cleanup …`).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/data/datasources/local/app_database.dart';
import 'package:ghina/data/datasources/remote/api_client.dart';
import 'package:ghina/data/datasources/remote/auth_api.dart';
import 'package:ghina/data/datasources/remote/sync_api.dart';
import 'package:ghina/data/datasources/remote/token_store.dart';
import 'package:ghina/data/models/api_dto.dart';
import 'package:ghina/data/models/entity_names.dart';
import 'package:ghina/data/models/wire.dart' show Json;
import 'package:ghina/data/repositories/auth_repository_impl.dart';
import 'package:ghina/data/repositories/content_repositories.dart';
import 'package:ghina/data/repositories/finance_repositories.dart';
import 'package:ghina/data/repositories/local_store.dart';
import 'package:ghina/data/repositories/notes_repositories.dart';
import 'package:ghina/data/repositories/photo_store.dart';
import 'package:ghina/data/repositories/task_repositories.dart';
import 'package:ghina/data/sync/outbox.dart';
import 'package:ghina/data/sync/sync_engine.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/usecases/usecases.dart';

/// Real wall clock shifted by [offset] (device clocks differ; LWW uses them).
final class OffsetClock implements Clock {
  Duration offset = Duration.zero;
  @override
  DateTime now() => DateTime.now().add(offset);
}

const _password = 'rahasia123';
const emailPrefix = 'mobile-test-dart-nc-';

/// A 4×4 baseline JPEG (776 bytes).
final jpegBytes = base64Decode(
  '/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAABKADAAQAAAABAAAABAAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgABAAEAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMABgYGBgYGCgYGCg4KCgoOEg4ODg4SFxISEhISFxwXFxcXFxccHBwcHBwcHCIiIiIiIicnJycnLCwsLCwsLCwsLP/bAEMBBwcHCwoLEwoKEy4fGh8uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLv/dAAQAAf/aAAwDAQACEQMRAD8A86ooor44/pE//9k=',
);

/// The repo root (this test runs from `mobile/`).
final repoRoot = Directory.current.parent.path;

bool uploadExists(String url) => File('$repoRoot/public$url').existsSync();

Future<Json> helper(String cmd, String arg) async {
  final r = await Process.run('node', [
    'scripts/e2e-helper.mjs',
    cmd,
    arg,
  ], workingDirectory: repoRoot);
  if (r.exitCode != 0) throw StateError('helper $cmd failed: ${r.stderr}');
  return (jsonDecode((r.stdout as String).trim().split('\n').last) as Map)
      .cast<String, dynamic>();
}

/// A 0.5 s mono PCM WAV (valid audio, but not a type the server accepts).
Uint8List wavBytes() {
  const n = 4000;
  final b = ByteData(44 + n * 2);
  void s(int o, String v) {
    for (var i = 0; i < v.length; i++) {
      b.setUint8(o + i, v.codeUnitAt(i));
    }
  }

  s(0, 'RIFF');
  b.setUint32(4, 36 + n * 2, Endian.little);
  s(8, 'WAVE');
  s(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, 8000, Endian.little);
  b.setUint32(28, 16000, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  s(36, 'data');
  b.setUint32(40, n * 2, Endian.little);
  return b.buffer.asUint8List();
}

/// One simulated phone: its own in-memory database + the real data layer.
class Device {
  Device(String baseUrl, this.name) {
    api = ApiClient(baseUrl: baseUrl, tokens: tokens);
    syncApi = DioSyncApi(api);
    auth = AuthRepositoryImpl(api: AuthApi(api), tokens: tokens, db: db);
    engine = SyncEngine(
      db: db,
      outbox: outbox,
      api: syncApi,
      photos: photos,
      clock: clock,
    );
  }

  final String name;
  final tokens = MemoryTokenStore();
  late final ApiClient api;
  late final DioSyncApi syncApi;
  late final AuthRepositoryImpl auth;
  late final SyncEngine engine;
  final db = AppDatabase.memory();
  late final outbox = Outbox(db);
  final clock = OffsetClock();
  final photos = InMemoryPhotoStore();
  late final store = LocalStore(db, outbox, clock);
  late final wallets = DriftWalletRepository(store);
  late final categories = DriftCategoryRepository(store);
  late final txs = DriftTransactionRepository(store, photos);
  late final areas = DriftTaskAreaRepository(store);
  late final tasks = DriftTaskRepository(store);
  late final uow = DriftUnitOfWork(store);
  late final notes = DriftNoteRepository(store, photos);
  late final labels = DriftNoteLabelRepository(store);
  late final accounts = DriftSocialAccountRepository(store);
  late final items = DriftContentItemRepository(store, photos);
  late final posts = DriftContentPostRepository(store);
  late final pillars = DriftContentPillarRepository(store);
  late final seedState = DriftDefaultsSeedState(db);

  late final createWallet = CreateWallet(wallets, clock);
  late final createTx = CreateTransaction(txs, wallets, categories, clock);
  late final deleteTx = DeleteTransaction(txs);
  late final createTask = CreateTask(tasks, areas, wallets, categories, clock);
  late final deleteTask = DeleteTask(tasks);

  late final createNote = CreateNote(notes, clock);
  late final updateNote = UpdateNote(notes, clock);
  late final deleteNote = DeleteNote(notes);
  late final toggleCheck = ToggleNoteChecklistItem(notes, clock);
  late final setChecklist = SetNoteChecklist(notes, clock);
  late final toggleLabel = ToggleNoteLabel(notes, clock);
  late final addNotePhotos = AddNotePhotos(notes, clock);
  late final removeNotePhoto = RemoveNotePhoto(notes, clock);
  late final addNoteAudio = AddNoteAudio(notes, clock);
  late final removeNoteAudio = RemoveNoteAudio(notes, clock);
  late final createLabel = CreateNoteLabel(labels, clock);
  late final deleteLabel = DeleteNoteLabel(labels);
  late final seedLabel = SeedDefaultNoteLabel(labels, seedState, clock);
  late final noteToTask = ConvertNoteToTask(notes, createTask, uow, clock);
  late final noteToContent = ConvertNoteToContent(
    notes,
    items,
    createItem,
    uow,
    clock,
  );
  late final noteToTx = ConvertNoteToTransaction(notes, createTx, uow, clock);

  late final createAccount = CreateSocialAccount(accounts, clock);
  late final deleteAccount = DeleteSocialAccount(accounts);
  late final createPillar = CreateContentPillar(pillars, clock);
  late final updatePillar = UpdateContentPillar(pillars, clock);
  late final deletePillar = DeleteContentPillar(pillars);
  late final seedPillars = SeedDefaultContentPillars(
    pillars,
    seedState,
    uow,
    clock,
  );
  late final createItem = CreateContentItem(items, clock);
  late final updateItem = UpdateContentItem(items, clock);
  late final deleteItem = DeleteContentItem(items);
  late final moveStage = MoveContentStage(items, clock);
  late final createPost = CreateContentPost(posts, items, accounts, uow, clock);
  late final schedulePost = ScheduleContentPost(posts, items, uow, clock);
  late final markPosted = MarkPostPosted(posts, items, uow, clock);
  late final markSkipped = MarkPostSkipped(posts, items, uow, clock);
  late final setSponsor = SetContentSponsor(items, clock);
  late final markSponsorPaid = MarkSponsorPaid(
    items,
    categories,
    createTx,
    uow,
    clock,
  );
  late final markSponsorUnpaid = MarkSponsorUnpaid(items, clock);
  late final reminders = WatchReminders(
    tasks,
    areas,
    () => Stream.value(clock.now()),
    posts: posts,
    items: items,
    accounts: accounts,
  );

  Future<void> sync() async {
    await engine.syncNow();
    expect((await db.getMeta()).lastError, isNull, reason: '$name sync error');
  }

  /// Syncs until the outbox is empty (re-queued work, e.g. label remaps).
  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await sync();
      if ((await outbox.all()).isEmpty) return;
    }
    fail('$name outbox never drained: ${await outbox.all()}');
  }

  /// The server's full state for this account.
  Future<PullResponse> server() => syncApi.pull(0);

  Future<Map<String, Json>> serverRows(String entity) async => {
    for (final r in (await server()).changes[entity]!) r['id'] as String: r,
  };

  Future<void> close() async {
    await engine.dispose();
    await db.close();
  }
}

void main() {
  final base = Platform.environment['GHINA_E2E_BASE_URL'];
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final skip = base == null ? 'set GHINA_E2E_BASE_URL to run' : false;
  final devices = <Device>[];
  final tmp = <File>[];
  var n = 0;

  tearDown(() async {
    for (final d in devices) {
      await d.close();
    }
    devices.clear();
    for (final f in tmp) {
      if (f.existsSync()) f.deleteSync();
    }
    tmp.clear();
  });
  tearDownAll(() async {
    if (base != null) await helper('cleanup', emailPrefix);
  });

  File tempFile(String ext, List<int> bytes) {
    final f = File(
      '${Directory.systemTemp.path}/ghina_nc_${DateTime.now().microsecondsSinceEpoch}_${n++}.$ext',
    )..writeAsBytesSync(bytes);
    tmp.add(f);
    return f;
  }

  File voiceFile() => tempFile(
    'm4a',
    File(
      '${Directory.current.path}/test/data/fixtures/voice.m4a',
    ).readAsBytesSync(),
  );

  /// A fresh account with two signed-in devices (both synced once).
  Future<(Device, Device, String)> pair() async {
    final email =
        '$emailPrefix${DateTime.now().millisecondsSinceEpoch}-${n++}@example.test';
    final a = Device(base!, 'A');
    final b = Device(base, 'B');
    devices.addAll([a, b]);
    await a.auth.register(name: 'E2E', email: email, password: _password);
    await b.auth.signIn(email: email, password: _password);
    await a.sync();
    await b.sync();
    return (a, b, email);
  }

  Future<String> userId(Device d) async => (await d.db.getMeta()).userId!;

  Future<String> wallet(Device d, double balance) async =>
      (await d.createWallet(
        WalletInput(name: 'W${n++}', initialBalance: balance),
      )).valueOrThrow.id;

  // ------------------------------------------------------------------ defaults

  test(
    'default Ide Konten label + pillars: seeded once by the server; offline seeding never duplicates or resurrects',
    () async {
      final (a, b, email) = await pair();
      final uid = await userId(a);
      final labelId = 'label-ide-konten-$uid';
      for (final d in [a, b]) {
        expect([for (final l in await d.labels.getAll()) l.id], [labelId]);
        expect(await d.pillars.getAll(), hasLength(5));
        final meta = await d.db.getMeta();
        expect(meta.notesSeeded && meta.contentSeeded, isTrue);
        // After a pull from the server the app never seeds by itself.
        expect((await d.seedLabel(uid)).valueOrThrow, 0);
        expect((await d.seedPillars(uid)).valueOrThrow, 0);
      }
      expect((await a.server()).changes[SyncEntity.noteLabels], hasLength(1));

      // The user deletes the default label and the Promo pillar, renames Edukasi.
      await a.deleteLabel(labelId);
      await a.deletePillar('pillar-promo-$uid');
      final edu = (await a.pillars.getById('pillar-edukasi-$uid'))!;
      await a.updatePillar(
        edu.id,
        ContentPillarInput(name: 'Edu', color: edu.color),
      );
      await a.settle();

      // A third phone signs in and seeds offline before its first pull.
      final c = Device(base!, 'C');
      devices.add(c);
      await c.auth.signIn(email: email, password: _password);
      expect((await c.db.getMeta()).notesSeeded, isFalse);
      expect((await c.seedLabel(uid)).valueOrThrow, 1);
      expect((await c.seedPillars(uid)).valueOrThrow, 5);
      // …and even labels a note with the seeded label.
      final note = (await c.createNote(
        NoteInput(body: 'ide dari C', labelIds: [labelId]),
      )).valueOrThrow;
      await c.settle();

      final s = await c.server();
      expect(
        s.changes[SyncEntity.noteLabels],
        isEmpty,
        reason: 'not resurrected',
      );
      final pillars = {
        for (final p in s.changes[SyncEntity.contentPillars]!)
          p['id'] as String: p['name'],
      };
      expect(pillars, hasLength(4));
      expect(pillars.containsKey('pillar-promo-$uid'), isFalse);
      expect(pillars['pillar-edukasi-$uid'], 'Edu');
      final sn = s.changes[SyncEntity.notes]!.single;
      expect(sn['id'], note.id);
      expect(sn['labels'], isEmpty);
      for (final d in [a, b, c]) {
        await d.sync();
        expect(await d.labels.getAll(), isEmpty, reason: d.name);
        expect(
          {for (final p in await d.pillars.getAll()) p.id: p.name},
          pillars,
          reason: d.name,
        );
        expect((await d.notes.getById(note.id))!.labelIds, isEmpty);
      }

      // A fourth phone seeds while the server still has its defaults (fresh
      // account): same ids, so nothing is duplicated and the server copy wins.
      final (e, f, _) = await pair();
      final uid2 = await userId(e);
      final g = Device(base, 'G');
      devices.add(g);
      g.tokens.token = e.tokens.token;
      await g.db.updateMeta(SyncMetaCompanion(userId: Value(uid2)));
      // The web renamed a default pillar in the meantime.
      final hib = (await e.pillars.getById('pillar-hiburan-$uid2'))!;
      await e.updatePillar(
        hib.id,
        ContentPillarInput(name: 'Fun', color: hib.color),
      );
      await e.settle();
      expect((await g.seedLabel(uid2)).valueOrThrow, 1);
      expect((await g.seedPillars(uid2)).valueOrThrow, 5);
      await g.settle();
      final s2 = await g.server();
      expect(s2.changes[SyncEntity.noteLabels], hasLength(1));
      expect(s2.changes[SyncEntity.contentPillars], hasLength(5));
      expect(
        (await g.pillars.getById('pillar-hiburan-$uid2'))!.name,
        'Fun',
        reason: 'the seeded (oldest) version never overwrites the server',
      );
      await f.sync();
      expect(await f.pillars.getAll(), hasLength(5));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  // ------------------------------------------------------------------ notes

  test(
    'notes: offline create/edit A → B, LWW on editedAt, link title fill never clobbers',
    () async {
      final (a, b, email) = await pair();
      // Offline on A.
      final created = (await a.createNote(
        const NoteInput(
          title: 'Resep',
          body:
              'Lihat http://127.0.0.1:3199/resep dan https://toko.example.test/x',
          checklist: [
            ChecklistItem(id: 'c1', text: 'Telur'),
            ChecklistItem(id: 'c2', text: 'Tepung'),
          ],
          color: 'yellow',
        ),
      )).valueOrThrow;
      expect(created.links, hasLength(2));
      await a.settle();
      await b.sync();
      final onB = (await b.notes.getById(created.id))!;
      expect(onB.title, 'Resep');
      expect(onB.checklist.map((c) => c.text), ['Telur', 'Tepung']);
      expect(onB.color, 'yellow');
      expect(onB.links.map((l) => l.url), [
        'http://127.0.0.1:3199/resep',
        'https://toko.example.test/x',
      ]);
      // The server's own title fetch refuses loopback / unresolvable hosts.
      await Future<void>.delayed(const Duration(seconds: 2));
      final s0 = (await a.serverRows(SyncEntity.notes))[created.id]!;
      expect([for (final l in s0['links'] as List) l['title']], [null, null]);

      // A edits offline; THEN the server fills a title (bumps updatedAt, not
      // editedAt); THEN A comes online — A's older-than-updatedAt edit must apply.
      await a.updateNote(
        created.id,
        const NoteInput(
          title: 'Resep kue',
          body:
              'Lihat http://127.0.0.1:3199/resep dan https://toko.example.test/x',
          checklist: [
            ChecklistItem(id: 'c1', text: 'Telur', done: true),
            ChecklistItem(id: 'c2', text: 'Tepung'),
          ],
          color: 'yellow',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((await helper('fill-titles', email))['filled'], 1);
      await a.settle();
      final s1 = (await a.serverRows(SyncEntity.notes))[created.id]!;
      expect(s1['title'], 'Resep kue', reason: 'edit not skipped by the fill');
      expect((s1['checklist'] as List).first['done'], isTrue);
      expect(
        (s1['links'] as List).first['title'],
        'Judul /resep',
        reason: 'a sent link without a title keeps the stored one',
      );
      for (final d in [a, b]) {
        await d.sync();
        final x = (await d.notes.getById(created.id))!;
        expect(x.title, 'Resep kue', reason: d.name);
        expect(x.links.first.title, 'Judul /resep', reason: d.name);
      }

      // LWW between devices: B edits "earlier" (its clock is behind), A later;
      // whoever pushes last, the later edit wins on both.
      b.clock.offset = const Duration(minutes: -5);
      await b.updateNote(
        created.id,
        const NoteInput(title: 'B lama', body: 'b'),
      );
      await a.updateNote(
        created.id,
        const NoteInput(title: 'A baru', body: 'a'),
      );
      await a.settle();
      await b.sync(); // skipped → full pull brings A's
      await a.sync();
      for (final d in [a, b]) {
        final x = (await d.notes.getById(created.id))!;
        expect(x.title, 'A baru', reason: d.name);
        expect(x.body, 'a', reason: d.name);
      }
      b.clock.offset = Duration.zero;
      await b.updateNote(
        created.id,
        const NoteInput(title: 'B menang', body: 'b2'),
      );
      await b.settle();
      await a.sync();
      expect((await a.notes.getById(created.id))!.title, 'B menang');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'notes: checklist/labels ops; label delete strips on both; duplicate label names merge without losing notes',
    () async {
      final (a, b, _) = await pair();
      final kerja = (await a.createLabel(
        const NoteLabelInput(name: 'Kerjaan', pinnedTab: true),
      )).valueOrThrow;
      final nt = (await a.createNote(
        NoteInput(
          title: 'Todo',
          checklist: const [
            ChecklistItem(id: 'x1', text: 'Satu'),
            ChecklistItem(id: 'x2', text: 'Dua'),
          ],
          labelIds: [kerja.id],
        ),
      )).valueOrThrow;
      await a.settle();
      await b.sync();
      await b.toggleCheck(nt.id, 'x2');
      await b.settle();
      await a.sync();
      expect((await a.notes.getById(nt.id))!.checklist.map((c) => c.done), [
        false,
        true,
      ]);

      // A deletes the label; B edits the note offline, still carrying it.
      await a.deleteLabel(kerja.id);
      expect((await a.notes.getById(nt.id))!.labelIds, isEmpty);
      await a.settle();
      await b.setChecklist(nt.id, const [
        ChecklistItem(id: 'x1', text: 'Satu', done: true),
        ChecklistItem(id: 'x2', text: 'Dua', done: true),
        ChecklistItem(id: 'x3', text: 'Tiga'),
      ]);
      expect((await b.notes.getById(nt.id))!.labelIds, [kerja.id]);
      await b.settle();
      await a.sync();
      final s = (await a.serverRows(SyncEntity.notes))[nt.id]!;
      expect(s['labels'], isEmpty);
      expect(s['checklist'], hasLength(3));
      for (final d in [a, b]) {
        final x = (await d.notes.getById(nt.id))!;
        expect(x.labelIds, isEmpty, reason: d.name);
        expect(x.checklist, hasLength(3), reason: d.name);
        expect(await d.labels.getById(kerja.id), isNull, reason: d.name);
      }

      // Same label name created on both devices offline, each with a note.
      final la = (await a.createLabel(
        const NoteLabelInput(name: 'Belanja'),
      )).valueOrThrow;
      final lb = (await b.createLabel(
        const NoteLabelInput(name: 'belanja'),
      )).valueOrThrow;
      final na = (await a.createNote(
        NoteInput(body: 'beras', labelIds: [la.id]),
      )).valueOrThrow;
      final nb = (await b.createNote(
        NoteInput(body: 'gula', labelIds: [lb.id]),
      )).valueOrThrow;
      await a.settle();
      await b.settle();
      await a.sync();
      final sl = (await a.server()).changes[SyncEntity.noteLabels]!.where(
        (l) => (l['name'] as String).toLowerCase() == 'belanja',
      );
      expect(sl.single['id'], la.id);
      final sn = await a.serverRows(SyncEntity.notes);
      expect(sn[na.id]!['labels'], [la.id]);
      expect(sn[nb.id]!['labels'], [la.id], reason: 'B note moved to A label');
      for (final d in [a, b]) {
        expect((await d.notes.getById(nb.id))!.labelIds, [la.id]);
        expect((await d.notes.getById(na.id))!.labelIds, [la.id]);
        expect(await d.labels.getById(lb.id), isNull);
        expect(await d.outbox.all(), isEmpty);
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'notes: photo + m4a clip upload offline→online, B gets URLs, removal deletes server files, WAV refused',
    () async {
      final (a, b, _) = await pair();
      final photo = tempFile('jpg', jpegBytes);
      final clip = voiceFile();
      final nt = (await a.createNote(
        NoteInput(
          body: 'rapat',
          photos: [TransactionPhoto.local(photo.path)],
          audio: [
            NoteAudio.local(
              clip.path,
              durationSec: 1,
              transcript: 'halo semua',
            ),
          ],
          source: NoteSource.voice,
        ),
      )).valueOrThrow;
      expect(nt.hasPendingUploads, isTrue);
      await a.settle();
      final s = (await a.serverRows(SyncEntity.notes))[nt.id]!;
      final photoUrl = (s['photos'] as List).single as String;
      final clipJson = (s['audio'] as List).single as Map;
      final clipUrl = clipJson['url'] as String;
      expect(photoUrl, endsWith('.jpg'));
      expect(clipUrl, endsWith('.m4a'));
      expect(clipJson['transcript'], 'halo semua');
      expect(clipJson['durationSec'], 1);
      expect(uploadExists(photoUrl) && uploadExists(clipUrl), isTrue);
      final local = (await a.notes.getById(nt.id))!;
      expect(local.hasPendingUploads, isFalse);
      expect(local.photos.single.url, photoUrl);
      expect(local.audio.single.url, clipUrl);
      await b.sync();
      final onB = (await b.notes.getById(nt.id))!;
      expect(onB.photos.single.url, photoUrl);
      expect(onB.audio.single.url, clipUrl);
      expect(onB.audio.single.transcript, 'halo semua');

      // A WAV clip is refused by the server: dropped, transcript kept in the body.
      final wav = tempFile('m4a', wavBytes()); // lies about its extension
      await a.addNoteAudio(
        nt.id,
        NoteAudioInput(
          path: wav.path,
          durationSec: 1,
          transcript: 'wav hilang',
        ),
      );
      await a.engine.syncNow();
      expect(
        (await a.db.getMeta()).lastError,
        contains('Rekaman suara gagal diunggah'),
      );
      final afterWav = (await a.notes.getById(nt.id))!;
      expect(afterWav.audio.map((x) => x.url), [clipUrl]);
      expect(afterWav.body, contains('wav hilang'));
      final sw = (await a.serverRows(SyncEntity.notes))[nt.id]!;
      expect(sw['audio'], hasLength(1));
      expect(await a.outbox.all(), isEmpty);

      // B removes both files → the server deletes them.
      await b.sync();
      final nb = (await b.notes.getById(nt.id))!;
      await b.removeNotePhoto(nt.id, nb.photos.single);
      await b.removeNoteAudio(nt.id, nb.audio.single);
      await b.settle();
      expect(uploadExists(photoUrl), isFalse);
      expect(uploadExists(clipUrl), isFalse);
      await a.sync();
      final na = (await a.notes.getById(nt.id))!;
      expect(na.photos, isEmpty);
      expect(na.audio, isEmpty);

      // Deleting a note deletes its files.
      await a.addNotePhotos(nt.id, [tempFile('jpg', jpegBytes).path]);
      await a.addNoteAudio(
        nt.id,
        NoteAudioInput(path: voiceFile().path, durationSec: 1),
      );
      await a.settle();
      final s2 = (await a.serverRows(SyncEntity.notes))[nt.id]!;
      final urls = [
        ...(s2['photos'] as List).cast<String>(),
        for (final c in s2['audio'] as List) c['url'] as String,
      ];
      expect(urls, hasLength(2));
      expect(urls.every(uploadExists), isTrue);
      await b.sync();
      await b.deleteNote(nt.id);
      await b.settle();
      expect(urls.any(uploadExists), isFalse);
      await a.sync();
      expect(await a.notes.getById(nt.id), isNull);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  // ------------------------------------------------------------------ conversions

  test(
    'conversions: note → task/content/transaction on A, links on B, deleting targets nulls links everywhere',
    () async {
      final (a, b, _) = await pair();
      final uid = await userId(a);
      final w = await wallet(a, 100000);
      final photo = tempFile('jpg', jpegBytes);
      final nt = (await a.createNote(
        NoteInput(
          title: 'Beli mic',
          body: 'Mic baru Rp 250.000 buat konten',
          photos: [TransactionPhoto.local(photo.path)],
        ),
      )).valueOrThrow;
      final task = (await a.noteToTask(
        nt.id,
        NoteTaskInput(areaId: 'area-kerjaan-$uid'),
      )).valueOrThrow.task;
      final item = (await a.noteToContent(nt.id)).valueOrThrow.item;
      final tx = (await a.noteToTx(
        nt.id,
        TransactionInput(
          type: TxType.expense,
          amount: 250000,
          walletId: w,
          note: 'Beli mic',
          date: DateTime.now(),
        ),
      )).valueOrThrow.transaction;
      await a.settle();
      final sn = (await a.serverRows(SyncEntity.notes))[nt.id]!;
      expect(sn['linkedTaskId'], task.id);
      expect(sn['linkedContentId'], item.id);
      expect(sn['linkedTransactionId'], tx.id);
      final si = (await a.serverRows(SyncEntity.contentItems))[item.id]!;
      expect(si['noteId'], nt.id);
      expect(si['stage'], 'ide');
      expect(si['idea'], contains('Rp 250.000'));
      expect((si['photos'] as List), hasLength(1), reason: 'photos copied');
      expect(
        (await a.serverRows(SyncEntity.tasks))[task.id]!['title'],
        'Beli mic',
      );
      await b.sync();
      final onB = (await b.notes.getById(nt.id))!;
      expect(onB.linkedTaskId, task.id);
      expect(onB.linkedContentId, item.id);
      expect(onB.linkedTransactionId, tx.id);
      expect((await b.items.getById(item.id))!.noteId, nt.id);
      expect((await b.wallets.getById(w))!.balance, -150000);

      // Deleting each target nulls the link on the server and both devices.
      await b.deleteTask(task.id);
      await a.deleteItem(item.id);
      await b.settle();
      await a.settle();
      await b.deleteTx(tx.id);
      await b.settle();
      await a.sync();
      final sn2 = (await a.serverRows(SyncEntity.notes))[nt.id]!;
      expect(
        [
          sn2['linkedTaskId'],
          sn2['linkedContentId'],
          sn2['linkedTransactionId'],
        ],
        [null, null, null],
      );
      for (final d in [a, b]) {
        final x = (await d.notes.getById(nt.id))!;
        expect(
          [x.linkedTaskId, x.linkedContentId, x.linkedTransactionId],
          [null, null, null],
          reason: d.name,
        );
        expect((await d.wallets.getById(w))!.balance, 100000, reason: d.name);
      }
      // The note's photo survives the transaction delete (shared file).
      final notePhoto = (sn2['photos'] as List).single as String;
      expect(uploadExists(notePhoto), isTrue);

      // Note deleted → the content item made from it loses noteId (and v.v.).
      final item2 = (await a.noteToContent(nt.id)).valueOrThrow.item;
      await a.settle();
      await b.sync();
      await b.deleteNote(nt.id);
      await b.settle();
      await a.sync();
      expect(
        (await a.serverRows(SyncEntity.contentItems))[item2.id]!['noteId'],
        isNull,
      );
      expect((await a.items.getById(item2.id))!.noteId, isNull);
      expect(uploadExists(notePhoto), isTrue, reason: 'item still uses it');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  // ------------------------------------------------------------------ content

  test(
    'content: accounts/pillars/items/posts across devices, stage auto-advance, cascades',
    () async {
      final (a, b, _) = await pair();
      final uid = await userId(a);
      final ig = (await a.createAccount(
        const SocialAccountInput(
          platform: SocialPlatform.instagram,
          handle: '@ghina',
          targetPerWeek: 3,
        ),
      )).valueOrThrow;
      final tt = (await a.createAccount(
        const SocialAccountInput(
          platform: SocialPlatform.tiktok,
          handle: 'ghina',
        ),
      )).valueOrThrow;
      final it = (await a.createItem(
        const ContentItemInput(
          title: 'Tips hemat',
          pillar: 'Edukasi',
          format: ContentFormat.reel,
        ),
      )).valueOrThrow;
      final pIg = (await a.createPost(
        it.id,
        ContentPostInput(accountId: ig.id, caption: 'Hemat #1'),
      )).valueOrThrow;
      final pTt = (await a.createPost(
        it.id,
        ContentPostInput(accountId: tt.id),
      )).valueOrThrow;
      await a.settle();
      await b.sync();
      expect(await b.accounts.getAll(), hasLength(2));
      expect(await b.posts.getAll(contentId: it.id), hasLength(2));
      expect((await b.items.getById(it.id))!.pillar, 'Edukasi');

      // Both devices schedule and post their own account offline.
      final at = DateTime.now().add(const Duration(days: 1));
      await a.schedulePost(pIg.id, at, remindBefore: 60);
      await b.schedulePost(pTt.id, at, remindBefore: 30);
      expect((await a.items.getById(it.id))!.stage, ContentStage.terjadwal);
      await a.markPosted(pIg.id);
      await b.markPosted(pTt.id);
      await a.settle();
      await b.settle();
      await a.settle();
      final sp = await a.serverRows(SyncEntity.contentPosts);
      expect(sp[pIg.id]!['status'], 'posted');
      expect(sp[pTt.id]!['status'], 'posted');
      final stageOnServer = (await a.serverRows(
        SyncEntity.contentItems,
      ))[it.id]!['stage'];
      expect(
        [
          stageOnServer,
          (await a.items.getById(it.id))!.stage.wire,
          (await b.items.getById(it.id))!.stage.wire,
        ],
        ['tayang', 'tayang', 'tayang'],
        reason: 'all posts posted → tayang everywhere',
      );

      // Pillar rename on A → items follow on the server and B; delete on B → null.
      final edu = (await a.pillars.getById('pillar-edukasi-$uid'))!;
      await a.updatePillar(
        edu.id,
        ContentPillarInput(name: 'Edu', color: edu.color),
      );
      await a.settle();
      await b.sync();
      expect((await b.items.getById(it.id))!.pillar, 'Edu');
      expect(
        (await a.serverRows(SyncEntity.contentItems))[it.id]!['pillar'],
        'Edu',
      );
      await b.deletePillar(edu.id);
      await b.settle();
      await a.sync();
      expect((await a.items.getById(it.id))!.pillar, isNull);
      expect(
        (await a.serverRows(SyncEntity.contentItems))[it.id]!['pillar'],
        isNull,
      );

      // Account delete on A cascades its posts (server + B).
      await a.deleteAccount(tt.id);
      await a.settle();
      await b.sync();
      expect((await a.serverRows(SyncEntity.contentPosts)).keys, [pIg.id]);
      expect([for (final p in await b.posts.getAll()) p.id], [pIg.id]);

      // Item delete cascades its posts.
      await b.deleteItem(it.id);
      await b.settle();
      await a.sync();
      expect(await a.posts.getAll(), isEmpty);
      expect((await a.server()).changes[SyncEntity.contentPosts], isEmpty);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'sponsor: paid → income transaction + balance on both devices and server; unpaid + delete reverses',
    () async {
      final (a, b, _) = await pair();
      final w = await wallet(a, 1000);
      final it = (await a.createItem(
        const ContentItemInput(
          title: 'Endorse sepatu',
          sponsor: SponsorInput(brand: 'Sepatu Kita', amount: 500000),
        ),
      )).valueOrThrow;
      await a.settle();
      await b.sync();
      final r = (await b.markSponsorPaid(
        it.id,
        record: SponsorPayment(walletId: w),
      )).valueOrThrow;
      final tx = r.transaction!;
      expect(tx.note, 'Endorse Sepatu Kita');
      expect((await b.wallets.getById(w))!.balance, 501000);
      await b.settle();
      await a.sync();
      final si = (await a.serverRows(SyncEntity.contentItems))[it.id]!;
      expect(si['sponsor']['paid'], isTrue);
      expect(si['sponsor']['transactionId'], tx.id);
      final st = (await a.serverRows(SyncEntity.transactions))[tx.id]!;
      expect(st['type'], 'income');
      expect(st['amount'], 500000);
      final sw = (await a.serverRows(SyncEntity.wallets))[w]!;
      expect(sw['balance'], 501000);
      expect((await a.wallets.getById(w))!.balance, 501000);
      expect((await a.items.getById(it.id))!.sponsor!.transactionId, tx.id);

      // Paid again on A never records a second income.
      final again = (await a.markSponsorPaid(
        it.id,
        record: SponsorPayment(walletId: w),
      )).valueOrThrow;
      expect(again.transaction, isNull);

      // Unpaid + delete the income on A.
      await a.markSponsorUnpaid(it.id);
      await a.deleteTx(tx.id);
      await a.settle();
      await b.sync();
      final si2 = (await a.serverRows(SyncEntity.contentItems))[it.id]!;
      expect(si2['sponsor']['paid'], isFalse);
      expect(si2['sponsor']['transactionId'], isNull);
      expect((await a.serverRows(SyncEntity.wallets))[w]!['balance'], 1000);
      for (final d in [a, b]) {
        expect((await d.wallets.getById(w))!.balance, 1000, reason: d.name);
        final s = (await d.items.getById(it.id))!.sponsor!;
        expect([s.paid, s.transactionId], [false, null], reason: d.name);
        expect(await d.txs.getById(tx.id), isNull, reason: d.name);
      }

      // Deleting the income elsewhere while the item stays paid keeps `paid`.
      final r2 = (await a.markSponsorPaid(
        it.id,
        record: SponsorPayment(walletId: w),
      )).valueOrThrow;
      await a.settle();
      await b.sync();
      await b.deleteTx(r2.transaction!.id);
      await b.settle();
      await a.sync();
      final s3 = (await a.items.getById(it.id))!.sponsor!;
      expect([s3.paid, s3.transactionId], [true, null]);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  // ------------------------------------------------------------------ reminders

  test(
    'reminders: post reminders merge with task reminders (≤ 60, soonest first, [IG-TAYANG], /content/posts/<id>)',
    () async {
      final (a, b, _) = await pair();
      final uid = await userId(a);
      final now = DateTime.now();
      final base0 = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(const Duration(days: 1, hours: 9));
      // 55 tasks, one reminder per day at 08:50 (due 09:00, 10 min before).
      for (var i = 0; i < 55; i++) {
        await a.createTask(
          TaskInput(
            areaId: 'area-kerjaan-$uid',
            title: 'Tugas $i',
            dueDate: base0.add(Duration(days: i)),
            dueTime: '09:00',
            remindBefore: 10,
          ),
        );
      }
      final ig = (await a.createAccount(
        const SocialAccountInput(
          platform: SocialPlatform.instagram,
          handle: 'ghina',
        ),
      )).valueOrThrow;
      final postIds = <String>[];
      // 10 posts every 7 days at 19:00, reminded 60 min before.
      for (var i = 0; i < 10; i++) {
        final it = (await a.createItem(
          ContentItemInput(title: 'Konten $i'),
        )).valueOrThrow;
        final p = (await a.createPost(
          it.id,
          ContentPostInput(
            accountId: ig.id,
            scheduledAt: base0.add(Duration(days: i * 7, hours: 10)),
            remindBefore: 60,
          ),
        )).valueOrThrow;
        postIds.add(p.id);
      }
      await a.settle();
      await b.sync();
      for (final d in [a, b]) {
        final list = await d.reminders().first;
        expect(list, hasLength(60), reason: d.name);
        for (var i = 1; i < list.length; i++) {
          expect(
            list[i].fireAt.isBefore(list[i - 1].fireAt),
            isFalse,
            reason: 'soonest first',
          );
        }
        final content = list
            .where((r) => r.key.startsWith('content-post-'))
            .toList();
        // Posts within the 60 soonest: task days 0..54 (08:50) + posts on days
        // 0,7,…,63 (18:00) → cut after 60 → posts on days 0..49 (8) make it.
        expect(content, hasLength(8), reason: d.name);
        expect(content.first.title, '[IG-TAYANG] Konten 0');
        expect(content.first.route, '/content/posts/${postIds.first}');
        expect(content.first.body, contains('@ghina'));
        expect(list.where((r) => r.route.startsWith('/tasks/')), hasLength(52));
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  // ------------------------------------------------------------------ reset

  test(
    'web reset keeps notes/labels/content, nulls transaction links on both devices',
    () async {
      final (a, b, email) = await pair();
      final w = await wallet(a, 1000);
      final label = (await a.createLabel(
        const NoteLabelInput(name: 'Keuangan'),
      )).valueOrThrow;
      final nt = (await a.createNote(
        NoteInput(body: 'Makan Rp 20.000', labelIds: [label.id]),
      )).valueOrThrow;
      final tx = (await a.noteToTx(
        nt.id,
        TransactionInput(
          type: TxType.expense,
          amount: 20000,
          walletId: w,
          date: DateTime.now(),
        ),
      )).valueOrThrow.transaction;
      final acc = (await a.createAccount(
        const SocialAccountInput(
          platform: SocialPlatform.youtube,
          handle: 'kanal',
        ),
      )).valueOrThrow;
      final it = (await a.createItem(
        const ContentItemInput(
          title: 'Review',
          sponsor: SponsorInput(brand: 'Brand', amount: 100),
        ),
      )).valueOrThrow;
      final post = (await a.createPost(
        it.id,
        ContentPostInput(accountId: acc.id),
      )).valueOrThrow;
      final paid = (await a.markSponsorPaid(
        it.id,
        record: SponsorPayment(walletId: w),
      )).valueOrThrow;
      expect(paid.transaction, isNotNull);
      await a.settle();
      await b.sync();
      final pillarCount = (await a.pillars.getAll()).length;

      final r = await helper('reset', email);
      await a.sync();
      await b.sync();
      for (final d in [a, b]) {
        expect((await d.db.getMeta()).epoch, r['epoch'], reason: d.name);
        expect(await d.txs.getById(tx.id), isNull);
        expect(await d.wallets.getAll(), isEmpty);
        final x = (await d.notes.getById(nt.id))!;
        expect(x.linkedTransactionId, isNull, reason: d.name);
        expect(x.labelIds, [label.id], reason: d.name);
        expect(await d.labels.getById(label.id), isNotNull);
        expect(await d.accounts.getById(acc.id), isNotNull);
        expect(await d.posts.getById(post.id), isNotNull);
        expect(await d.pillars.getAll(), hasLength(pillarCount));
        final s = (await d.items.getById(it.id))!.sponsor!;
        expect([s.paid, s.transactionId], [true, null], reason: d.name);
      }
      final sn = (await a.serverRows(SyncEntity.notes))[nt.id]!;
      expect(sn['linkedTransactionId'], isNull);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  // ------------------------------------------------------------------ perf

  test(
    'perf: device full pull + 200-mutation push at ~1500 tx / 300 tasks / 500 notes / 200 items + 400 posts',
    () async {
      final (a, _, _) = await pair();
      final uid = await userId(a);
      final epoch = (await a.db.getMeta()).epoch;
      var seq = 0;
      PushMutation up(String entity, String id, Json data) => PushMutation(
        id: 'perf-${seq++}',
        entity: entity,
        op: MutationOp.upsert,
        entityId: id,
        data: data,
        clientUpdatedAt: DateTime.now(),
      );
      Future<void> pushAll(List<PushMutation> ms) async {
        for (var i = 0; i < ms.length; i += 500) {
          final r = await a.syncApi.push(
            ms.sublist(i, i + 500 > ms.length ? ms.length : i + 500),
            epoch: epoch,
          );
          expect(
            r.results.where((x) => x.status != PushStatus.applied),
            isEmpty,
          );
        }
      }

      final cat = (await a.categories.getAll())
          .firstWhere((c) => c.type == CategoryType.expense)
          .id;
      final now = DateTime.now();
      await pushAll([
        up(SyncEntity.wallets, 'pf-w', {
          'name': 'W',
          'type': 'cash',
          'balance': 1e8,
          'currency': 'IDR',
          'color': '#22c55e',
          'icon': 'wallet',
        }),
        for (var i = 0; i < 1500; i++)
          up(SyncEntity.transactions, 'pf-t-$i', {
            'walletId': 'pf-w',
            'toWalletId': null,
            'categoryId': cat,
            'type': 'expense',
            'amount': 1000 + i,
            'note': 'n$i',
            'date': now
                .subtract(Duration(hours: i * 5))
                .toUtc()
                .toIso8601String(),
          }),
        for (var i = 0; i < 300; i++)
          up(SyncEntity.tasks, 'pf-k-$i', {
            'areaId': 'area-kerjaan-$uid',
            'title': 'Tugas $i',
            'bucket': 'want',
          }),
        for (var i = 0; i < 500; i++)
          up(SyncEntity.notes, 'pf-n-$i', {
            'title': 'Catatan $i',
            'body': 'Isi $i https://x.example.test/$i',
            'checklist': [
              for (var k = 0; k < 1 + i % 8; k++)
                {'id': 'c$k', 'text': 'Item $k', 'done': k.isEven},
            ],
            'labels': ['label-ide-konten-$uid'],
          }),
        up(SyncEntity.socialAccounts, 'pf-ig', {
          'platform': 'instagram',
          'platformName': null,
          'handle': 'p',
          'color': '#E1306C',
          'targetPerWeek': 3,
          'archived': false,
          'sortOrder': 0,
        }),
        up(SyncEntity.socialAccounts, 'pf-tt', {
          'platform': 'tiktok',
          'platformName': null,
          'handle': 'p',
          'color': '#000000',
          'targetPerWeek': 2,
          'archived': false,
          'sortOrder': 1,
        }),
        for (var i = 0; i < 200; i++)
          up(SyncEntity.contentItems, 'pf-ci-$i', {
            'title': 'Konten $i',
            'stage': 'terjadwal',
            'idea': 'Naskah $i',
          }),
        for (var i = 0; i < 200; i++)
          for (final acc in ['pf-ig', 'pf-tt'])
            up(SyncEntity.contentPosts, 'pf-cp-$i-$acc', {
              'contentId': 'pf-ci-$i',
              'accountId': acc,
              'status': 'scheduled',
              'scheduledAt': now
                  .add(Duration(days: i))
                  .toUtc()
                  .toIso8601String(),
              'remindBefore': 60,
            }),
      ]);

      final c = Device(base!, 'C');
      devices.add(c);
      c.tokens.token = a.tokens.token;
      await c.db.updateMeta(SyncMetaCompanion(userId: Value(uid)));
      var sw = Stopwatch()..start();
      await c.sync();
      final pullMs = sw.elapsedMilliseconds;
      expect(await c.notes.getAll(), hasLength(500));
      expect(await c.posts.getAll(), hasLength(400));

      // 200 local mutations: 80 note edits, 20 new notes, 50 item stage moves,
      // 50 posts marked posted (each auto-advancing its item).
      final notes = await c.notes.getAll();
      for (var i = 0; i < 80; i++) {
        await c.updateNote(
          notes[i].id,
          NoteInput(
            title: 'Ubah $i',
            body: notes[i].body,
            checklist: notes[i].checklist,
          ),
        );
      }
      for (var i = 0; i < 20; i++) {
        await c.createNote(NoteInput(body: 'Baru $i'));
      }
      for (var i = 0; i < 50; i++) {
        await c.moveStage('pf-ci-$i', ContentStage.siap);
      }
      for (var i = 100; i < 150; i++) {
        await c.markPosted('pf-cp-$i-pf-ig');
      }
      final queued = (await c.outbox.all()).length;
      sw = Stopwatch()..start();
      await c.settle();
      final pushMs = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print(
        'PERF device full pull: $pullMs ms; push $queued queued mutations + pull: $pushMs ms',
      );
      expect(pullMs, lessThan(10000));
      expect(pushMs, lessThan(10000));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
