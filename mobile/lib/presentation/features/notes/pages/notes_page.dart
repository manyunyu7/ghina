import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/platform/platform_state.dart';
import '../../../state/session_controller.dart';
import '../note_draft.dart';
import '../widgets/color_palette.dart';
import '../widgets/note_card.dart';
import '../widgets/voice_recorder_sheet.dart';

/// Grid (masonry) or list — kept for the app session.
final notesGridProvider = NotifierProvider<_GridMode, bool>(_GridMode.new);

class _GridMode extends Notifier<bool> {
  @override
  bool build() => true;
  void toggle() => state = !state;
}

const _allTab = '__all__';
const _archiveTab = '__archive__';

/// Catatan: label tabs (Semua · pinned labels · Arsip), grid/list of note
/// cards (pinned first), debounced search, "+ Catatan" FAB (long-press =
/// start "Rekam suara" right away).
class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

  static const searchDebounce = Duration(milliseconds: 300);

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  String _query = '';
  bool _searching = false;
  String _tab = _allTab;

  @override
  void initState() {
    super.initState();
    // Offline fallback: seeds "Ide Konten" only if no notes-aware pull yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final uid = ref.read(currentUserProvider)?.id;
      if (uid != null) unawaited(ref.read(seedDefaultNoteLabelProvider)(uid));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(NotesPage.searchDebounce, () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _search.clear();
        _query = '';
      }
    });
    if (_searching) _searchFocus.requestFocus();
  }

  NoteFilter _filter(List<NoteLabel> tabs) {
    final q = _query.isEmpty ? null : _query;
    if (_tab == _archiveTab) return NoteFilter(archived: true, search: q);
    if (_tab != _allTab && tabs.any((l) => l.id == _tab)) {
      return NoteFilter.label(_tab, search: q);
    }
    // "Semua": searching looks everywhere (archive included).
    return q == null ? NoteFilter.all : NoteFilter(search: q, archived: null);
  }

  String? get _tabLabelId =>
      _tab == _allTab || _tab == _archiveTab ? null : _tab;

  void _newNote({bool checklist = false}) => context.push(
    '/notes/new',
    extra: NoteDraft(labelIds: [?_tabLabelId], checklist: checklist),
  );

  Future<void> _voiceNote() async {
    final rec = await showVoiceRecorderSheet(context, autoStart: true);
    if (rec == null || !mounted) return;
    final secs = math
        .max(1, (rec.duration.inMilliseconds / 1000).round())
        .clamp(1, audioDurationMax);
    final r = await ref.read(createNoteProvider)(
      NoteInput(
        labelIds: [?_tabLabelId],
        audio: [NoteAudio.local(rec.path, durationSec: secs)],
        source: NoteSource.voice,
      ),
    );
    if (!mounted) return;
    switch (r) {
      case Ok(:final value):
        // The note keeps its own copy; drop the recorder's file.
        unawaited(ref.read(voiceRecorderProvider).deleteFile(rec.path));
        showOkToast(context, 'Rekaman tersimpan 🎙️', icon: Icons.mic_rounded);
        context.push(noteRoute(value.id));
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  Future<void> _quickActions(Note n) async {
    final action = await showChunkyBottomSheet<String>(
      context,
      title: n.displayTitle.isEmpty ? 'Catatan' : n.displayTitle,
      showClose: true,
      builder: (c) {
        Widget row(String v, IconData icon, String text, {bool red = false}) =>
            ChunkyTile(
              key: ValueKey('qa-$v'),
              framed: false,
              leading: Icon(
                icon,
                color: red ? GhinaColors.red.base : c.ghina.textSecondary,
              ),
              title: text,
              onTap: () => Navigator.of(c).pop(v),
            );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row(
              'pin',
              n.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
              n.pinned ? 'Lepas sematan' : 'Sematkan',
            ),
            row('color', Icons.palette_outlined, 'Ganti warna'),
            row(
              'archive',
              n.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
              n.archived ? 'Keluarkan dari arsip' : 'Arsipkan',
            ),
            row('delete', Icons.delete_outline_rounded, 'Hapus', red: true),
          ],
        );
      },
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'pin':
        await ref.read(setNotePinnedProvider)(n.id, !n.pinned);
      case 'color':
        await showNoteColorSheet(
          context,
          selected: n.color,
          onChanged: (c) => ref.read(setNoteColorProvider)(n.id, c),
        );
      case 'archive':
        await ref.read(setNoteArchivedProvider)(n.id, !n.archived);
        if (mounted) {
          showToastBadge(
            context,
            message: n.archived ? 'Dikeluarkan dari arsip' : 'Diarsipkan 📦',
            icon: Icons.archive_rounded,
            color: GhinaColors.blue,
          );
        }
      case 'delete':
        final ok = await showChunkyConfirm(
          context,
          title: 'Hapus catatan ini?',
          message: 'Hilang permanen. Mau disimpan? Pakai Arsipkan.',
          confirmLabel: 'Hapus',
          destructive: true,
        );
        if (ok) await ref.read(deleteNoteProvider)(n.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final tabs = ref.watch(watchNoteTabsProvider).value ?? const <NoteLabel>[];
    if (_tab != _allTab && _tab != _archiveTab && tabs.isNotEmpty) {
      if (!tabs.any((l) => l.id == _tab)) _tab = _allTab;
    }
    final filter = _filter(tabs);
    final notes = ref.watch(watchNotesProvider(filter));
    final grid = ref.watch(notesGridProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => popOr(context, '/home')),
        title: _searching
            ? TextField(
                key: const ValueKey('notes-search'),
                controller: _search,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                onChanged: _onSearch,
                style: GhinaType.bodyL.w(700).copyWith(color: g.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Cari catatan…',
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintStyle: GhinaType.bodyL.copyWith(color: g.textMuted),
                ),
              )
            : const Text('Catatan'),
        actions: [
          IconButton(
            key: const ValueKey('notes-search-toggle'),
            tooltip: _searching ? 'Tutup pencarian' : 'Cari',
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: _toggleSearch,
          ),
          IconButton(
            key: const ValueKey('notes-layout'),
            tooltip: grid ? 'Tampilan daftar' : 'Tampilan grid',
            icon: Icon(
              grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
            ),
            onPressed: () => ref.read(notesGridProvider.notifier).toggle(),
          ),
          IconButton(
            key: const ValueKey('notes-labels'),
            tooltip: 'Kelola label',
            icon: const Icon(Icons.label_outline_rounded),
            onPressed: () => context.push('/notes/labels'),
          ),
        ],
      ),
      floatingActionButton: _NotesFab(
        onTap: _newNote,
        onLongPress: _voiceNote,
        onChecklist: () => _newNote(checklist: true),
      ),
      body: Column(
        children: [
          _TabsRow(
            tabs: tabs,
            selected: _tab,
            onSelect: (t) => setState(() => _tab = t),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => pullToSync(context, ref),
              child: switch (notes) {
                AsyncData(:final value) => _content(value, tabs, grid),
                AsyncError() => ScrollableFill(
                  child: ErrorRetry(
                    onRetry: () => ref.invalidate(watchNotesProvider(filter)),
                  ),
                ),
                _ => const LoadingListView(hero: false),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(List<NoteView> notes, List<NoteLabel> tabs, bool grid) {
    if (notes.isEmpty) return ScrollableFill(child: _empty(tabs));
    final pinned = [
      for (final v in notes)
        if (v.note.pinned) v,
    ];
    final others = [
      for (final v in notes)
        if (!v.note.pinned) v,
    ];
    final showHeaders = pinned.isNotEmpty && others.isNotEmpty;
    final searchAll = _query.isNotEmpty && _tab == _allTab;

    Widget section(List<NoteView> items) => grid
        ? _Masonry(
            items: items,
            builder: (v) => _card(v, compact: false, searchAll: searchAll),
          )
        : Column(
            children: [
              for (final v in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _card(v, compact: true, searchAll: searchAll),
                ),
            ],
          );

    return ListView(
      key: const ValueKey('notes-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
      children: [
        if (_query.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              '${notes.length} catatan cocok dengan "$_query"',
              style: GhinaType.bodyS
                  .w(800)
                  .copyWith(color: context.ghina.textSecondary),
            ),
          ),
        if (showHeaders) const _Header('Disematkan'),
        if (pinned.isNotEmpty) section(pinned),
        if (showHeaders) const _Header('Lainnya'),
        if (others.isNotEmpty) section(others),
      ],
    );
  }

  Widget _card(NoteView v, {required bool compact, required bool searchAll}) =>
      NoteCard(
        view: v,
        compact: compact,
        showArchived: searchAll,
        onTap: () => context.push(noteRoute(v.id)),
        onLongPress: () => _quickActions(v.note),
      );

  Widget _empty(List<NoteLabel> tabs) {
    if (_query.isNotEmpty) {
      return EmptyState(
        title: 'Nggak ketemu',
        message: 'Belum ada catatan berisi "$_query". Coba kata lain, ya.',
        mood: MascotMood.thinking,
        actionLabel: 'Hapus pencarian',
        onAction: _toggleSearch,
      );
    }
    if (_tab == _archiveTab) {
      return const EmptyState(
        title: 'Arsip masih kosong',
        message: 'Catatan yang diarsipkan disimpan di sini, rapi dan aman.',
        mood: MascotMood.sleeping,
      );
    }
    final label = tabs.where((l) => l.id == _tab).firstOrNull;
    return EmptyState(
      title: label != null
          ? 'Belum ada catatan ${label.name}'
          : 'Belum ada catatan',
      message: label != null
          ? 'Catatan baru dari tab ini otomatis dapat label ${label.name}.'
          : 'Ide, daftar belanja, rekaman suara — tulis yang pertama, yuk!',
      mood: MascotMood.waving,
      actionLabel: 'Tulis catatan',
      onAction: _newNote,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: GhinaType.overline
          .w(900)
          .copyWith(color: context.ghina.textSecondary),
    ),
  );
}

/// Two balanced columns (shorter column gets the next card).
class _Masonry extends StatelessWidget {
  const _Masonry({required this.items, required this.builder});
  final List<NoteView> items;
  final Widget Function(NoteView v) builder;

  @override
  Widget build(BuildContext context) {
    final cols = [<NoteView>[], <NoteView>[]];
    final h = [0, 0];
    for (final v in items) {
      final i = h[0] <= h[1] ? 0 : 1;
      cols[i].add(v);
      h[i] += noteCardWeight(v.note);
    }
    Widget col(List<NoteView> xs) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final v in xs)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: builder(v),
          ),
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: col(cols[0])),
        const SizedBox(width: 10),
        Expanded(child: col(cols[1])),
      ],
    );
  }
}

class _TabsRow extends StatelessWidget {
  const _TabsRow({
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<NoteLabel> tabs;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget chip(String id, String label, {IconData? icon, ChunkySwatch? c}) =>
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChunkyChip(
            key: ValueKey('notes-tab-$id'),
            label: label,
            icon: icon,
            color: c ?? GhinaColors.green,
            selected: selected == id,
            onTap: () => onSelect(id),
          ),
        );
    return SizedBox(
      height: 20 + MediaQuery.textScalerOf(context).scale(36),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 8),
        children: [
          chip(_allTab, 'Semua', icon: Icons.notes_rounded),
          for (final l in tabs)
            chip(l.id, l.name, c: CategoryColors.swatch(l.color)),
          chip(
            _archiveTab,
            'Arsip',
            icon: Icons.archive_outlined,
            c: GhinaColors.gray,
          ),
        ],
      ),
    );
  }
}

/// "+ Catatan": tap = new note with the keyboard up; long-press = record a
/// voice note right away. A small checklist shortcut sits above it.
class _NotesFab extends StatelessWidget {
  const _NotesFab({
    required this.onTap,
    required this.onLongPress,
    required this.onChecklist,
  });

  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onChecklist;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ChunkySurface(
          key: const ValueKey('notes-fab-checklist'),
          color: g.surface,
          edgeColor: g.borderEdge,
          borderColor: g.border,
          depth: GhinaDepth.sm,
          borderRadius: GhinaRadii.rLg,
          padding: const EdgeInsets.all(10),
          onTap: onChecklist,
          semanticLabel: 'Checklist baru',
          child: Icon(
            Icons.checklist_rounded,
            color: GhinaColors.green.base,
            size: 24,
          ),
        ),
        const SizedBox(height: 10),
        Tooltip(
          message: 'Tahan untuk rekam suara',
          child: ChunkySurface(
            key: const ValueKey('notes-fab'),
            color: GhinaColors.green.base,
            edgeColor: GhinaColors.green.edge,
            depth: GhinaDepth.md,
            borderRadius: GhinaRadii.rLg,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            onTap: onTap,
            onLongPress: onLongPress,
            semanticLabel: 'Catatan baru. Tahan untuk rekam suara',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                const SizedBox(width: 6),
                Text(
                  'CATATAN',
                  style: GhinaType.button.copyWith(color: Colors.white),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 2,
                  height: 18,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.mic_rounded, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
