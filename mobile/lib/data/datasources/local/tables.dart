import 'package:drift/drift.dart';

/// Stores `DateTime` as integer milliseconds since epoch; reads back as local time.
class EpochMsConverter extends TypeConverter<DateTime, int> {
  const EpochMsConverter();

  @override
  DateTime fromSql(int fromDb) => DateTime.fromMillisecondsSinceEpoch(fromDb);

  @override
  int toSql(DateTime value) => value.millisecondsSinceEpoch;
}

const epochMs = EpochMsConverter();

mixin Timestamps on Table {
  IntColumn get createdAt => integer().map(epochMs)();
  IntColumn get updatedAt => integer().map(epochMs)();
}

@DataClassName('WalletRow')
class Wallets extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text().withDefault(const Constant('cash'))();

  /// Last server balance (or the initial balance until the wallet is pushed).
  RealColumn get balance => real().withDefault(const Constant(0))();
  TextColumn get currency => text().withDefault(const Constant('IDR'))();
  TextColumn get color => text().withDefault(const Constant('#6366f1'))();
  TextColumn get icon => text().withDefault(const Constant('wallet'))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CategoryRow')
class Categories extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text().withDefault(const Constant('expense'))();
  TextColumn get color => text().withDefault(const Constant('#6366f1'))();
  TextColumn get icon => text().withDefault(const Constant('circle'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TransactionRow')
@TableIndex(name: 'idx_tx_date', columns: {#date})
@TableIndex(name: 'idx_tx_wallet', columns: {#walletId})
@TableIndex(name: 'idx_tx_to_wallet', columns: {#toWalletId})
@TableIndex(name: 'idx_tx_category', columns: {#categoryId})
class Transactions extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get walletId => text()();
  TextColumn get toWalletId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get type => text().withDefault(const Constant('expense'))();
  RealColumn get amount => real()();
  TextColumn get note => text().nullable()();
  IntColumn get date => integer().map(epochMs)();

  // --- schema v3 (`docs/transaction-photos.md`) ---

  /// JSON array of strings, display order: uploaded paths (`/uploads/x.jpg`) and
  /// photos waiting for upload as `local:<absolute file path>` (device-only marker,
  /// never sent on the wire). v2 rows migrate to `[]`.
  TextColumn get photos => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BudgetRow')
@TableIndex(name: 'idx_budget_period', columns: {#year, #month})
class Budgets extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get categoryId => text()();
  RealColumn get amount => real()();
  IntColumn get month => integer()();
  IntColumn get year => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {categoryId, month, year},
  ];
}

@DataClassName('SubscriptionRow')
class Subscriptions extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get amount => real()();
  TextColumn get currency => text().withDefault(const Constant('IDR'))();
  TextColumn get cycle => text().withDefault(const Constant('monthly'))();
  IntColumn get nextBilling => integer().map(epochMs)();
  TextColumn get categoryId => text().nullable()();
  TextColumn get walletId => text().nullable()();
  TextColumn get color => text().withDefault(const Constant('#6366f1'))();
  TextColumn get icon => text().withDefault(const Constant('credit-card'))();
  TextColumn get note => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PlannedRow')
@TableIndex(name: 'idx_planned_date', columns: {#date})
class Planned extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get type => text().withDefault(const Constant('expense'))();
  RealColumn get amount => real()();
  TextColumn get note => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get walletId => text().nullable()();
  IntColumn get date => integer().map(epochMs)();
  BoolColumn get done => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PrayerRow')
class Prayers extends Table with Timestamps {
  TextColumn get id => text()();

  /// `YYYY-MM-DD`
  TextColumn get date => text()();

  /// Fardhu `subuh|dzuhur|ashar|maghrib|isya`, sunnah `dhuha|tahajud|witir`.
  TextColumn get prayer => text()();

  // --- schema v2 (prayer quality, `docs/prayer-quality.md`) ---

  /// Fardhu: `masjid|jamaah|ontime|late|qadha|missed|excused`; sunnah: `done`.
  /// v1 rows (performed) migrate to `ontime`.
  TextColumn get status => text().withDefault(const Constant('ontime'))();
  BoolColumn get qobliyah => boolean().withDefault(const Constant(false))();
  BoolColumn get badiyah => boolean().withDefault(const Constant(false))();

  /// Sunnah only.
  IntColumn get rakaat => integer().nullable()();
  IntColumn get prayedAt => integer().map(epochMs).nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {date, prayer},
  ];
}

@DataClassName('HealthRow')
@TableIndex(name: 'idx_health_date', columns: {#date})
class Health extends Table with Timestamps {
  TextColumn get id => text()();
  IntColumn get date => integer().map(epochMs)();
  RealColumn get weight => real().nullable()();
  IntColumn get systolic => integer().nullable()();
  IntColumn get diastolic => integer().nullable()();
  IntColumn get pulse => integer().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FoodRow')
@TableIndex(name: 'idx_food_date', columns: {#date})
class Food extends Table with Timestamps {
  TextColumn get id => text()();
  IntColumn get date => integer().map(epochMs)();
  TextColumn get name => text()();
  TextColumn get meal => text().nullable()();
  IntColumn get calories => integer().nullable()();
  TextColumn get photoUrl => text().nullable()();

  /// Device-only: photo waiting to be uploaded. Never sent on the wire.
  TextColumn get localPhotoPath => text().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// --- schema v3: tasks (`docs/tasks.md`) ---

@DataClassName('TaskAreaRow')
class TaskAreas extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// 1–8 chars `A–Z0–9`, unique per user.
  TextColumn get code => text()();
  TextColumn get color => text().withDefault(const Constant('#58CC02'))();
  TextColumn get icon => text().withDefault(const Constant('briefcase'))();

  /// JSON `{"days":[1..7],"start":"HH:mm","end":"HH:mm"}`; null = anytime.
  TextColumn get schedule => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TaskRow')
@TableIndex(name: 'idx_task_area', columns: {#areaId})
@TableIndex(name: 'idx_task_due', columns: {#dueDate})
class Tasks extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get areaId => text()();
  TextColumn get title => text()();
  TextColumn get note => text().nullable()();

  /// `fire | want | should`
  TextColumn get bucket => text().withDefault(const Constant('want'))();

  /// Local date `YYYY-MM-DD`.
  TextColumn get dueDate => text().nullable()();

  /// Local `HH:mm`, only with [dueDate].
  TextColumn get dueTime => text().nullable()();
  IntColumn get remindBefore => integer().nullable()();

  /// JSON `{"freq","interval","weekdays"?,"monthDay"?}`; null = one-off.
  TextColumn get recurrence => text().nullable()();
  TextColumn get seriesId => text().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  IntColumn get doneAt => integer().map(epochMs).nullable()();
  RealColumn get sortOrder => real().withDefault(const Constant(0))();
  RealColumn get amount => real().nullable()();
  TextColumn get walletId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get transactionId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// --- schema v4: notes (`docs/notes.md`) and content planner (`docs/content.md`) ---
//
// JSON fields are stored as JSON text. Photo/audio lists may hold device-only
// markers for files waiting for upload (`local:<path>` photos, `{"local": path}`
// clips) — never sent on the wire.

@DataClassName('NoteRow')
@TableIndex(name: 'idx_note_updated', columns: {#updatedAt})
class Notes extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get title => text().nullable()();
  TextColumn get body => text().withDefault(const Constant(''))();

  /// JSON `[{id, text, done}]`.
  TextColumn get checklist => text().withDefault(const Constant('[]'))();

  /// JSON array of label ids.
  TextColumn get labels => text().withDefault(const Constant('[]'))();
  TextColumn get color => text().nullable()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  /// JSON array: `/uploads/…` paths and `local:<path>` markers.
  TextColumn get photos => text().withDefault(const Constant('[]'))();

  /// JSON `[{url, durationSec, transcript?}]`; pending clips `{local, …}`.
  TextColumn get audio => text().withDefault(const Constant('[]'))();

  /// JSON `[{url, title?}]`.
  TextColumn get links => text().withDefault(const Constant('[]'))();

  /// `share | quick | voice`
  TextColumn get source => text().nullable()();
  TextColumn get linkedTaskId => text().nullable()();
  TextColumn get linkedContentId => text().nullable()();
  TextColumn get linkedTransactionId => text().nullable()();

  /// Device-only: lowercased title + body + checklist + transcripts (search).
  TextColumn get searchText => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('NoteLabelRow')
class NoteLabels extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get color => text().withDefault(const Constant('#58CC02'))();
  BoolColumn get pinnedTab => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SocialAccountRow')
class SocialAccounts extends Table with Timestamps {
  TextColumn get id => text()();

  /// `instagram | tiktok | youtube | x | threads | linkedin | facebook | other`
  TextColumn get platform => text()();
  TextColumn get platformName => text().nullable()();
  TextColumn get handle => text()();
  TextColumn get color => text()();
  IntColumn get targetPerWeek => integer().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ContentItemRow')
class ContentItems extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get title => text()();

  /// `ide | naskah | produksi | siap | terjadwal | tayang`
  TextColumn get stage => text().withDefault(const Constant('ide'))();
  TextColumn get format => text().nullable()();

  /// Pillar name.
  TextColumn get pillar => text().nullable()();
  TextColumn get idea => text().withDefault(const Constant(''))();
  TextColumn get noteId => text().nullable()();
  TextColumn get checklist => text().withDefault(const Constant('[]'))();
  TextColumn get photos => text().withDefault(const Constant('[]'))();

  /// JSON `[{url, label}]`.
  TextColumn get assetLinks => text().withDefault(const Constant('[]'))();

  /// JSON `{brand, amount, currency, due?, paid, transactionId?}` or null.
  TextColumn get sponsor => text().nullable()();

  /// Device-only: JSON `{stage: epochMs}` — when this device first saw each
  /// stage reached (gamification, see `lib/domain/game/README.md`).
  TextColumn get stageLog => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ContentPostRow')
@TableIndex(name: 'idx_post_content', columns: {#contentId})
@TableIndex(name: 'idx_post_account', columns: {#accountId})
@TableIndex(name: 'idx_post_scheduled', columns: {#scheduledAt})
class ContentPosts extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get contentId => text()();
  TextColumn get accountId => text()();
  TextColumn get caption => text().withDefault(const Constant(''))();
  TextColumn get hashtags => text().withDefault(const Constant(''))();
  IntColumn get scheduledAt => integer().map(epochMs).nullable()();
  IntColumn get remindBefore => integer().nullable()();

  /// `draft | scheduled | posted | skipped`
  TextColumn get status => text().withDefault(const Constant('draft'))();
  IntColumn get postedAt => integer().map(epochMs).nullable()();
  TextColumn get url => text().nullable()();

  /// JSON `{views, likes, comments, shares, saves, followers}`.
  TextColumn get metrics => text().withDefault(const Constant('{}'))();
  IntColumn get metricsAt => integer().map(epochMs).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ContentPillarRow')
class ContentPillars extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get color => text().withDefault(const Constant('#58CC02'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pending local mutations, pushed in [seq] order.
@DataClassName('OutboxRow')
@TableIndex(name: 'idx_outbox_entity', columns: {#entity, #entityId})
class Outbox extends Table {
  IntColumn get seq => integer().autoIncrement()();

  /// Mutation id sent to the server (UUID v4).
  TextColumn get mutationId => text().unique()();

  /// Wire entity name (`transactions`, …).
  TextColumn get entity => text()();

  /// `upsert` | `delete`
  TextColumn get op => text()();
  TextColumn get entityId => text()();

  /// JSON of the upsert `data` (null for deletes).
  TextColumn get data => text().nullable()();

  /// Transactions only: JSON of the row as the server currently has it (null if the
  /// server doesn't have it). Pending balance effect = effect(data) − effect(base).
  TextColumn get base => text().nullable()();

  /// True when the entity did not exist on the server when this was queued.
  BoolColumn get isCreate => boolean().withDefault(const Constant(false))();

  /// True while part of a push request that hasn't been answered yet.
  BoolColumn get inFlight => boolean().withDefault(const Constant(false))();

  /// Milliseconds since epoch.
  IntColumn get clientUpdatedAt => integer()();
}

/// Single-row sync bookkeeping (id = 1).
@DataClassName('SyncMetaRow')
class SyncMeta extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();

  /// Next pull cursor (server ms). 0 = full pull.
  IntColumn get cursor => integer().withDefault(const Constant(0))();
  TextColumn get epoch => text().nullable()();

  /// Owner of the local data (wiped when a different user signs in).
  TextColumn get userId => text().nullable()();
  IntColumn get lastSyncAt => integer().nullable()();
  TextColumn get lastError => text().nullable()();

  /// Set after a rejected/skipped mutation so the next pull re-downloads everything.
  BoolColumn get fullPullRequired =>
      boolean().withDefault(const Constant(false))();

  /// v3: the default task areas were checked/seeded after the first pull from a
  /// server that knows tasks (`docs/tasks.md`), so they're never re-created.
  BoolColumn get tasksSeeded => boolean().withDefault(const Constant(false))();

  /// v4: a pull from a notes-aware server succeeded — the server owns seeding
  /// the default "Ide Konten" label from then on; the app never seeds it again.
  BoolColumn get notesSeeded => boolean().withDefault(const Constant(false))();

  /// v4: a pull from a content-aware server succeeded — the server owns seeding
  /// the default pillars from then on; the app never seeds them again.
  BoolColumn get contentSeeded =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
