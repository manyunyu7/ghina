import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/failure.dart';
import '../../../../core/formatters.dart';
import '../../../../core/ids.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/rewards/rewards.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/session_controller.dart';
import '../content_actions.dart';
import '../content_format.dart';
import '../widgets/content_visuals.dart';
import '../widgets/idea_sheets.dart';
import '../widgets/item_sheets.dart';
import '../widgets/markdown_view.dart';

/// New / edit content item: title, stage, format, pillar, idea (Markdown),
/// production checklist, photos, asset links, sponsor and the posts per
/// account.
class ContentItemPage extends ConsumerStatefulWidget {
  const ContentItemPage({super.key, this.id});

  /// Null when creating a new item.
  final String? id;

  @override
  ConsumerState<ContentItemPage> createState() => _ContentItemPageState();
}

/// Everything the form edits (value-equal → dirty check).
typedef _Form = ({
  String title,
  ContentStage stage,
  ContentFormat? format,
  String? pillar,
  String idea,
  List<ChecklistItem> checklist,
  List<TransactionPhoto> photos,
  List<AssetLink> links,
  bool sponsor,
  String brand,
  double amount,
  String? due,
});

bool _sameForm(_Form a, _Form b) =>
    a.title == b.title &&
    a.stage == b.stage &&
    a.format == b.format &&
    a.pillar == b.pillar &&
    a.idea == b.idea &&
    _listEq(a.checklist, b.checklist) &&
    _listEq(a.photos, b.photos) &&
    _listEq(a.links, b.links) &&
    a.sponsor == b.sponsor &&
    (!a.sponsor ||
        (a.brand == b.brand && a.amount == b.amount && a.due == b.due));

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _ContentItemPageState extends ConsumerState<ContentItemPage> {
  final _title = TextEditingController();
  final _idea = TextEditingController();
  final _brand = TextEditingController();
  final _amount = TextEditingController();
  final _newStep = TextEditingController();
  ContentStage _stage = ContentStage.ide;
  ContentFormat? _format;
  String? _pillar;
  List<ChecklistItem> _checklist = const [];
  List<TransactionPhoto> _photos = const [];
  List<AssetLink> _links = const [];
  bool _sponsor = false;
  DateTime? _due;
  bool _preview = false;
  bool _saving = false;
  String? _titleError;
  String? _brandError;

  _Form? _base;
  ContentItem? _loaded;

  bool get _isNew => widget.id == null;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _idea, _brand, _amount]) {
      c.addListener(_changed);
    }
    if (_isNew) _base = _form;
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    for (final c in [_title, _idea, _brand, _amount, _newStep]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _currency => ref.read(currencyProvider);

  _Form get _form => (
    title: _title.text,
    stage: _stage,
    format: _format,
    pillar: _pillar,
    idea: _idea.text,
    checklist: _checklist,
    photos: _photos,
    links: _links,
    sponsor: _sponsor,
    brand: _brand.text,
    amount: parseAmountInput(_amount.text) ?? 0,
    due: _due == null ? null : dateKey(_due!),
  );

  bool get _dirty => _base != null && !_sameForm(_form, _base!);

  void _load(ContentItem i) {
    if (_loaded == i) return;
    if (_loaded != null && _dirty) {
      _loaded = i; // keep the user's edits
      return;
    }
    _loaded = i;
    _title.text = i.title;
    _idea.text = i.idea;
    _stage = i.stage;
    _format = i.format;
    _pillar = i.pillar;
    _checklist = i.checklist;
    _photos = i.photos;
    _links = i.assetLinks;
    final s = i.sponsor;
    _sponsor = s != null;
    _brand.text = s?.brand ?? '';
    _amount.text = s == null || s.amount == 0
        ? ''
        : amountToInput(s.amount, s.currency);
    _due = s?.due == null ? null : parseDateKey(s!.due!);
    _base = _form;
  }

  ContentItemInput _input() => ContentItemInput(
    title: _title.text,
    stage: _stage,
    format: _format,
    pillar: _pillar,
    idea: _idea.text,
    noteId: _loaded?.noteId,
    checklist: _checklist,
    photos: _photos,
    assetLinks: _links,
    sponsor: _sponsor
        ? SponsorInput(
            brand: _brand.text,
            amount: parseAmountInput(_amount.text) ?? 0,
            currency: _loaded?.sponsor?.currency ?? _currency,
            due: _due,
            paid: _loaded?.sponsor?.paid ?? false,
          )
        : null,
    keepSponsor: _sponsor,
  );

  /// Saves; returns the item (null on error). New items replace this route
  /// with the edit page when [stay].
  Future<ContentItem?> _save({bool stay = false, bool quiet = false}) async {
    if (_saving) return null;
    if (!_isNew && !_dirty) return _loaded;
    setState(() {
      _saving = true;
      _titleError = null;
      _brandError = null;
    });
    final from = _loaded?.stage ?? ContentStage.ide;
    final forward = _stage.isAfter(from);
    final rewards = forward ? await RewardTracker.startLoaded(ref) : null;
    final r = _isNew
        ? await ref.read(createContentItemProvider)(_input())
        : await ref.read(updateContentItemProvider)(widget.id!, _input());
    if (!mounted) return null;
    setState(() => _saving = false);
    switch (r) {
      case Ok(:final value):
        _base = _form;
        _loaded = value;
        final to = value.stage;
        final done = quiet
            ? null
            : (_isNew ? 'Konten tersimpan 💡' : 'Tersimpan 👍');
        if (rewards != null) {
          await rewards.finish(
            context,
            xpToast: (xp) => 'Naik ke ${to.emoji} ${to.label}! +$xp XP',
            doneToast: done,
            goalHint: true,
          );
        } else if (done != null) {
          showOkToast(context, done);
        }
        if (!mounted) return value;
        if (_isNew) {
          if (stay) {
            context.pushReplacement(contentItemRoute(value.id));
          } else {
            popOr(context, '/content');
          }
        }
        return value;
      case Err(:final failure):
        if (failure is ValidationFailure && failure.field == 'title') {
          setState(() => _titleError = failure.message);
        } else if (failure is ValidationFailure && failure.field == 'brand') {
          setState(() => _brandError = failure.message);
        } else {
          showFailureToast(context, failure);
        }
        return null;
    }
  }

  Future<void> _delete() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus konten ini?',
      message:
          'Semua posting per akunnya ikut terhapus. Nggak bisa dibatalkan.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deleteContentItemProvider)(widget.id!);
    if (!mounted) return;
    switch (r) {
      case Ok():
        _base = _form;
        showOkToast(context, 'Konten dihapus');
        popOr(context, '/content');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  // ---------------------------------------------------------------- sponsor

  Future<void> _markPaid() async {
    var item = _loaded;
    if (item == null) return;
    if (_dirty || item.sponsor == null) {
      item = await _save(quiet: true);
      if (item == null || !mounted) return;
    }
    final s = item.sponsor;
    if (s == null) return;
    final choice = await showSponsorPaidSheet(context, sponsor: s);
    if (choice == null || !mounted) return;
    final rewards = await RewardTracker.startLoaded(ref);
    final r = await ref.read(markSponsorPaidProvider)(
      item.id,
      record: choice.record && choice.walletId != null
          ? SponsorPayment(walletId: choice.walletId!)
          : null,
    );
    if (!mounted) return;
    switch (r) {
      case Ok(:final value):
        await rewards.finish(
          context,
          xpToast: (xp) => value.transaction != null
              ? 'Cuan masuk! 💰 +$xp XP'
              : 'Sponsor lunas! +$xp XP',
          doneToast: value.transaction != null
              ? 'Pemasukan tercatat 💰'
              : 'Sponsor ditandai lunas',
        );
      case Err(:final failure):
        rewards.cancel();
        showFailureToast(context, failure);
    }
  }

  Future<void> _markUnpaid() async {
    final item = _loaded;
    final s = item?.sponsor;
    if (item == null || s == null) return;
    final txId = s.transactionId;
    final choice = await showChunkyDialog<String>(
      context,
      builder: (c) => ChunkyDialog(
        title: 'Batalkan lunas?',
        message: txId == null
            ? 'Sponsor ${s.brand} kembali jadi belum dibayar.'
            : 'Pemasukan "Endorse ${s.brand}" sudah tercatat. Mau dihapus juga?',
        mood: MascotMood.thinking,
        actions: [
          if (txId != null)
            ChunkyButton(
              key: const ValueKey('unpaid-delete-tx'),
              label: 'Hapus pemasukannya juga',
              variant: ChunkyButtonVariant.danger,
              onPressed: () => Navigator.of(c).pop('delete'),
            ),
          ChunkyButton(
            key: const ValueKey('unpaid-keep'),
            label: txId == null ? 'Batalkan lunas' : 'Simpan pemasukannya',
            variant: txId == null
                ? ChunkyButtonVariant.primary
                : ChunkyButtonVariant.secondary,
            onPressed: () => Navigator.of(c).pop('keep'),
          ),
          ChunkyButton(
            label: 'Batal',
            variant: ChunkyButtonVariant.ghost,
            onPressed: () => Navigator.of(c).pop(),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final r = await ref.read(markSponsorUnpaidProvider)(item.id);
    if (!mounted) return;
    if (r case Err(:final failure)) {
      showFailureToast(context, failure);
      return;
    }
    if (choice == 'delete' && txId != null) {
      final d = await ref.read(deleteTransactionProvider)(txId);
      if (!mounted) return;
      if (d case Err(:final failure)) {
        showFailureToast(context, failure);
        return;
      }
      showOkToast(context, 'Belum lunas, pemasukan dihapus');
    } else {
      showOkToast(context, 'Kembali belum lunas');
    }
  }

  // ---------------------------------------------------------------- posts

  Future<void> _addPost(ContentItemView view) async {
    var item = _loaded;
    if (_dirty) {
      item = await _save(quiet: true);
      if (item == null || !mounted) return;
    }
    final accounts = ref.read(watchSocialAccountsProvider).value ?? const [];
    final id = await showAddPostAccountSheet(
      context,
      accounts: accounts,
      used: {for (final p in view.posts) p.post.accountId},
      onManage: () => context.push('/content/accounts'),
    );
    if (id == null || !mounted) return;
    final r = await ref.read(createContentPostProvider)(
      view.id,
      ContentPostInput(accountId: id),
    );
    if (!mounted) return;
    switch (r) {
      case Ok(:final value):
        context.push(contentPostRoute(value.id));
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  // ---------------------------------------------------------------- photos

  Future<void> _addPhotos() async {
    final paths = await pickPhotos(
      context,
      ref,
      remaining: maxContentPhotos - _photos.length,
      max: maxContentPhotos,
    );
    if (paths.isEmpty || !mounted) return;
    setState(
      () => _photos = [
        ..._photos,
        for (final p in paths) TransactionPhoto.local(p),
      ],
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final async = _isNew
        ? null
        : ref.watch(watchContentItemProvider(widget.id!));
    final view = async?.value;
    if (view != null) _load(view.item);

    final body = _isNew
        ? _buildForm()
        : async!.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingListView(),
            error: (_, _) => ErrorRetry(
              onRetry: () =>
                  ref.invalidate(watchContentItemProvider(widget.id!)),
            ),
            data: (v) => v == null
                ? EmptyState(
                    mood: MascotMood.thinking,
                    title: 'Konten nggak ditemukan',
                    message: 'Mungkin sudah dihapus di perangkat lain.',
                    actionLabel: 'Ke papan konten',
                    onAction: () => context.go('/content'),
                  )
                : _buildForm(v),
          );

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final keep = await showChunkyConfirm(
          this.context,
          title: 'Simpan perubahan?',
          message: 'Ada perubahan yang belum disimpan.',
          confirmLabel: 'Simpan',
          cancelLabel: 'Buang',
        );
        if (!mounted) return;
        if (keep) {
          final saved = await _save(quiet: true);
          if (saved == null || !mounted) return;
          if (_isNew) return; // _save already left the page
        }
        _base = _form;
        if (mounted) popOr(this.context, '/content');
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'Konten baru' : 'Detail konten'),
          actions: [
            if (!_isNew && view != null)
              PopupMenuButton<String>(
                key: const ValueKey('item-overflow'),
                tooltip: 'Menu',
                onSelected: (a) {
                  if (a == 'delete') _delete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('Hapus konten')),
                ],
              ),
          ],
        ),
        bottomNavigationBar: !_isNew && !_dirty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    GhinaSpace.page,
                    8,
                    GhinaSpace.page,
                    12,
                  ),
                  child: ChunkyButton(
                    key: const ValueKey('item-save'),
                    label: 'Simpan',
                    loading: _saving,
                    onPressed: () => _save(),
                  ),
                ),
              ),
        body: body,
      ),
    );
  }

  Widget _buildForm([ContentItemView? view]) {
    final g = context.ghina;
    final pillars = ref.watch(watchContentPillarsProvider).value ?? const [];
    final now = ref.read(clockProvider).now();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        40,
      ),
      children: [
        ChunkyTextField(
          key: const ValueKey('item-title'),
          controller: _title,
          label: 'Judul',
          hint: 'Mis. 5 tips hemat ngopi',
          errorText: _titleError,
          maxLength: contentTitleMax,
          autofocus: _isNew,
        ),
        if (view?.note != null) ...[
          const SizedBox(height: 8),
          ChunkyTile(
            leading: const Icon(Icons.sticky_note_2_rounded),
            title: 'Dari catatan',
            subtitle: view!.note!.displayTitle,
            dense: true,
            showChevron: true,
            onTap: () => context.push(noteRoute(view.note!.id)),
          ),
        ],
        const SizedBox(height: 20),
        const FieldLabel('Tahap'),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              for (final s in ContentStage.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: ChunkyChip(
                      key: ValueKey('item-stage-${s.wire}'),
                      label: s.label,
                      icon: stageIcon(s),
                      selected: _stage == s,
                      color: stageSwatch(s),
                      onTap: () => setState(() => _stage = s),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FormatPillarPicker(
          format: _format,
          pillar: _pillar,
          pillars: pillars,
          onFormat: (f) => setState(() => _format = f),
          onPillar: (p) => setState(() => _pillar = p),
        ),
        const SizedBox(height: 24),
        SectionHeader(
          title: 'Ide & naskah',
          trailing: SizedBox(
            width: 170,
            child: ChunkySegmented<bool>(
              height: 32,
              value: _preview,
              onChanged: (v) => setState(() => _preview = v),
              segments: const [
                ChunkySegment(value: false, label: 'Tulis'),
                ChunkySegment(value: true, label: 'Pratinjau'),
              ],
            ),
          ),
        ),
        if (_preview)
          ChunkyCard(
            key: const ValueKey('idea-preview'),
            padding: const EdgeInsets.all(14),
            child: _idea.text.trim().isEmpty
                ? Text(
                    'Belum ada isi.',
                    style: GhinaType.body.copyWith(color: g.textMuted),
                  )
                : MarkdownView(
                    text: _idea.text,
                    onLink: (u) => confirmOpenContentLink(context, ref, u),
                  ),
          )
        else
          ChunkyTextField(
            key: const ValueKey('item-idea'),
            controller: _idea,
            hint: 'Hook, poin-poin, CTA…\nPakai **tebal**, - daftar, # judul',
            maxLines: 14,
            minLines: 5,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
          ),
        const SizedBox(height: 24),
        SectionHeader(
          title: 'Checklist produksi',
          subtitle: _checklist.isEmpty
              ? null
              : '${_checklist.where((c) => c.done).length}/${_checklist.length} beres',
        ),
        ..._checklistRows(),
        const SizedBox(height: 24),
        SectionHeader(
          title: 'Foto',
          subtitle: '${_photos.length}/$maxContentPhotos',
        ),
        PhotoStrip(
          photos: [
            for (final p in _photos)
              p.isPending
                  ? ViewerPhoto.file(p.localPath!)
                  : ViewerPhoto.network(p.url!),
          ],
          max: maxContentPhotos,
          heroScope: 'content-${widget.id ?? 'new'}',
          onAdd: _addPhotos,
          onRemove: (i) => setState(() => _photos = [..._photos]..removeAt(i)),
        ),
        const SizedBox(height: 24),
        SectionHeader(
          title: 'Link aset',
          actionLabel: _links.length < maxAssetLinks ? 'Tambah' : null,
          onAction: () async {
            final l = await showAssetLinkSheet(context);
            if (l != null) setState(() => _links = [..._links, l]);
          },
        ),
        if (_links.isEmpty)
          Text(
            'Draft Canva, folder Drive, project CapCut…',
            style: GhinaType.bodyS.copyWith(color: g.textMuted),
          ),
        for (var i = 0; i < _links.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChunkyTile(
              key: ValueKey('asset-$i'),
              dense: true,
              leading: Icon(Icons.link_rounded, color: GhinaColors.blue.base),
              title:
                  _links[i].label ??
                  Uri.tryParse(_links[i].url)?.host ??
                  _links[i].url,
              subtitle: _links[i].url,
              onTap: () => openUrlOrToast(context, ref, _links[i].url),
              onLongPress: () async {
                final l = await showAssetLinkSheet(context, initial: _links[i]);
                if (l != null) setState(() => _links = [..._links]..[i] = l);
              },
              trailing: IconButton(
                tooltip: 'Hapus link',
                icon: const Icon(Icons.close_rounded),
                onPressed: () =>
                    setState(() => _links = [..._links]..removeAt(i)),
              ),
            ),
          ),
        const SizedBox(height: 24),
        _sponsorSection(),
        const SizedBox(height: 24),
        SectionHeader(
          title: 'Posting per akun',
          subtitle: view == null || view.posts.isEmpty
              ? null
              : '${view.postedCount}/${view.posts.length} tayang',
        ),
        if (view == null) ...[
          Text(
            'Simpan dulu, lalu pilih akun tujuan (IG, TikTok, …).',
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
          const SizedBox(height: 10),
          ChunkyButton(
            key: const ValueKey('item-save-add'),
            label: 'Simpan & pilih akun',
            icon: Icons.add_rounded,
            variant: ChunkyButtonVariant.outline,
            size: ChunkyButtonSize.medium,
            onPressed: () => _save(stay: true),
          ),
        ] else ...[
          for (final p in view.posts)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PostTile(view: p, now: now),
            ),
          ChunkyButton(
            key: const ValueKey('item-add-post'),
            label: 'Tambah akun',
            icon: Icons.add_rounded,
            variant: ChunkyButtonVariant.outline,
            size: ChunkyButtonSize.medium,
            onPressed: () => _addPost(view),
          ),
        ],
      ],
    );
  }

  List<Widget> _checklistRows() {
    final g = context.ghina;
    return [
      for (final c in _checklist)
        Padding(
          key: ValueKey('step-${c.id}'),
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Checkbox(
                value: c.done,
                onChanged: (_) => setState(
                  () => _checklist = checklistToggle(_checklist, c.id),
                ),
              ),
              Expanded(
                child: Text(
                  c.text,
                  style: GhinaType.body.copyWith(
                    color: c.done ? g.textMuted : g.textPrimary,
                    decoration: c.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Hapus langkah',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, color: g.textMuted),
                onPressed: () => setState(
                  () => _checklist = checklistRemove(_checklist, c.id),
                ),
              ),
            ],
          ),
        ),
      ChunkyTextField(
        key: const ValueKey('step-new'),
        controller: _newStep,
        hint: 'Tambah langkah (mis. Rekam B-roll)',
        prefixIcon: Icons.add_task_rounded,
        textInputAction: TextInputAction.done,
        onSubmitted: (t) {
          if (t.trim().isEmpty) return;
          try {
            setState(() {
              _checklist = checklistAdd(_checklist, t.trim(), id: newId());
              _newStep.clear();
            });
          } on ValidationFailure catch (e) {
            showErrorToast(context, e.message);
          }
        },
      ),
    ];
  }

  Widget _sponsorSection() {
    final g = context.ghina;
    final saved = _loaded?.sponsor;
    final paid = saved?.paid ?? false;
    final currency = saved?.currency ?? _currency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Sponsor',
                style: GhinaType.h2.copyWith(color: g.textPrimary),
              ),
            ),
            if (paid)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: ChunkyPill(label: 'Lunas', color: GhinaColors.green),
              ),
            Switch(
              key: const ValueKey('sponsor-toggle'),
              value: _sponsor,
              onChanged: paid ? null : (v) => setState(() => _sponsor = v),
            ),
          ],
        ),
        if (!_sponsor)
          Text(
            'Endorse? Catat brand dan nominalnya biar nggak lupa ditagih.',
            style: GhinaType.bodyS.copyWith(color: g.textMuted),
          )
        else ...[
          const SizedBox(height: 8),
          ChunkyTextField(
            key: const ValueKey('sponsor-brand'),
            controller: _brand,
            label: 'Brand',
            hint: 'Mis. Kopi Kenangan',
            errorText: _brandError,
            maxLength: brandMax,
            enabled: !paid,
          ),
          const SizedBox(height: 12),
          AmountField(
            key: const ValueKey('sponsor-amount'),
            controller: _amount,
            currency: currency,
            label: 'Nominal',
            helperText: 'Kosongkan / 0 kalau barter',
          ),
          const SizedBox(height: 12),
          PickerField(
            key: const ValueKey('sponsor-due'),
            label: 'Jatuh tempo (opsional)',
            value: _due == null ? null : Fmt.dateFull(_due!),
            placeholder: 'Tanpa tanggal',
            leading: Icon(Icons.event_rounded, color: GhinaColors.orange.base),
            trailingIcon: _due == null
                ? Icons.calendar_month_rounded
                : Icons.close_rounded,
            onTap: () async {
              if (_due != null) {
                setState(() => _due = null);
                return;
              }
              final d = await showGhinaDatePicker(
                context,
                initial: ref.read(clockProvider).now(),
                title: 'Jatuh tempo',
              );
              if (d != null) setState(() => _due = startOfDay(d));
            },
          ),
          const SizedBox(height: 14),
          if (_loaded != null && !paid)
            ChunkyButton(
              key: const ValueKey('sponsor-paid'),
              label: 'Tandai dibayar',
              icon: Icons.payments_rounded,
              color: GhinaColors.green,
              size: ChunkyButtonSize.medium,
              onPressed: _markPaid,
            ),
          if (paid) ...[
            if (saved?.transactionId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: GhinaColors.green.base,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Tercatat sebagai pemasukan "Endorse ${saved!.brand}"',
                        style: GhinaType.bodyS
                            .w(700)
                            .copyWith(color: g.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ChunkyButton(
              key: const ValueKey('sponsor-unpaid'),
              label: 'Batalkan lunas',
              variant: ChunkyButtonVariant.ghost,
              size: ChunkyButtonSize.medium,
              onPressed: _markUnpaid,
            ),
          ],
        ],
      ],
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.view, required this.now});
  final ContentPostView view;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = view.post;
    final a = view.account;
    final when = p.isPosted && p.postedAt != null
        ? 'Tayang ${contentWhenLabel(p.postedAt!, now)}'
        : p.scheduledAt != null
        ? contentWhenLabel(p.scheduledAt!, now)
        : 'Belum dijadwal';
    return ChunkyTile(
      key: ValueKey('item-post-${view.id}'),
      leading: a == null
          ? const Icon(Icons.help_outline_rounded)
          : AccountAvatar(account: a, size: 40, status: p.status),
      title: a?.atHandle ?? 'Akun terhapus',
      subtitle: when,
      trailing: PostStatusPill(status: p.status),
      onTap: () => context.push(contentPostRoute(view.id)),
    );
  }
}
