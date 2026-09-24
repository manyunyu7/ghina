/// Content planner use cases — `docs/content.md`. Rules: `content_rules.dart`.
library;

import '../../core/clock.dart';
import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../../core/streams.dart';
import '../entities/entities.dart';
import '../repositories/repositories.dart';
import 'content_rules.dart';
import 'notes_rules.dart';
import 'notes_usecases.dart' show seedVersion;
import 'task_rules.dart' show remindBeforeMax;
import 'task_usecases.dart' show TickSource;
import 'transaction_usecases.dart' show CreateTransaction, TransactionInput;

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int _nextSort(Iterable<int> orders) =>
    orders.isEmpty ? 0 : orders.reduce((a, b) => a > b ? a : b) + 1;

// ================================================================ accounts

/// Form data of a social account.
final class SocialAccountInput {
  const SocialAccountInput({
    required this.platform,
    required this.handle,
    this.platformName,
    this.color,
    this.targetPerWeek,
  });

  final SocialPlatform platform;

  /// Required for `other` (e.g. "Pinterest"), ignored otherwise. ≤ 30.
  final String? platformName;

  /// `@username` or channel name, 1–60.
  final String handle;

  /// `#rrggbb`; null = the platform's default color.
  final String? color;

  /// 1–50 posts per week; null/0 = no target.
  final int? targetPerWeek;
}

({String? platformName, String handle, String color, int? target})
_validateAccount(SocialAccountInput i) {
  final handle = cleanLine(i.handle);
  if (handle.isEmpty) {
    throw const ValidationFailure('Username wajib diisi', field: 'handle');
  }
  if (handle.length > handleMax) {
    throw const ValidationFailure(
      'Username maksimal $handleMax karakter',
      field: 'handle',
    );
  }
  String? name;
  if (i.platform == SocialPlatform.other) {
    name = cleanLine(i.platformName ?? '');
    if (name.isEmpty) {
      throw const ValidationFailure(
        'Isi nama platform untuk platform Lainnya',
        field: 'platformName',
      );
    }
    if (name.length > platformNameMax) {
      throw const ValidationFailure(
        'Nama platform maksimal $platformNameMax karakter',
        field: 'platformName',
      );
    }
  }
  final t = i.targetPerWeek;
  if (t != null && (t < 0 || t > targetPerWeekMax)) {
    throw const ValidationFailure(
      'Target per minggu 1–$targetPerWeekMax',
      field: 'targetPerWeek',
    );
  }
  return (
    platformName: name,
    handle: handle,
    color: i.color == null ? i.platform.color : requireHex(i.color),
    target: t == null || t == 0 ? null : t,
  );
}

/// Adds an account at the end of the order.
final class CreateSocialAccount {
  const CreateSocialAccount(this._accounts, this._clock);
  final SocialAccountRepository _accounts;
  final Clock _clock;

  Future<Result<SocialAccount>> call(SocialAccountInput input) =>
      guard(() async {
        final v = _validateAccount(input);
        final now = _clock.now();
        final a = SocialAccount(
          id: newId(),
          platform: input.platform,
          platformName: v.platformName,
          handle: v.handle,
          color: v.color,
          targetPerWeek: v.target,
          sortOrder: _nextSort(
            (await _accounts.getAll()).map((x) => x.sortOrder),
          ),
          createdAt: now,
          updatedAt: now,
        );
        await _accounts.save(a);
        return a;
      });
}

/// Full edit (keeps order and archived).
final class UpdateSocialAccount {
  const UpdateSocialAccount(this._accounts, this._clock);
  final SocialAccountRepository _accounts;
  final Clock _clock;

  Future<Result<SocialAccount>> call(String id, SocialAccountInput input) =>
      guard(() async {
        final old = await _accounts.getById(id);
        if (old == null) throw const NotFoundFailure('Akun tidak ditemukan');
        final v = _validateAccount(input);
        final a = old.copyWith(
          platform: input.platform,
          platformName: v.platformName,
          handle: v.handle,
          color: v.color,
          targetPerWeek: v.target,
          updatedAt: _clock.now(),
        );
        await _accounts.save(a);
        return a;
      });
}

/// Archived accounts leave pickers and the calendar slots (posts stay).
final class SetSocialAccountArchived {
  const SetSocialAccountArchived(this._accounts, this._clock);
  final SocialAccountRepository _accounts;
  final Clock _clock;

  Future<Result<SocialAccount>> call(String id, bool archived) =>
      guard(() async {
        final a = await _accounts.getById(id);
        if (a == null) throw const NotFoundFailure('Akun tidak ditemukan');
        if (a.archived == archived) return a;
        final u = a.copyWith(archived: archived, updatedAt: _clock.now());
        await _accounts.save(u);
        return u;
      });
}

/// `[ids in new order]` → sortOrder = index.
final class ReorderSocialAccounts {
  const ReorderSocialAccounts(this._accounts, this._uow, this._clock);
  final SocialAccountRepository _accounts;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<void>> call(List<String> ids) => guard(
    () => _uow.run(() async {
      final now = _clock.now();
      for (final (i, id) in ids.indexed) {
        final a = await _accounts.getById(id);
        if (a == null || a.sortOrder == i) continue;
        await _accounts.save(a.copyWith(sortOrder: i, updatedAt: now));
      }
    }),
  );
}

/// Deletes the account **and all its posts** (confirm in the UI).
final class DeleteSocialAccount {
  const DeleteSocialAccount(this._accounts);
  final SocialAccountRepository _accounts;

  Future<Result<void>> call(String id) => guard(() async {
    if (await _accounts.getById(id) == null) {
      throw const NotFoundFailure('Akun tidak ditemukan');
    }
    await _accounts.delete(id);
  });
}

// ================================================================ pillars

final class ContentPillarInput {
  const ContentPillarInput({required this.name, this.color = '#58CC02'});

  /// 1–30, unique (case-insensitive).
  final String name;
  final String color;
}

String _pillarName(String name, List<ContentPillar> all, {String? exceptId}) {
  final n = cleanLine(name);
  if (n.isEmpty) {
    throw const ValidationFailure('Nama pilar wajib diisi', field: 'name');
  }
  if (n.length > pillarNameMax) {
    throw const ValidationFailure(
      'Nama pilar maksimal $pillarNameMax karakter',
      field: 'name',
    );
  }
  if (pillarNameTaken(all, n, exceptId: exceptId)) {
    throw const ValidationFailure('Pilar ini sudah ada', field: 'name');
  }
  return n;
}

final class CreateContentPillar {
  const CreateContentPillar(this._pillars, this._clock);
  final ContentPillarRepository _pillars;
  final Clock _clock;

  Future<Result<ContentPillar>> call(ContentPillarInput input) =>
      guard(() async {
        final all = await _pillars.getAll();
        final now = _clock.now();
        final p = ContentPillar(
          id: newId(),
          name: _pillarName(input.name, all),
          color: requireHex(input.color),
          sortOrder: _nextSort(all.map((x) => x.sortOrder)),
          createdAt: now,
          updatedAt: now,
        );
        await _pillars.save(p);
        return p;
      });
}

/// Rename/recolor. A rename also renames the pillar on every content item.
final class UpdateContentPillar {
  const UpdateContentPillar(this._pillars, this._clock);
  final ContentPillarRepository _pillars;
  final Clock _clock;

  Future<Result<ContentPillar>> call(String id, ContentPillarInput input) =>
      guard(() async {
        final all = await _pillars.getAll();
        final old = all.where((p) => p.id == id).firstOrNull;
        if (old == null) throw const NotFoundFailure('Pilar tidak ditemukan');
        final p = old.copyWith(
          name: _pillarName(input.name, all, exceptId: id),
          color: requireHex(input.color),
          updatedAt: _clock.now(),
        );
        await _pillars.save(p);
        return p;
      });
}

final class ReorderContentPillars {
  const ReorderContentPillars(this._pillars, this._uow, this._clock);
  final ContentPillarRepository _pillars;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<void>> call(List<String> ids) => guard(
    () => _uow.run(() async {
      final now = _clock.now();
      for (final (i, id) in ids.indexed) {
        final p = await _pillars.getById(id);
        if (p == null || p.sortOrder == i) continue;
        await _pillars.save(p.copyWith(sortOrder: i, updatedAt: now));
      }
    }),
  );
}

/// Deletes a pillar; items with it get `pillar = null`.
final class DeleteContentPillar {
  const DeleteContentPillar(this._pillars);
  final ContentPillarRepository _pillars;

  Future<Result<void>> call(String id) => guard(() async {
    if (await _pillars.getById(id) == null) {
      throw const NotFoundFailure('Pilar tidak ditemukan');
    }
    await _pillars.delete(id);
  });
}

/// Offline fallback: creates the default pillars (deterministic ids) when there
/// is none **and** no pull from a content-aware server has succeeded yet (after
/// that the server owns them). Call it when the Content screen opens. Returns
/// the number created (0 or 5). Pushed as the oldest possible version.
final class SeedDefaultContentPillars {
  const SeedDefaultContentPillars(
    this._pillars,
    this._seedState,
    this._uow,
    this._clock,
  );
  final ContentPillarRepository _pillars;
  final DefaultsSeedState _seedState;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<int>> call(String userId) => guard(
    () => _uow.run(() async {
      if (userId.isEmpty || await _seedState.contentServerSeeded()) return 0;
      if ((await _pillars.getAll()).isNotEmpty) return 0;
      final list = defaultPillars(userId, _clock.now());
      for (final p in list) {
        await _pillars.save(p.copyWith(updatedAt: seedVersion));
      }
      return list.length;
    }),
  );
}

// ================================================================ items

/// Sponsor form data.
final class SponsorInput {
  const SponsorInput({
    required this.brand,
    required this.amount,
    this.currency = 'IDR',
    this.due,
    this.paid = false,
  });

  /// 1–100.
  final String brand;

  /// ≥ 0 (0 = barter).
  final double amount;

  /// 3 letters.
  final String currency;

  /// Payment due day (time ignored).
  final DateTime? due;
  final bool paid;
}

Sponsor _sponsor(SponsorInput i, {Sponsor? old}) {
  final brand = cleanLine(i.brand);
  if (brand.isEmpty) {
    throw const ValidationFailure('Nama brand wajib diisi', field: 'brand');
  }
  if (brand.length > brandMax) {
    throw const ValidationFailure(
      'Nama brand maksimal $brandMax karakter',
      field: 'brand',
    );
  }
  if (!i.amount.isFinite || i.amount < 0) {
    throw const ValidationFailure(
      'Nominal sponsor tidak boleh negatif',
      field: 'amount',
    );
  }
  final cur = i.currency.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(cur)) {
    throw const ValidationFailure(
      'Mata uang harus 3 huruf (mis. IDR)',
      field: 'currency',
    );
  }
  return Sponsor(
    brand: brand,
    amount: i.amount,
    currency: cur,
    due: i.due == null ? null : dateKey(i.due!),
    paid: i.paid,
    transactionId: old?.transactionId,
  );
}

/// Removing a sponsor whose income transaction is still linked is refused:
/// the link would be lost, and paying a re-added sponsor would record the
/// income a second time. Delete that transaction first (the link then clears).
Sponsor? _removeSponsor(Sponsor? old) {
  if (old?.transactionId != null) {
    throw const ValidationFailure(
      'Pemasukan sponsor ini sudah dicatat. Hapus transaksinya dulu sebelum '
      'menghapus sponsor.',
      field: 'sponsor',
    );
  }
  return null;
}

/// Form data of a content item.
final class ContentItemInput {
  const ContentItemInput({
    required this.title,
    this.stage = ContentStage.ide,
    this.format,
    this.pillar,
    this.idea = '',
    this.noteId,
    this.checklist = const [],
    this.photos,
    this.assetLinks = const [],
    this.sponsor,
    this.keepSponsor = true,
  });

  /// 1–200.
  final String title;
  final ContentStage stage;
  final ContentFormat? format;

  /// Pillar name (from `watchContentPillarsProvider`), or null.
  final String? pillar;

  /// Markdown idea / script.
  final String idea;

  /// Source note (conversions set it).
  final String? noteId;
  final List<ChecklistItem> checklist;

  /// ≤ 10. Null = none on create, unchanged on update.
  final List<TransactionPhoto>? photos;

  /// ≤ 20, http(s) URLs.
  final List<AssetLink> assetLinks;

  /// Null + [keepSponsor] (default) keeps the current sponsor on update; pass
  /// `keepSponsor: false` with null to remove it.
  final SponsorInput? sponsor;
  final bool keepSponsor;
}

List<AssetLink> _assetLinks(List<AssetLink> links) {
  final out = <AssetLink>[];
  for (final l in links) {
    final url = l.url.trim();
    if (!isHttpUrl(url)) {
      throw const ValidationFailure(
        'URL harus diawali http:// atau https://',
        field: 'assetLinks',
      );
    }
    final label = l.label == null ? null : cleanLine(l.label!);
    if (label != null && label.length > assetLabelMax) {
      throw const ValidationFailure(
        'Label tautan maksimal $assetLabelMax karakter',
        field: 'assetLinks',
      );
    }
    out.add(
      AssetLink(url: url, label: label == null || label.isEmpty ? null : label),
    );
  }
  if (out.length > maxAssetLinks) {
    throw const ValidationFailure(
      'Maksimal $maxAssetLinks tautan aset',
      field: 'assetLinks',
    );
  }
  return List.unmodifiable(out);
}

List<TransactionPhoto> _contentPhotos(List<TransactionPhoto> photos) {
  final out = <TransactionPhoto>[];
  for (final p in photos) {
    if (!out.contains(p)) out.add(p);
  }
  if (out.length > maxContentPhotos) {
    throw const ValidationFailure(
      'Maksimal $maxContentPhotos foto',
      field: 'photos',
    );
  }
  return List.unmodifiable(out);
}

ContentItem _buildItem(
  String id,
  ContentItemInput i, {
  required ContentItem? old,
  required DateTime now,
}) {
  final title = cleanLine(i.title);
  if (title.isEmpty) {
    throw const ValidationFailure('Judul wajib diisi', field: 'title');
  }
  if (title.length > contentTitleMax) {
    throw const ValidationFailure(
      'Judul maksimal $contentTitleMax karakter',
      field: 'title',
    );
  }
  final idea = cleanText(i.idea);
  if (idea.length > noteBodyMax) {
    throw const ValidationFailure(
      'Ide/naskah terlalu panjang (maks 50.000 karakter)',
      field: 'idea',
    );
  }
  final pillar = i.pillar == null ? null : cleanLine(i.pillar!);
  if (pillar != null && pillar.length > pillarNameMax) {
    throw const ValidationFailure(
      'Nama pilar maksimal $pillarNameMax karakter',
      field: 'pillar',
    );
  }
  return ContentItem(
    id: id,
    title: title,
    stage: i.stage,
    format: i.format,
    pillar: pillar == null || pillar.isEmpty ? null : pillar,
    idea: idea,
    noteId: optionalNonEmpty(i.noteId) ?? (old?.noteId),
    checklist: normalizeChecklist(i.checklist),
    photos: _contentPhotos(i.photos ?? old?.photos ?? const []),
    assetLinks: _assetLinks(i.assetLinks),
    sponsor: i.sponsor != null
        ? _sponsor(i.sponsor!, old: old?.sponsor)
        : (i.keepSponsor ? old?.sponsor : _removeSponsor(old?.sponsor)),
    stageReachedAt: old?.stageReachedAt ?? const {},
    createdAt: old?.createdAt ?? now,
    updatedAt: now,
  );
}

String? optionalNonEmpty(String? v) => v == null || v.isEmpty ? null : v;

Future<ContentItem> _requireItem(ContentItemRepository items, String id) async {
  final i = await items.getById(id);
  if (i == null) throw const NotFoundFailure('Konten tidak ditemukan');
  return i;
}

Future<ContentItem> _saveItem(
  ContentItemRepository items,
  ContentItem i,
) async {
  await items.save(i);
  return await items.getById(i.id) ?? i;
}

final class CreateContentItem {
  const CreateContentItem(this._items, this._clock);
  final ContentItemRepository _items;
  final Clock _clock;

  Future<Result<ContentItem>> call(ContentItemInput input) => guard(
    () => _saveItem(
      _items,
      _buildItem(newId(), input, old: null, now: _clock.now()),
    ),
  );
}

/// Full edit. `photos` null = unchanged; sponsor see [ContentItemInput].
final class UpdateContentItem {
  const UpdateContentItem(this._items, this._clock);
  final ContentItemRepository _items;
  final Clock _clock;

  Future<Result<ContentItem>> call(String id, ContentItemInput input) =>
      guard(() async {
        final old = await _requireItem(_items, id);
        return _saveItem(
          _items,
          _buildItem(id, input, old: old, now: _clock.now()),
        );
      });
}

/// Deletes the item **and its posts**; the source note stays (its
/// `linkedContentId` is cleared).
final class DeleteContentItem {
  const DeleteContentItem(this._items);
  final ContentItemRepository _items;

  Future<Result<void>> call(String id) => guard(() async {
    await _requireItem(_items, id);
    await _items.delete(id);
  });
}

Future<Result<ContentItem>> _patchItem(
  ContentItemRepository items,
  Clock clock,
  String id,
  ContentItem Function(ContentItem i) change,
) => guard(() async {
  final i = await _requireItem(items, id);
  final u = change(i);
  if (u == i) return i;
  return _saveItem(items, u.copyWith(updatedAt: clock.now()));
});

/// Board drag / stage picker (any direction).
final class MoveContentStage {
  const MoveContentStage(this._items, this._clock);
  final ContentItemRepository _items;
  final Clock _clock;

  Future<Result<ContentItem>> call(String id, ContentStage stage) =>
      _patchItem(_items, _clock, id, (i) => i.copyWith(stage: stage));
}

final class SetContentChecklist {
  const SetContentChecklist(this._items, this._clock);
  final ContentItemRepository _items;
  final Clock _clock;

  Future<Result<ContentItem>> call(String id, List<ChecklistItem> items) =>
      _patchItem(
        _items,
        _clock,
        id,
        (i) => i.copyWith(checklist: normalizeChecklist(items)),
      );
}

final class ToggleContentChecklistItem {
  const ToggleContentChecklistItem(this._items, this._clock);
  final ContentItemRepository _items;
  final Clock _clock;

  Future<Result<ContentItem>> call(String id, String itemId) => _patchItem(
    _items,
    _clock,
    id,
    (i) => i.copyWith(checklist: checklistToggle(i.checklist, itemId)),
  );
}

final class AddContentPhotos {
  const AddContentPhotos(this._items, this._clock);
  final ContentItemRepository _items;
  final Clock _clock;

  Future<Result<ContentItem>> call(String id, List<String> filePaths) =>
      _patchItem(
        _items,
        _clock,
        id,
        (i) => i.copyWith(
          photos: _contentPhotos([
            ...i.photos,
            for (final p in filePaths) TransactionPhoto.local(p),
          ]),
        ),
      );
}

final class RemoveContentPhoto {
  const RemoveContentPhoto(this._items, this._clock);
  final ContentItemRepository _items;
  final Clock _clock;

  Future<Result<ContentItem>> call(String id, TransactionPhoto photo) =>
      _patchItem(
        _items,
        _clock,
        id,
        (i) => i.copyWith(
          photos: [
            for (final p in i.photos)
              if (p != photo) p,
          ],
        ),
      );
}

final class SetContentPhotos {
  const SetContentPhotos(this._items, this._clock);
  final ContentItemRepository _items;
  final Clock _clock;

  Future<Result<ContentItem>> call(String id, List<TransactionPhoto> photos) =>
      _patchItem(
        _items,
        _clock,
        id,
        (i) => i.copyWith(photos: _contentPhotos(photos)),
      );
}

/// Sets (or with null removes) the sponsor; keeps a linked transaction.
final class SetContentSponsor {
  const SetContentSponsor(this._items, this._clock);
  final ContentItemRepository _items;
  final Clock _clock;

  Future<Result<ContentItem>> call(String id, SponsorInput? sponsor) =>
      _patchItem(
        _items,
        _clock,
        id,
        (i) => i.copyWith(
          sponsor: sponsor == null
              ? _removeSponsor(i.sponsor)
              : _sponsor(sponsor, old: i.sponsor),
        ),
      );
}

/// "Catat pemasukan" when marking a sponsor paid.
final class SponsorPayment {
  const SponsorPayment({
    required this.walletId,
    this.amount,
    this.categoryId,
    this.date,
    this.note,
  });

  final String walletId;

  /// Default: the sponsor amount (must be > 0).
  final double? amount;

  /// An **income** category, or null.
  final String? categoryId;

  /// Default: now.
  final DateTime? date;

  /// Default: `Endorse <brand>`.
  final String? note;
}

/// Marks the sponsor paid. With [record], an income transaction is recorded
/// through [CreateTransaction] (note `Endorse <brand>`) and linked as
/// `sponsor.transactionId` — never a second one when already linked.
/// All-or-nothing. Returns the item and the new transaction (if any).
final class MarkSponsorPaid {
  const MarkSponsorPaid(
    this._items,
    this._categories,
    this._createTx,
    this._uow,
    this._clock,
  );
  final ContentItemRepository _items;
  final CategoryRepository _categories;
  final CreateTransaction _createTx;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<({ContentItem item, Transaction? transaction})>> call(
    String id, {
    SponsorPayment? record,
  }) => guard(
    () => _uow.run(() async {
      final i = await _requireItem(_items, id);
      final s = i.sponsor;
      if (s == null) {
        throw const ValidationFailure(
          'Konten ini tidak punya sponsor',
          field: 'sponsor',
        );
      }
      Transaction? tx;
      if (record != null && s.transactionId == null) {
        final amount = record.amount ?? s.amount;
        if (!amount.isFinite || amount <= 0) {
          throw const ValidationFailure(
            'Nominal harus lebih dari 0',
            field: 'amount',
          );
        }
        if (record.walletId.isEmpty) {
          throw const ValidationFailure('Pilih dompet', field: 'walletId');
        }
        final cat = optionalNonEmpty(record.categoryId);
        if (cat != null) {
          final c = await _categories.getById(cat);
          if (c == null) {
            throw const NotFoundFailure('Kategori tidak ditemukan');
          }
          if (c.type != CategoryType.income) {
            throw const ValidationFailure(
              'Kategori harus kategori pemasukan',
              field: 'categoryId',
            );
          }
        }
        final note = record.note?.trim();
        tx = (await _createTx(
          TransactionInput(
            type: TxType.income,
            amount: amount,
            walletId: record.walletId,
            categoryId: cat,
            note: note == null || note.isEmpty
                ? sponsorTransactionNote(s.brand)
                : note,
            date: record.date ?? _clock.now(),
          ),
        )).valueOrThrow;
      }
      final u = i.copyWith(
        sponsor: s.copyWith(
          paid: true,
          transactionId: tx?.id ?? s.transactionId,
        ),
        updatedAt: _clock.now(),
      );
      return (item: await _saveItem(_items, u), transaction: tx);
    }),
  );
}

/// Back to unpaid. The recorded transaction stays linked (delete it
/// separately), so marking paid again reuses it instead of recording a second
/// income.
final class MarkSponsorUnpaid {
  const MarkSponsorUnpaid(this._items, this._clock);
  final ContentItemRepository _items;
  final Clock _clock;

  Future<Result<ContentItem>> call(String id) => _patchItem(
    _items,
    _clock,
    id,
    (i) => i.sponsor == null
        ? i
        : i.copyWith(sponsor: i.sponsor!.copyWith(paid: false)),
  );
}

// ================================================================ posts

/// Form data of a post (one account of an item).
final class ContentPostInput {
  const ContentPostInput({
    required this.accountId,
    this.caption = '',
    this.hashtags = '',
    this.scheduledAt,
    this.remindBefore,
    this.url,
  });

  final String accountId;

  /// ≤ 5000.
  final String caption;

  /// Free text, ≤ 1000.
  final String hashtags;

  /// Planned publish time → status `scheduled` (null → `draft`).
  final DateTime? scheduledAt;

  /// Minutes before (0–10080); null = no reminder. Presets:
  /// `remindBeforeOptions`.
  final int? remindBefore;

  /// Link to the live post (http/https), or null.
  final String? url;
}

String? _postUrl(String? v) {
  final u = v?.trim();
  if (u == null || u.isEmpty) return null;
  if (!isHttpUrl(u)) {
    throw const ValidationFailure(
      'URL harus diawali http:// atau https://',
      field: 'url',
    );
  }
  return u;
}

({String caption, String hashtags, int? remindBefore, String? url})
_validatePost(ContentPostInput i) {
  final caption = cleanText(i.caption);
  if (caption.length > captionMax) {
    throw const ValidationFailure(
      'Caption maksimal $captionMax karakter',
      field: 'caption',
    );
  }
  final hashtags = cleanText(i.hashtags).trim();
  if (hashtags.length > hashtagsMax) {
    throw const ValidationFailure(
      'Hashtag maksimal $hashtagsMax karakter',
      field: 'hashtags',
    );
  }
  final r = i.remindBefore;
  if (r != null && (r < 0 || r > remindBeforeMax)) {
    throw const ValidationFailure(
      'Pengingat maksimal 7 hari sebelumnya',
      field: 'remindBefore',
    );
  }
  return (
    caption: caption,
    hashtags: hashtags,
    remindBefore: r,
    url: _postUrl(i.url),
  );
}

/// Recomputes the item's stage after its posts changed (`autoStage`, never
/// backwards) and saves it when it moved.
Future<void> _autoAdvance(
  ContentItemRepository items,
  ContentPostRepository posts,
  String contentId,
  DateTime now,
) async {
  final i = await items.getById(contentId);
  if (i == null) return;
  final next = autoStage(i.stage, await posts.getAll(contentId: contentId));
  if (next != i.stage) {
    await items.save(i.copyWith(stage: next, updatedAt: now));
  }
}

Future<ContentPost> _requirePost(ContentPostRepository posts, String id) async {
  final p = await posts.getById(id);
  if (p == null) throw const NotFoundFailure('Posting tidak ditemukan');
  return p;
}

/// Adds a post for one account (one per account per item). Status = scheduled
/// with a `scheduledAt`, else draft. Auto-advances the item's stage.
final class CreateContentPost {
  const CreateContentPost(
    this._posts,
    this._items,
    this._accounts,
    this._uow,
    this._clock,
  );
  final ContentPostRepository _posts;
  final ContentItemRepository _items;
  final SocialAccountRepository _accounts;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<ContentPost>> call(String contentId, ContentPostInput input) =>
      guard(
        () => _uow.run(() async {
          await _requireItem(_items, contentId);
          if (await _accounts.getById(input.accountId) == null) {
            throw const ValidationFailure(
              'Akun tidak ditemukan',
              field: 'accountId',
            );
          }
          final existing = await _posts.getAll(contentId: contentId);
          if (existing.any((p) => p.accountId == input.accountId)) {
            throw const ValidationFailure(
              'Akun ini sudah punya posting untuk konten ini',
              field: 'accountId',
            );
          }
          final v = _validatePost(input);
          final now = _clock.now();
          final p = ContentPost(
            id: newId(),
            contentId: contentId,
            accountId: input.accountId,
            caption: v.caption,
            hashtags: v.hashtags,
            scheduledAt: input.scheduledAt,
            remindBefore: v.remindBefore,
            status: input.scheduledAt == null
                ? PostStatus.draft
                : PostStatus.scheduled,
            url: v.url,
            createdAt: now,
            updatedAt: now,
          );
          await _posts.save(p);
          await _autoAdvance(_items, _posts, contentId, now);
          return p;
        }),
      );
}

/// Full edit. A draft/scheduled post becomes scheduled/draft by `scheduledAt`;
/// posted/skipped keep their status.
final class UpdateContentPost {
  const UpdateContentPost(this._posts, this._items, this._uow, this._clock);
  final ContentPostRepository _posts;
  final ContentItemRepository _items;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<ContentPost>> call(String id, ContentPostInput input) => guard(
    () => _uow.run(() async {
      final old = await _requirePost(_posts, id);
      final v = _validatePost(input);
      if (input.accountId != old.accountId) {
        final siblings = await _posts.getAll(contentId: old.contentId);
        if (siblings.any((p) => p.id != id && p.accountId == input.accountId)) {
          throw const ValidationFailure(
            'Akun ini sudah punya posting untuk konten ini',
            field: 'accountId',
          );
        }
      }
      final now = _clock.now();
      final status = old.isPosted || old.isSkipped
          ? old.status
          : (input.scheduledAt == null
                ? PostStatus.draft
                : PostStatus.scheduled);
      final p = old.copyWith(
        accountId: input.accountId,
        caption: v.caption,
        hashtags: v.hashtags,
        scheduledAt: input.scheduledAt,
        remindBefore: v.remindBefore,
        status: status,
        url: v.url,
        updatedAt: now,
      );
      await _posts.save(p);
      await _autoAdvance(_items, _posts, p.contentId, now);
      return p;
    }),
  );
}

/// Schedules (or reschedules) a post: status scheduled.
final class ScheduleContentPost {
  const ScheduleContentPost(this._posts, this._items, this._uow, this._clock);
  final ContentPostRepository _posts;
  final ContentItemRepository _items;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<ContentPost>> call(
    String id,
    DateTime at, {
    int? remindBefore,
  }) => guard(
    () => _uow.run(() async {
      final old = await _requirePost(_posts, id);
      if (remindBefore != null &&
          (remindBefore < 0 || remindBefore > remindBeforeMax)) {
        throw const ValidationFailure(
          'Pengingat maksimal 7 hari sebelumnya',
          field: 'remindBefore',
        );
      }
      final now = _clock.now();
      final p = old.copyWith(
        scheduledAt: at,
        remindBefore: remindBefore ?? old.remindBefore,
        status: old.isPosted ? old.status : PostStatus.scheduled,
        updatedAt: now,
      );
      await _posts.save(p);
      await _autoAdvance(_items, _posts, p.contentId, now);
      return p;
    }),
  );
}

/// "Sudah tayang": status posted, `postedAt` = [postedAt] or now, optional URL.
final class MarkPostPosted {
  const MarkPostPosted(this._posts, this._items, this._uow, this._clock);
  final ContentPostRepository _posts;
  final ContentItemRepository _items;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<ContentPost>> call(
    String id, {
    DateTime? postedAt,
    String? url,
  }) => guard(
    () => _uow.run(() async {
      final old = await _requirePost(_posts, id);
      final now = _clock.now();
      final p = old.copyWith(
        status: PostStatus.posted,
        postedAt: postedAt ?? (old.isPosted ? old.postedAt : null) ?? now,
        url: url == null ? old.url : _postUrl(url),
        updatedAt: now,
      );
      await _posts.save(p);
      await _autoAdvance(_items, _posts, p.contentId, now);
      return p;
    }),
  );
}

/// "Lewati": status skipped (skipped posts don't block `tayang`).
final class MarkPostSkipped {
  const MarkPostSkipped(this._posts, this._items, this._uow, this._clock);
  final ContentPostRepository _posts;
  final ContentItemRepository _items;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<ContentPost>> call(String id) => guard(
    () => _uow.run(() async {
      final old = await _requirePost(_posts, id);
      final now = _clock.now();
      final p = old.copyWith(
        status: PostStatus.skipped,
        postedAt: null,
        updatedAt: now,
      );
      await _posts.save(p);
      await _autoAdvance(_items, _posts, p.contentId, now);
      return p;
    }),
  );
}

/// Undo posted/skipped: back to scheduled (with a date) or draft. The item's
/// stage never moves back by itself.
final class ReopenContentPost {
  const ReopenContentPost(this._posts, this._clock);
  final ContentPostRepository _posts;
  final Clock _clock;

  Future<Result<ContentPost>> call(String id) => guard(() async {
    final old = await _requirePost(_posts, id);
    if (!old.isPosted && !old.isSkipped) return old;
    final p = old.copyWith(
      status: old.scheduledAt == null ? PostStatus.draft : PostStatus.scheduled,
      postedAt: null,
      updatedAt: _clock.now(),
    );
    await _posts.save(p);
    return p;
  });
}

/// Manual performance entry (`metricsAt` = now).
final class SetPostMetrics {
  const SetPostMetrics(this._posts, this._clock);
  final ContentPostRepository _posts;
  final Clock _clock;

  Future<Result<ContentPost>> call(String id, PostMetrics metrics) => guard(
    () async {
      final old = await _requirePost(_posts, id);
      for (final v in [
        metrics.views,
        metrics.likes,
        metrics.comments,
        metrics.shares,
        metrics.saves,
        metrics.followers,
      ]) {
        if (v != null && (v < 0 || v > 1e12)) {
          throw const ValidationFailure(
            'Metrik tidak boleh negatif',
            field: 'metrics',
          );
        }
      }
      final now = _clock.now();
      final p = old.copyWith(metrics: metrics, metricsAt: now, updatedAt: now);
      await _posts.save(p);
      return p;
    },
  );
}

final class DeleteContentPost {
  const DeleteContentPost(this._posts, this._items, this._uow, this._clock);
  final ContentPostRepository _posts;
  final ContentItemRepository _items;
  final UnitOfWork _uow;
  final Clock _clock;

  Future<Result<void>> call(String id) => guard(
    () => _uow.run(() async {
      final p = await _requirePost(_posts, id);
      await _posts.delete(id);
      await _autoAdvance(_items, _posts, p.contentId, _clock.now());
    }),
  );
}

// ================================================================ reading

/// Accounts in order (`includeArchived: false` for pickers).
final class WatchSocialAccounts {
  const WatchSocialAccounts(this._accounts);
  final SocialAccountRepository _accounts;

  Stream<List<SocialAccount>> call({bool includeArchived = false}) =>
      _accounts.watchAll().map(
        (l) => [
          for (final a in [...l]..sort(compareAccounts))
            if (includeArchived || !a.archived) a,
        ],
      );
}

final class WatchContentPillars {
  const WatchContentPillars(this._pillars);
  final ContentPillarRepository _pillars;

  Stream<List<ContentPillar>> call() =>
      _pillars.watchAll().map((l) => [...l]..sort(comparePillars));
}

/// The pipeline board for a filter.
final class WatchContentBoard {
  const WatchContentBoard(this._items, this._posts, this._accounts);
  final ContentItemRepository _items;
  final ContentPostRepository _posts;
  final SocialAccountRepository _accounts;

  Stream<ContentBoard> call([ContentFilter filter = ContentFilter.all]) =>
      combineLatest3(
        _items.watchAll(),
        _posts.watchAll(),
        _accounts.watchAll(),
        (List<ContentItem> i, List<ContentPost> p, List<SocialAccount> a) =>
            buildContentBoard(i, p, a, filter),
      ).distinct();
}

/// One item with posts and its source note; null when deleted.
final class WatchContentItem {
  const WatchContentItem(this._items, this._posts, this._accounts, this._notes);
  final ContentItemRepository _items;
  final ContentPostRepository _posts;
  final SocialAccountRepository _accounts;
  final NoteRepository _notes;

  Stream<ContentItemView?> call(String id) => combineLatest4(
    _items.watchById(id),
    _posts.watchAll(),
    _accounts.watchAll(),
    _notes.watchAll(),
    (
      ContentItem? i,
      List<ContentPost> p,
      List<SocialAccount> a,
      List<Note> n,
    ) => i == null
        ? null
        : buildItemViews(
            [i],
            [
              for (final x in p)
                if (x.contentId == id) x,
            ],
            a,
            notes: [
              for (final x in n)
                if (x.id == i.noteId) x,
            ],
          )[id],
  ).distinct();
}

/// One post with its account and item (reminder tap target); null when deleted.
final class WatchContentPost {
  const WatchContentPost(this._posts, this._items, this._accounts);
  final ContentPostRepository _posts;
  final ContentItemRepository _items;
  final SocialAccountRepository _accounts;

  Stream<ContentPostView?> call(String id) => combineLatest3(
    _posts.watchById(id),
    _items.watchAll(),
    _accounts.watchAll(),
    (ContentPost? p, List<ContentItem> i, List<SocialAccount> a) => p == null
        ? null
        : ContentPostView(
            post: p,
            account: a.where((x) => x.id == p.accountId).firstOrNull,
            item: i.where((x) => x.id == p.contentId).firstOrNull,
          ),
  ).distinct();
}

/// Calendar of a local day range (see `weekRange`, `monthGridRange`).
final class WatchContentCalendar {
  const WatchContentCalendar(this._posts, this._items, this._accounts);
  final ContentPostRepository _posts;
  final ContentItemRepository _items;
  final SocialAccountRepository _accounts;

  Stream<ContentCalendar> call(DateTime from, DateTime to) => combineLatest3(
    _posts.watchAll(),
    _items.watchAll(),
    _accounts.watchAll(),
    (List<ContentPost> p, List<ContentItem> i, List<SocialAccount> a) =>
        buildContentCalendar(from, to, p, i, a),
  ).distinct();
}

/// "Tayang hari ini" (re-evaluated every minute; emits on change only).
final class WatchTodayPosts {
  const WatchTodayPosts(this._posts, this._items, this._accounts, this._ticks);
  final ContentPostRepository _posts;
  final ContentItemRepository _items;
  final SocialAccountRepository _accounts;
  final TickSource _ticks;

  Stream<TodayPosts> call() => combineLatest4(
    _posts.watchAll(),
    _items.watchAll(),
    _accounts.watchAll(),
    _ticks(),
    (
      List<ContentPost> p,
      List<ContentItem> i,
      List<SocialAccount> a,
      DateTime now,
    ) => buildTodayPosts(now, p, i, a),
  ).distinct();
}

/// Posted posts waiting for "Isi performa?" (≥ 3 days, no metrics), oldest
/// first.
final class WatchMetricsDue {
  const WatchMetricsDue(this._posts, this._items, this._accounts, this._ticks);
  final ContentPostRepository _posts;
  final ContentItemRepository _items;
  final SocialAccountRepository _accounts;
  final TickSource _ticks;

  Stream<List<ContentPostView>> call() => combineLatest4(
    _posts.watchAll(),
    _items.watchAll(),
    _accounts.watchAll(),
    _ticks(),
    (
      List<ContentPost> p,
      List<ContentItem> i,
      List<SocialAccount> a,
      DateTime now,
    ) {
      final acc = {for (final x in a) x.id: x};
      final items = {for (final x in i) x.id: x};
      final due = p.where((x) => needsMetricsPrompt(x, now)).toList()
        ..sort((x, y) => x.postedAt!.compareTo(y.postedAt!));
      return [
        for (final x in due)
          ContentPostView(
            post: x,
            account: acc[x.accountId],
            item: items[x.contentId],
          ),
      ];
    },
  ).distinct(_listEq);
}

/// Idea inbox: "Ide Konten" notes not converted yet.
final class WatchIdeaInbox {
  const WatchIdeaInbox(this._notes, this._labels);
  final NoteRepository _notes;
  final NoteLabelRepository _labels;

  Stream<List<Note>> call() => combineLatest2(
    _notes.watch(archived: false),
    _labels.watchAll(),
    ideaInbox,
  );
}

/// The report for a local day range (re-evaluated every minute for the
/// in-progress week; emits on change only).
final class WatchContentReport {
  const WatchContentReport(
    this._items,
    this._posts,
    this._accounts,
    this._transactions,
    this._ticks,
  );
  final ContentItemRepository _items;
  final ContentPostRepository _posts;
  final SocialAccountRepository _accounts;
  final TransactionRepository _transactions;
  final TickSource _ticks;

  Stream<ContentReport> call(DateTime from, DateTime to) => combineLatestList(
    [
      _items.watchAll(),
      _posts.watchAll(),
      _accounts.watchAll(),
      _transactions.watch(),
      _ticks(),
    ],
    (v) => buildContentReport(
      from: from,
      to: to,
      now: v[4] as DateTime,
      items: v[0] as List<ContentItem>,
      posts: v[1] as List<ContentPost>,
      accounts: v[2] as List<SocialAccount>,
      txDates: {for (final t in v[3] as List<Transaction>) t.id: t.date},
    ),
  ).distinct();
}
