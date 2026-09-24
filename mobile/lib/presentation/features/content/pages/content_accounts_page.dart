import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../widgets/content_visuals.dart';

/// Akun & pilar: the user's social accounts (platform, handle, weekly
/// target, archive, order) and the content pillars.
class ContentAccountsPage extends ConsumerWidget {
  const ContentAccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(watchAllSocialAccountsProvider);
    final pillars = ref.watch(watchContentPillarsProvider);
    final g = context.ghina;

    Future<void> reorderAccounts(
      List<SocialAccount> list,
      int from,
      int to,
    ) async {
      final ids = [for (final a in list) a.id];
      final id = ids.removeAt(from);
      ids.insert(to, id);
      final r = await ref.read(reorderSocialAccountsProvider)(ids);
      if (r case Err(:final failure) when context.mounted) {
        showFailureToast(context, failure);
      }
    }

    Future<void> reorderPillars(
      List<ContentPillar> list,
      int from,
      int to,
    ) async {
      final ids = [for (final p in list) p.id];
      final id = ids.removeAt(from);
      ids.insert(to, id);
      final r = await ref.read(reorderContentPillarsProvider)(ids);
      if (r case Err(:final failure) when context.mounted) {
        showFailureToast(context, failure);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Akun & pilar')),
      body: RefreshIndicator(
        onRefresh: () => pullToSync(context, ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                8,
                GhinaSpace.page,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Akun sosmed',
                  subtitle: 'Tahan ≡ untuk mengurutkan',
                  actionLabel: 'Tambah',
                  onAction: () => showAccountSheet(context),
                ),
              ),
            ),
            ...accounts.when(
              skipLoadingOnReload: true,
              loading: () => [
                const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 180,
                    child: LoadingListView(hero: false, tiles: 2),
                  ),
                ),
              ],
              error: (_, _) => [
                SliverToBoxAdapter(
                  child: ErrorRetry(
                    compact: true,
                    onRetry: () =>
                        ref.invalidate(watchAllSocialAccountsProvider),
                  ),
                ),
              ],
              data: (list) => list.isEmpty
                  ? [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: GhinaSpace.page,
                          ),
                          child: EmptyState(
                            compact: true,
                            mood: MascotMood.waving,
                            title: 'Belum ada akun',
                            message:
                                'Tambahkan akun IG, TikTok, YouTube… yang mau kamu isi rutin.',
                            actionLabel: 'Tambah akun',
                            onAction: () => showAccountSheet(context),
                          ),
                        ),
                      ),
                    ]
                  : [
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GhinaSpace.page,
                        ),
                        sliver: SliverReorderableList(
                          itemCount: list.length,
                          onReorderItem: (a, b) => reorderAccounts(list, a, b),
                          proxyDecorator: (child, _, _) => Material(
                            type: MaterialType.transparency,
                            child: child,
                          ),
                          itemBuilder: (context, i) {
                            final a = list[i];
                            return Padding(
                              key: ValueKey('account-${a.id}'),
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Opacity(
                                opacity: a.archived ? 0.55 : 1,
                                child: ChunkyTile(
                                  leading: AccountAvatar(account: a, size: 42),
                                  title: a.atHandle,
                                  subtitle: [
                                    a.platformLabel,
                                    if (a.hasTarget)
                                      'target ${a.targetPerWeek}/minggu',
                                    if (a.archived) 'diarsipkan',
                                  ].join(' · '),
                                  onTap: () =>
                                      showAccountSheet(context, account: a),
                                  trailing: ReorderableDragStartListener(
                                    index: i,
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Icon(
                                        Icons.drag_handle_rounded,
                                        color: g.textMuted,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                GhinaSpace.page,
                20,
                GhinaSpace.page,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Pilar konten',
                  subtitle: 'Tema besar kontenmu',
                  actionLabel: 'Tambah',
                  onAction: () => showPillarSheet(context),
                ),
              ),
            ),
            ...pillars.when(
              skipLoadingOnReload: true,
              loading: () => [
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
              error: (_, _) => [
                SliverToBoxAdapter(
                  child: ErrorRetry(
                    compact: true,
                    onRetry: () => ref.invalidate(watchContentPillarsProvider),
                  ),
                ),
              ],
              data: (list) => list.isEmpty
                  ? [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: GhinaSpace.page,
                          ),
                          child: Text(
                            'Belum ada pilar. Contoh: Edukasi, Hiburan, Promo.',
                            style: GhinaType.bodyS.copyWith(color: g.textMuted),
                          ),
                        ),
                      ),
                    ]
                  : [
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GhinaSpace.page,
                        ),
                        sliver: SliverReorderableList(
                          itemCount: list.length,
                          onReorderItem: (a, b) => reorderPillars(list, a, b),
                          proxyDecorator: (child, _, _) => Material(
                            type: MaterialType.transparency,
                            child: child,
                          ),
                          itemBuilder: (context, i) {
                            final p = list[i];
                            return Padding(
                              key: ValueKey('pillar-${p.id}'),
                              padding: const EdgeInsets.only(bottom: 10),
                              child: ChunkyTile(
                                dense: true,
                                leading: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: readableColor(context, p.color),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                title: p.name,
                                onTap: () =>
                                    showPillarSheet(context, pillar: p),
                                trailing: ReorderableDragStartListener(
                                  index: i,
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.drag_handle_rounded,
                                      color: g.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 60)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- account sheet

Future<void> showAccountSheet(BuildContext context, {SocialAccount? account}) =>
    showChunkyBottomSheet<void>(
      context,
      title: account == null ? 'Tambah akun' : 'Ubah akun',
      showClose: true,
      builder: (_) => _AccountSheet(account: account),
    );

class _AccountSheet extends ConsumerStatefulWidget {
  const _AccountSheet({this.account});
  final SocialAccount? account;

  @override
  ConsumerState<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends ConsumerState<_AccountSheet> {
  late SocialPlatform _platform =
      widget.account?.platform ?? SocialPlatform.instagram;
  late final _handle = TextEditingController(
    text: widget.account?.handle ?? '',
  );
  late final _name = TextEditingController(
    text: widget.account?.platformName ?? '',
  );
  late int _target = widget.account?.targetPerWeek ?? 3;
  late String? _color = widget.account?.color;
  String? _handleError;
  String? _nameError;
  bool _busy = false;

  @override
  void dispose() {
    _handle.dispose();
    _name.dispose();
    super.dispose();
  }

  String get _effectiveColor => _color ?? _platform.color;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _handleError = null;
      _nameError = null;
    });
    final input = SocialAccountInput(
      platform: _platform,
      handle: _handle.text,
      platformName: _platform == SocialPlatform.other ? _name.text : null,
      color: _color,
      targetPerWeek: _target == 0 ? null : _target,
    );
    final a = widget.account;
    final r = a == null
        ? await ref.read(createSocialAccountProvider)(input)
        : await ref.read(updateSocialAccountProvider)(a.id, input);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case Ok():
        Navigator.of(context).pop();
        showOkToast(
          context,
          a == null ? 'Akun ditambahkan 🎉' : 'Akun tersimpan',
        );
      case Err(:final failure):
        if (failure is ValidationFailure && failure.field == 'handle') {
          setState(() => _handleError = failure.message);
        } else if (failure is ValidationFailure &&
            failure.field == 'platformName') {
          setState(() => _nameError = failure.message);
        } else {
          showFailureToast(context, failure);
        }
    }
  }

  Future<void> _archive(bool archived) async {
    final r = await ref.read(setSocialAccountArchivedProvider)(
      widget.account!.id,
      archived,
    );
    if (!mounted) return;
    switch (r) {
      case Ok():
        Navigator.of(context).pop();
        showOkToast(context, archived ? 'Akun diarsipkan' : 'Akun aktif lagi');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  Future<void> _delete() async {
    final a = widget.account!;
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus ${a.atHandle}?',
      message:
          'Semua posting untuk akun ini ikut terhapus (kontennya tetap ada). Kalau cuma mau disembunyikan, arsipkan saja.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deleteSocialAccountProvider)(a.id);
    if (!mounted) return;
    switch (r) {
      case Ok():
        Navigator.of(context).pop();
        showOkToast(context, 'Akun dihapus');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final a = widget.account;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Platform'),
        LayoutBuilder(
          builder: (context, c) {
            final w = (c.maxWidth - 8 * 3) / 4;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in SocialPlatform.values)
                  SizedBox(
                    width: w,
                    child: _PlatformTile(
                      platform: p,
                      selected: p == _platform,
                      onTap: () => setState(() {
                        if (_color == _platform.color) _color = null;
                        _platform = p;
                      }),
                    ),
                  ),
              ],
            );
          },
        ),
        if (_platform == SocialPlatform.other) ...[
          const SizedBox(height: 12),
          ChunkyTextField(
            key: const ValueKey('account-platform-name'),
            controller: _name,
            label: 'Nama platform',
            hint: 'Mis. Pinterest',
            maxLength: platformNameMax,
            errorText: _nameError,
          ),
        ],
        const SizedBox(height: 12),
        ChunkyTextField(
          key: const ValueKey('account-handle'),
          controller: _handle,
          label: 'Username / nama channel',
          hint: '@username',
          textCapitalization: TextCapitalization.none,
          maxLength: handleMax,
          errorText: _handleError,
        ),
        const SizedBox(height: 12),
        FieldLabel(
          'Target per minggu',
          trailing: Text(
            _target == 0 ? 'Tanpa target' : '$_target posting',
            key: const ValueKey('account-target-value'),
            style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
          ),
        ),
        Row(
          children: [
            ChunkyIconButton(
              key: const ValueKey('account-target-minus'),
              icon: Icons.remove_rounded,
              tooltip: 'Kurangi',
              onPressed: _target > 0 ? () => setState(() => _target--) : null,
            ),
            Expanded(
              child: Slider(
                value: _target.toDouble().clamp(0, 14),
                max: 14,
                divisions: 14,
                onChanged: (v) => setState(() => _target = v.round()),
              ),
            ),
            ChunkyIconButton(
              key: const ValueKey('account-target-plus'),
              icon: Icons.add_rounded,
              tooltip: 'Tambah',
              onPressed: _target < targetPerWeekMax
                  ? () => setState(() => _target++)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const FieldLabel('Warna'),
        ChunkyColorPicker(
          selected: _effectiveColor,
          palette: [
            _platform.color,
            for (final c in CategoryColors.palette)
              if (c.toLowerCase() != _platform.color.toLowerCase()) c,
          ],
          onChanged: (c) => setState(() => _color = c),
        ),
        const SizedBox(height: 20),
        ChunkyButton(
          key: const ValueKey('account-save'),
          label: 'Simpan',
          loading: _busy,
          onPressed: _save,
        ),
        if (a != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChunkyButton(
                  key: const ValueKey('account-archive'),
                  label: a.archived ? 'Aktifkan' : 'Arsipkan',
                  variant: ChunkyButtonVariant.ghost,
                  size: ChunkyButtonSize.medium,
                  onPressed: () => _archive(!a.archived),
                ),
              ),
              Expanded(
                child: ChunkyButton(
                  key: const ValueKey('account-delete'),
                  label: 'Hapus',
                  variant: ChunkyButtonVariant.ghost,
                  color: GhinaColors.red,
                  size: ChunkyButtonSize.medium,
                  onPressed: _delete,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PlatformTile extends StatelessWidget {
  const _PlatformTile({
    required this.platform,
    required this.selected,
    required this.onTap,
  });

  final SocialPlatform platform;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final c = readableColor(context, platform.color);
    final on = c.computeLuminance() > 0.55
        ? const Color(0xFF2B2B2B)
        : Colors.white;
    return ChunkySurface(
      key: ValueKey('platform-${platform.wire}'),
      color: selected ? c.withValues(alpha: g.isDark ? 0.25 : 0.12) : g.surface,
      edgeColor: selected ? c : g.borderEdge,
      borderColor: selected ? c : g.border,
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rMd,
      onTap: onTap,
      semanticLabel: platform.label,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            child: Icon(platformIcon(platform), size: 17, color: on),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              platform.label,
              style: GhinaType.caption.w(800).copyWith(color: g.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- pillar sheet

Future<void> showPillarSheet(BuildContext context, {ContentPillar? pillar}) =>
    showChunkyBottomSheet<void>(
      context,
      title: pillar == null ? 'Pilar baru' : 'Ubah pilar',
      showClose: true,
      builder: (_) => _PillarSheet(pillar: pillar),
    );

class _PillarSheet extends ConsumerStatefulWidget {
  const _PillarSheet({this.pillar});
  final ContentPillar? pillar;

  @override
  ConsumerState<_PillarSheet> createState() => _PillarSheetState();
}

class _PillarSheetState extends ConsumerState<_PillarSheet> {
  late final _name = TextEditingController(text: widget.pillar?.name ?? '');
  late String _color = widget.pillar?.color ?? CategoryColors.palette.first;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final p = widget.pillar;
    final input = ContentPillarInput(name: _name.text, color: _color);
    final r = p == null
        ? await ref.read(createContentPillarProvider)(input)
        : await ref.read(updateContentPillarProvider)(p.id, input);
    if (!mounted) return;
    switch (r) {
      case Ok():
        Navigator.of(context).pop();
        final renamed = p != null && p.name != _name.text.trim();
        showOkToast(
          context,
          renamed ? 'Pilar diganti, kontennya ikut 👍' : 'Pilar tersimpan',
        );
      case Err(:final failure):
        setState(() => _error = failure.message);
    }
  }

  Future<void> _delete() async {
    final p = widget.pillar!;
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus pilar ${p.name}?',
      message:
          'Konten dengan pilar ini jadi tanpa pilar. Kontennya sendiri tetap aman.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deleteContentPillarProvider)(p.id);
    if (!mounted) return;
    switch (r) {
      case Ok():
        Navigator.of(context).pop();
        showOkToast(context, 'Pilar dihapus');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pillar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkyTextField(
          key: const ValueKey('pillar-name'),
          controller: _name,
          label: 'Nama pilar',
          hint: 'Mis. Edukasi',
          maxLength: pillarNameMax,
          autofocus: p == null,
          errorText: _error,
        ),
        if (p != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Ganti nama = semua konten berpilar ini ikut diganti.',
              style: GhinaType.caption.copyWith(color: context.ghina.textMuted),
            ),
          ),
        const SizedBox(height: 12),
        const FieldLabel('Warna'),
        ChunkyColorPicker(
          selected: _color,
          onChanged: (c) => setState(() => _color = c),
        ),
        const SizedBox(height: 20),
        ChunkyButton(
          key: const ValueKey('pillar-save'),
          label: 'Simpan',
          onPressed: _save,
        ),
        if (p != null) ...[
          const SizedBox(height: 8),
          ChunkyButton(
            key: const ValueKey('pillar-delete'),
            label: 'Hapus pilar',
            variant: ChunkyButtonVariant.ghost,
            color: GhinaColors.red,
            size: ChunkyButtonSize.medium,
            onPressed: _delete,
          ),
        ],
      ],
    );
  }
}
