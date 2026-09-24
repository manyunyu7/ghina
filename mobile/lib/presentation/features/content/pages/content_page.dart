import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/session_controller.dart';
import '../content_actions.dart';
import '../widgets/calendar_tab.dart';
import '../widgets/content_card.dart';
import '../widgets/content_visuals.dart';
import '../widgets/idea_sheets.dart';

enum ContentTab { board, inbox, calendar }

/// Konten: the pipeline board (Papan), the idea inbox (Ide masuk) and the
/// posting calendar (Kalender).
class ContentPage extends ConsumerStatefulWidget {
  const ContentPage({super.key, this.initialTab = ContentTab.board});

  final ContentTab initialTab;

  @override
  ConsumerState<ContentPage> createState() => _ContentPageState();
}

class _ContentPageState extends ConsumerState<ContentPage> {
  late ContentTab _tab = widget.initialTab;
  ContentStage _stage = ContentStage.ide;
  ContentFilter _filter = ContentFilter.all;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _seedPillars());
  }

  /// Offline fallback only (a no-op once the server seeded them).
  Future<void> _seedPillars() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    await ref.read(seedDefaultContentPillarsProvider)(user.id);
  }

  Future<void> _quickAdd() async {
    final item = await showQuickAddIdeaSheet(
      context,
      stage: _tab == ContentTab.board ? _stage : ContentStage.ide,
    );
    if (item == null || !mounted) return;
    setState(() {
      _tab = ContentTab.board;
      _stage = item.stage;
    });
    showOkToast(context, 'Ide tersimpan 💡');
  }

  @override
  Widget build(BuildContext context) {
    // Icons only when the three tab labels fit comfortably.
    final roomy =
        MediaQuery.sizeOf(context).width /
            MediaQuery.textScalerOf(context).scale(1) >=
        370;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Konten'),
        actions: [
          IconButton(
            key: const ValueKey('content-report'),
            tooltip: 'Laporan',
            icon: const Icon(Icons.insights_rounded),
            onPressed: () => context.push('/content/report'),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('content-overflow'),
            tooltip: 'Menu',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) => context.push(v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: '/content/accounts',
                child: ListTile(
                  leading: Icon(Icons.manage_accounts_rounded),
                  title: Text('Akun & pilar'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: '/content/report',
                child: ListTile(
                  leading: Icon(Icons.insights_rounded),
                  title: Text('Laporan'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: _tab == ContentTab.inbox
          ? null
          : FloatingActionButton(
              key: const ValueKey('content-add'),
              tooltip: 'Ide baru',
              onPressed: _quickAdd,
              child: const Icon(Icons.add_rounded, size: 30),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              4,
              GhinaSpace.page,
              8,
            ),
            child: ChunkySegmented<ContentTab>(
              height: 40,
              value: _tab,
              onChanged: (t) => setState(() => _tab = t),
              segments: [
                ChunkySegment(
                  value: ContentTab.board,
                  label: 'Papan',
                  icon: roomy ? Icons.view_kanban_rounded : null,
                ),
                ChunkySegment(
                  value: ContentTab.inbox,
                  label: 'Ide masuk',
                  icon: roomy ? Icons.inbox_rounded : null,
                  color: GhinaColors.orange,
                ),
                ChunkySegment(
                  value: ContentTab.calendar,
                  label: 'Kalender',
                  icon: roomy ? Icons.calendar_month_rounded : null,
                  color: GhinaColors.purple,
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (_tab) {
              ContentTab.board => _board(),
              ContentTab.inbox => const _InboxTab(),
              ContentTab.calendar => const ContentCalendarTab(),
            },
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ board

  Widget _board() {
    final boardAsync = ref.watch(watchContentBoardProvider(_filter));
    final accounts = ref.watch(watchSocialAccountsProvider).value;
    final pillars = ref.watch(watchContentPillarsProvider).value ?? const [];
    final due = ref.watch(watchMetricsDueProvider).value ?? const [];
    final now = ref.read(clockProvider).now();
    final board = boardAsync.value;

    return RefreshIndicator(
      onRefresh: () => pullToSync(context, ref),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (due.isNotEmpty)
            SliverToBoxAdapter(child: _MetricsDueBanner(due: due)),
          if (accounts != null && accounts.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  GhinaSpace.page,
                  0,
                  GhinaSpace.page,
                  12,
                ),
                child: ChunkyCard(
                  tinted: GhinaColors.blue,
                  onTap: () => context.push('/content/accounts'),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_add_alt_1_rounded,
                        color: GhinaColors.blue.base,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Tambahkan akun sosmed kamu biar bisa dijadwalkan.',
                          style: GhinaType.bodyS
                              .w(700)
                              .copyWith(color: context.ghina.textPrimary),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: context.ghina.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: _StageBar(
              board: board,
              selected: _stage,
              dragging: _dragging,
              onSelect: (s) => setState(() => _stage = s),
              onDrop: (v, s) async {
                await moveStageFlow(context, ref, v.item, s);
              },
            ),
          ),
          SliverToBoxAdapter(
            child: _FilterBar(
              filter: _filter,
              accounts: accounts ?? const [],
              pillars: pillars,
              onChanged: (f) => setState(() => _filter = f),
            ),
          ),
          ...boardAsync.when(
            skipLoadingOnReload: true,
            loading: () => [
              const SliverToBoxAdapter(
                child: SizedBox(
                  height: 320,
                  child: LoadingListView(hero: false, tiles: 3),
                ),
              ),
            ],
            error: (_, _) => [
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorRetry(
                  compact: true,
                  onRetry: () =>
                      ref.invalidate(watchContentBoardProvider(_filter)),
                ),
              ),
            ],
            data: (b) => _column(b, pillars, now),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  List<Widget> _column(
    ContentBoard b,
    List<ContentPillar> pillars,
    DateTime now,
  ) {
    final items = b.column(_stage).items;
    if (items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: GhinaSpace.page),
            child: _emptyStage(b),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          GhinaSpace.page,
          4,
          GhinaSpace.page,
          0,
        ),
        sliver: SliverLayoutBuilder(
          builder: (context, c) => SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final v = items[i];
              final card = ContentCard(
                view: v,
                pillars: pillars,
                now: now,
                onTap: () => context.push(contentItemRoute(v.id)),
                onMenu: () => _moveSheet(v),
                onAdvance: () {
                  final next = ContentStage.values[v.stage.index + 1];
                  moveStageFlow(context, ref, v.item, next);
                },
              );
              return Padding(
                key: ValueKey('board-${v.id}'),
                padding: const EdgeInsets.only(bottom: 12),
                child: LongPressDraggable<ContentItemView>(
                  data: v,
                  onDragStarted: () => setState(() => _dragging = true),
                  onDragEnd: (_) => setState(() => _dragging = false),
                  feedback: SizedBox(
                    width: c.crossAxisExtent,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Transform.rotate(
                        angle: -0.03,
                        child: Opacity(opacity: 0.92, child: card),
                      ),
                    ),
                  ),
                  childWhenDragging: Opacity(opacity: 0.3, child: card),
                  child: card,
                ),
              );
            },
          ),
        ),
      ),
    ];
  }

  Future<void> _moveSheet(ContentItemView v) async {
    final to = await showStagePickerSheet(context, item: v.item);
    if (to == null || !mounted) return;
    await moveStageFlow(context, ref, v.item, to);
  }

  Widget _emptyStage(ContentBoard b) {
    if (!_filter.isEmpty) {
      return EmptyState(
        compact: true,
        mood: MascotMood.thinking,
        title: 'Nggak ada yang cocok',
        message: 'Coba longgarkan filternya.',
        actionLabel: 'Hapus filter',
        onAction: () => setState(() => _filter = ContentFilter.all),
      );
    }
    if (_stage == ContentStage.ide) {
      return EmptyState(
        compact: true,
        title: b.isEmpty ? 'Papan masih kosong' : 'Belum ada ide baru',
        message: 'Tulis ide kontenmu dulu, nanti digeser sampai tayang 🚀',
        actionLabel: 'Tambah ide',
        onAction: _quickAdd,
      );
    }
    final prev = ContentStage.values[_stage.index - 1];
    return EmptyState(
      compact: true,
      mood: MascotMood.happy,
      title: 'Kosong di ${_stage.label}',
      message: 'Geser konten dari ${prev.label} ke sini kalau sudah siap.',
      actionLabel: 'Lihat ${prev.label}',
      onAction: () => setState(() => _stage = prev),
    );
  }
}

// ---------------------------------------------------------------- stage bar

class _StageBar extends StatelessWidget {
  const _StageBar({
    required this.board,
    required this.selected,
    required this.dragging,
    required this.onSelect,
    required this.onDrop,
  });

  final ContentBoard? board;
  final ContentStage selected;
  final bool dragging;
  final ValueChanged<ContentStage> onSelect;
  final void Function(ContentItemView, ContentStage) onDrop;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            4,
            GhinaSpace.page,
            8,
          ),
          child: Row(
            children: [
              for (final s in ContentStage.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    height: 48,
                    child: DragTarget<ContentItemView>(
                      onWillAcceptWithDetails: (d) => d.data.stage != s,
                      onAcceptWithDetails: (d) => onDrop(d.data, s),
                      builder: (context, cand, _) => _StageChip(
                        stage: s,
                        count: board?.column(s).items.length,
                        selected: s == selected,
                        hovering: cand.isNotEmpty,
                        onTap: () => onSelect(s),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: GhinaMotion.fast,
          child: dragging
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                    GhinaSpace.page,
                    0,
                    GhinaSpace.page,
                    4,
                  ),
                  child: Text(
                    'Lepas di tahap tujuan ↑',
                    style: GhinaType.bodyS
                        .w(700)
                        .copyWith(color: g.textSecondary),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({
    required this.stage,
    required this.count,
    required this.selected,
    required this.hovering,
    required this.onTap,
  });

  final ContentStage stage;
  final int? count;
  final bool selected;
  final bool hovering;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = stageSwatch(stage);
    final active = selected || hovering;
    return AnimatedScale(
      scale: hovering ? 1.08 : 1,
      duration: GhinaMotion.fast,
      child: ChunkySurface(
        key: ValueKey('stage-${stage.wire}'),
        color: active ? sw.tint(g.brightness) : g.surface,
        edgeColor: active ? sw.base : g.borderEdge,
        borderColor: active ? sw.base : g.border,
        depth: GhinaDepth.sm,
        borderRadius: GhinaRadii.rLg,
        onTap: onTap,
        semanticLabel: '${stage.label} ${count ?? 0}',
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(stageIcon(stage), size: 20, color: stageColor(context, stage)),
            const SizedBox(width: 6),
            Text(
              stage.label,
              style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
            ),
            const SizedBox(width: 6),
            Container(
              constraints: const BoxConstraints(minWidth: 22),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: active ? sw.base : g.surfaceAlt,
                borderRadius: BorderRadius.circular(GhinaRadii.pill),
              ),
              child: Text(
                '${count ?? '–'}',
                key: ValueKey('stage-count-${stage.wire}'),
                textAlign: TextAlign.center,
                style: GhinaType.caption
                    .w(900)
                    .copyWith(color: active ? sw.on : g.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- filters

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.accounts,
    required this.pillars,
    required this.onChanged,
  });

  final ContentFilter filter;
  final List<SocialAccount> accounts;
  final List<ContentPillar> pillars;
  final ValueChanged<ContentFilter> onChanged;

  ContentFilter _with({
    Object? accountId = _keep,
    Object? pillar = _keep,
    Object? format = _keep,
  }) => ContentFilter(
    accountId: identical(accountId, _keep)
        ? filter.accountId
        : accountId as String?,
    pillar: identical(pillar, _keep) ? filter.pillar : pillar as String?,
    format: identical(format, _keep) ? filter.format : format as ContentFormat?,
    search: filter.search,
  );

  @override
  Widget build(BuildContext context) {
    final account = accounts.where((a) => a.id == filter.accountId).firstOrNull;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: GhinaSpace.page),
        children: [
          _FilterChip(
            key: const ValueKey('filter-account'),
            label: account == null ? 'Semua akun' : account.atHandle,
            icon: Icons.person_rounded,
            active: account != null,
            onTap: () async {
              final id = await _pick<String>(
                context,
                title: 'Filter akun',
                options: [
                  for (final a in accounts)
                    (a.id, '${a.platformLabel} · ${a.atHandle}'),
                ],
                selected: filter.accountId,
              );
              if (id != null) {
                onChanged(_with(accountId: id.isEmpty ? null : id));
              }
            },
          ),
          _FilterChip(
            key: const ValueKey('filter-pillar'),
            label: filter.pillar ?? 'Pilar',
            icon: Icons.label_rounded,
            active: filter.pillar != null,
            onTap: () async {
              final p = await _pick<String>(
                context,
                title: 'Filter pilar',
                options: [for (final p in pillars) (p.name, p.name)],
                selected: filter.pillar,
              );
              if (p != null) onChanged(_with(pillar: p.isEmpty ? null : p));
            },
          ),
          _FilterChip(
            key: const ValueKey('filter-format'),
            label: filter.format?.label ?? 'Format',
            icon: Icons.category_rounded,
            active: filter.format != null,
            onTap: () async {
              final f = await _pick<String>(
                context,
                title: 'Filter format',
                options: [
                  for (final f in ContentFormat.values) (f.wire, f.label),
                ],
                selected: filter.format?.wire,
              );
              if (f != null) {
                onChanged(
                  _with(
                    format: f.isEmpty ? null : ContentFormat.tryFromWire(f),
                  ),
                );
              }
            },
          ),
          if (!filter.isEmpty)
            Center(
              child: TextButton.icon(
                key: const ValueKey('filter-clear'),
                onPressed: () => onChanged(ContentFilter.all),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Hapus'),
              ),
            ),
        ],
      ),
    );
  }
}

const _keep = Object();

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Center(
      child: ChunkyChip(
        label: label,
        icon: icon,
        selected: active,
        onTap: onTap,
      ),
    ),
  );
}

/// Single-choice sheet. Returns the value, `''` for "Semua", null = dismissed.
Future<String?> _pick<T>(
  BuildContext context, {
  required String title,
  required List<(String, String)> options,
  String? selected,
}) => showChunkyBottomSheet<String>(
  context,
  title: title,
  showClose: true,
  builder: (c) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (value, label) in [('', 'Semua'), ...options])
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ChunkyTile(
            key: ValueKey('pick-$value'),
            title: label,
            dense: true,
            tinted: (selected ?? '') == value ? GhinaColors.blue : null,
            trailing: (selected ?? '') == value
                ? Icon(Icons.check_circle_rounded, color: GhinaColors.blue.base)
                : null,
            onTap: () => Navigator.of(c).pop(value),
          ),
        ),
    ],
  ),
);

// ---------------------------------------------------------------- metrics due

class _MetricsDueBanner extends StatelessWidget {
  const _MetricsDueBanner({required this.due});
  final List<ContentPostView> due;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final first = due.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        0,
        GhinaSpace.page,
        8,
      ),
      child: ChunkyCard(
        key: const ValueKey('metrics-due'),
        tinted: GhinaColors.purple,
        padding: const EdgeInsets.all(14),
        onTap: () => context.push(contentPostRoute(first.id)),
        child: Row(
          children: [
            Icon(
              Icons.insights_rounded,
              color: GhinaColors.purple.base,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Isi performa?',
                    style: GhinaType.h3.copyWith(color: g.textPrimary),
                  ),
                  Text(
                    due.length == 1
                        ? '"${first.title}" sudah 3 hari tayang.'
                        : '${due.length} posting sudah 3 hari tayang.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: g.textMuted),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- inbox

class _InboxTab extends ConsumerWidget {
  const _InboxTab();

  Future<void> _convert(BuildContext context, WidgetRef ref, Note n) async {
    final pick = await showConvertIdeaSheet(context, title: noteActionTitle(n));
    if (pick == null || !context.mounted) return;
    final r = await ref.read(convertNoteToContentProvider)(
      n.id,
      format: pick.format,
      pillar: pick.pillar,
    );
    if (!context.mounted) return;
    switch (r) {
      case Ok(:final value):
        showOkToast(context, 'Masuk ke papan 💡');
        context.push(contentItemRoute(value.item.id));
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(watchIdeaInboxProvider);
    final g = context.ghina;
    return RefreshIndicator(
      onRefresh: () => pullToSync(context, ref),
      child: inbox.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingListView(hero: false),
        error: (_, _) => ScrollableFill(
          child: ErrorRetry(
            onRetry: () => ref.invalidate(watchIdeaInboxProvider),
          ),
        ),
        data: (notes) => notes.isEmpty
            ? ScrollableFill(
                child: EmptyState(
                  mood: MascotMood.thinking,
                  title: 'Inbox ide kosong',
                  message:
                      'Catatan berlabel "Ide Konten" muncul di sini. Tulis ide kapan saja di Catatan.',
                  actionLabel: 'Buka catatan',
                  onAction: () => context.push('/notes'),
                ),
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  GhinaSpace.page,
                  4,
                  GhinaSpace.page,
                  120,
                ),
                itemCount: notes.length,
                itemBuilder: (context, i) {
                  final n = notes[i];
                  final excerpt = bodyExcerpt(n.body, max: 160);
                  return Padding(
                    key: ValueKey('inbox-${n.id}'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ChunkyCard(
                      onTap: () => context.push(noteRoute(n.id)),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.lightbulb_rounded,
                                color: GhinaColors.orange.base,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  noteActionTitle(n),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GhinaType.h3.copyWith(
                                    color: g.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (excerpt.isNotEmpty &&
                              excerpt != noteActionTitle(n)) ...[
                            const SizedBox(height: 6),
                            Text(
                              excerpt,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: GhinaType.bodyS.copyWith(
                                color: g.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              if (n.hasPhotos)
                                TagChip(
                                  label: '${n.photos.length} foto',
                                  icon: Icons.photo_rounded,
                                ),
                              if (n.hasChecklist) ...[
                                const SizedBox(width: 6),
                                TagChip(
                                  label:
                                      '${n.checklistDone}/${n.checklist.length}',
                                  icon: Icons.checklist_rounded,
                                ),
                              ],
                              const Spacer(),
                              ChunkyButton(
                                key: ValueKey('convert-${n.id}'),
                                label: 'Jadikan konten',
                                size: ChunkyButtonSize.small,
                                color: GhinaColors.orange,
                                expand: false,
                                onPressed: () => _convert(context, ref, n),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
