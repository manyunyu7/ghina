import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/game/game.dart' hide MascotMood;
import '../../../design_system/design_system.dart';
import '../../../state/game/game_providers.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../shared/game_visuals.dart';

/// Colours cycled per unit (banner, nodes, popover).
const _unitColors = [
  GhinaColors.green,
  GhinaColors.blue,
  GhinaColors.purple,
  GhinaColors.orange,
  GhinaColors.pink,
  GhinaColors.red,
];

ChunkySwatch unitColor(int unitIndex) =>
    _unitColors[unitIndex % _unitColors.length];

/// Zigzag horizontal offsets (× amplitude) like the Duolingo path.
const _wave = [0.0, 0.55, 0.95, 0.55, 0.0, -0.55, -0.95, -0.55];

/// "Belajar" tab: the winding lesson path, one colored banner per unit.
class LearnPage extends ConsumerStatefulWidget {
  const LearnPage({super.key});

  @override
  ConsumerState<LearnPage> createState() => _LearnPageState();
}

class _LearnPageState extends ConsumerState<LearnPage> {
  final _currentKey = GlobalKey();
  String? _open;
  bool _scrolled = false;

  void _scrollToCurrent() {
    if (_scrolled) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _currentKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.4,
        duration: GhinaMotion.slow,
        curve: GhinaMotion.standard,
      );
    });
  }

  void _toggle(String id) => setState(() => _open = _open == id ? null : id);

  void _start(LessonProgress l) {
    setState(() => _open = null);
    context.push('/learn/lesson/${l.lesson.id}');
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final path = ref.watch(learnPathProvider);
    return Scaffold(
      backgroundColor: g.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _TopBar(),
            Expanded(
              child: switch (path) {
                AsyncData(:final value) => _buildPath(value),
                AsyncError() => ErrorRetry(
                  onRetry: () => ref.invalidate(gameLocalStateProvider),
                ),
                _ => const _PathSkeleton(),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPath(LearnPathProgress path) {
    if (path.units.isEmpty) {
      return const EmptyState(
        title: 'Materi belum tersedia',
        message: 'Nanti ada pelajaran seru di sini, tunggu ya!',
      );
    }
    if (path.nextLesson != null) _scrollToCurrent();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _open == null ? null : () => setState(() => _open = null),
      child: LayoutBuilder(
        builder: (context, box) => ListView(
          padding: const EdgeInsets.fromLTRB(
            GhinaSpace.page,
            GhinaSpace.sm,
            GhinaSpace.page,
            120,
          ),
          children: [
            for (var u = 0; u < path.units.length; u++)
              ..._unit(path.units[u], u, box.maxWidth - GhinaSpace.page * 2),
            if (path.isCompleted) const _Graduated(),
          ],
        ),
      ),
    );
  }

  List<Widget> _unit(UnitProgress unit, int index, double width) {
    final color = unitColor(index);
    final amp = (width / 2 - 70).clamp(40.0, 96.0);
    final lessons = unit.lessons;
    return [
      if (index > 0) const SizedBox(height: 28),
      _UnitBanner(unit: unit, index: index, color: color),
      const SizedBox(height: 28),
      for (var i = 0; i < lessons.length; i++) ...[
        _nodeRow(
          lessons[i],
          color: color,
          dx: _wave[i % _wave.length] * amp,
          number: i + 1,
          total: lessons.length,
        ),
        if (_open == lessons[i].lesson.id)
          _LessonPopover(
            lesson: lessons[i],
            number: i + 1,
            total: lessons.length,
            color: color,
            dx: _wave[i % _wave.length] * amp,
            onStart: () => _start(lessons[i]),
          ),
        const SizedBox(height: 18),
      ],
      _Trophy(
        done: unit.isCompleted,
        dx: _wave[lessons.length % _wave.length] * amp,
      ),
    ];
  }

  Widget _nodeRow(
    LessonProgress l, {
    required ChunkySwatch color,
    required double dx,
    required int number,
    required int total,
  }) {
    final state = l.isNext
        ? PathNodeState.current
        : l.isCompleted
        ? PathNodeState.completed
        : l.isLocked
        ? PathNodeState.locked
        : PathNodeState.available;
    final node = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PathNode(
          state: state,
          icon: number == 1 ? Icons.star_rounded : _nodeIcon(number),
          color: color,
          progress: 0,
          bubbleLabel: l.isPractice ? 'Ulangi' : 'Mulai',
          onTap: () => _toggle(l.lesson.id),
        ),
        if (l.isCompleted) ...[
          const SizedBox(height: 6),
          _Stars(count: l.stars),
        ],
      ],
    );
    // Locked nodes still open the popover to explain why.
    final tappable = l.isLocked
        ? GestureDetector(
            onTap: () => _toggle(l.lesson.id),
            child: AbsorbPointer(child: node),
          )
        : node;
    final withMascot = Stack(
      clipBehavior: Clip.none,
      children: [
        tappable,
        if (l.isNext)
          Positioned(
            bottom: 0,
            left: dx > 0 ? -104 : null,
            right: dx > 0 ? null : -104,
            child: const IgnorePointer(
              child: MascotView(mood: MascotMood.waving, size: 84),
            ),
          ),
      ],
    );
    return Center(
      key: l.isNext ? _currentKey : ValueKey('node-${l.lesson.id}'),
      child: Transform.translate(offset: Offset(dx, 0), child: withMascot),
    );
  }

  IconData _nodeIcon(int number) => switch (number % 4) {
    0 => Icons.fitness_center_rounded,
    1 => Icons.star_rounded,
    2 => Icons.menu_book_rounded,
    _ => Icons.lightbulb_rounded,
  };
}

// ---------------------------------------------------------------- top bar

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = context.ghina;
    final summary = ref.watch(gameSummaryProvider).value;
    final path = ref.watch(learnPathProvider).value;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        10,
        GhinaSpace.page,
        10,
      ),
      decoration: BoxDecoration(
        color: g.background,
        border: Border(bottom: BorderSide(color: g.border, width: 2)),
      ),
      child: Row(
        children: [
          // Pushed from Beranda/Profil (no longer a tab): offer a way back.
          if (context.canPop()) ...[
            ChunkyIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Kembali',
              onPressed: () => context.pop(),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Belajar', style: GhinaType.h1),
                if (path != null)
                  Text(
                    '${path.completedLessons}/${path.totalLessons} pelajaran selesai',
                    style: GhinaType.caption.copyWith(color: g.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (summary != null) ...[
            StatPill(
              leading: StreakFlame(
                count: summary.streak.current,
                active: summary.streak.current > 0,
                size: 20,
                showCount: false,
                animate: false,
              ),
              value: '${summary.streak.current}',
              color: GhinaColors.orange,
              semanticLabel: 'Streak ${summary.streak.current} hari',
            ),
            const SizedBox(width: 8),
            StatPill(
              icon: Icons.bolt_rounded,
              value: '${summary.totalXp}',
              color: GhinaColors.yellow,
              semanticLabel: '${summary.totalXp} XP',
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- unit banner

class _UnitBanner extends StatelessWidget {
  const _UnitBanner({
    required this.unit,
    required this.index,
    required this.color,
  });

  final UnitProgress unit;
  final int index;
  final ChunkySwatch color;

  @override
  Widget build(BuildContext context) {
    final locked = !unit.isUnlocked;
    final g = context.ghina;
    final sw = locked
        ? ChunkySwatch(
            base: g.disabled,
            edge: g.disabledEdge,
            light: g.surfaceAlt,
            on: g.onDisabled,
          )
        : color;
    return ChunkyCard(
      color: sw,
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UNIT ${index + 1} · ${unit.completedLessons}/${unit.totalLessons}',
                  style: GhinaType.overline.copyWith(
                    color: sw.on.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unit.unit.title,
                  style: GhinaType.h2.w(900).copyWith(color: sw.on),
                ),
                const SizedBox(height: 4),
                Text(
                  unit.unit.description,
                  style: GhinaType.bodyS.copyWith(
                    color: sw.on.withValues(alpha: 0.92),
                  ),
                ),
                const SizedBox(height: 10),
                ChunkyProgressBar(
                  value: unit.fraction,
                  height: 10,
                  color: GhinaColors.yellow,
                  trackColor: sw.edge,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: sw.edge,
              borderRadius: GhinaRadii.rLg,
            ),
            child: Icon(
              unit.isCompleted
                  ? Icons.emoji_events_rounded
                  : locked
                  ? Icons.lock_rounded
                  : gameIcon(unit.unit.icon),
              color: unit.isCompleted ? GhinaColors.yellow.base : sw.on,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- popover

class _LessonPopover extends StatelessWidget {
  const _LessonPopover({
    required this.lesson,
    required this.number,
    required this.total,
    required this.color,
    required this.dx,
    required this.onStart,
  });

  final LessonProgress lesson;
  final int number;
  final int total;
  final ChunkySwatch color;
  final double dx;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final locked = lesson.isLocked;
    final face = locked ? g.surfaceAlt : color.base;
    final fg = locked ? g.textSecondary : color.on;
    final xp = lesson.isPractice ? XpRules.practiceBase : XpRules.lessonBase;
    final button = ChunkySwatch(
      base: Colors.white,
      edge: const Color(0xFFE5E5E5),
      light: Colors.white,
      on: color.base,
    );
    return PopIn(
      fromScale: 0.9,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            // Tail pointing at the node.
            Transform.translate(
              offset: Offset(dx, 1),
              child: Transform.rotate(
                angle: 0.785398,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: face,
                    borderRadius: const BorderRadius.all(Radius.circular(3)),
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -9),
              child: GestureDetector(
                onTap: () {}, // swallow taps so the page doesn't close it
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: face,
                    borderRadius: GhinaRadii.rXl,
                    border: locked
                        ? Border.all(color: g.border, width: 2)
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lesson.lesson.title,
                        style: GhinaType.h3.w(900).copyWith(color: fg),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        locked
                            ? 'Selesaikan pelajaran sebelumnya dulu buat membuka ini ya.'
                            : lesson.isPractice
                            ? 'Latihan lagi biar makin nempel · ${lesson.stars}/${LessonProgress.maxStars} bintang'
                            : '${lesson.lesson.description} · Pelajaran $number dari $total',
                        style: GhinaType.bodyS.copyWith(
                          color: fg.withValues(alpha: 0.92),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ChunkyButton(
                        label: locked
                            ? 'Terkunci'
                            : lesson.isPractice
                            ? 'Latihan +$xp XP'
                            : 'Mulai +$xp XP',
                        icon: locked ? Icons.lock_rounded : null,
                        color: button,
                        onPressed: locked ? null : onStart,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- bits

class _Stars extends StatelessWidget {
  const _Stars({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < LessonProgress.maxStars; i++)
          Icon(
            Icons.star_rounded,
            size: 18,
            color: i < count ? GhinaColors.yellow.base : g.border,
          ),
      ],
    );
  }
}

class _Trophy extends StatelessWidget {
  const _Trophy({required this.done, required this.dx});

  final bool done;
  final double dx;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final face = done ? GhinaColors.yellow.base : g.disabled;
    final edge = done ? GhinaColors.yellow.edge : g.disabledEdge;
    return Center(
      child: Transform.translate(
        offset: Offset(dx, 0),
        child: Semantics(
          label: done ? 'Unit selesai' : 'Piala unit',
          child: Container(
            width: 64,
            height: 60,
            decoration: BoxDecoration(
              color: edge,
              borderRadius: const BorderRadius.all(Radius.elliptical(32, 30)),
            ),
            alignment: Alignment.topCenter,
            child: Container(
              width: 64,
              height: 54,
              decoration: BoxDecoration(
                color: face,
                borderRadius: const BorderRadius.all(Radius.elliptical(32, 27)),
              ),
              child: Icon(
                Icons.emoji_events_rounded,
                color: done ? Colors.white : g.onDisabled,
                size: 30,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Graduated extends StatelessWidget {
  const _Graduated();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 28),
    child: MascotSpeech(
      mood: MascotMood.excited,
      title: 'Kamu tamat semua! 🎓',
      message:
          'Semua pelajaran sudah beres. Ulangi kapan aja buat ngumpulin bintang.',
    ),
  );
}

class _PathSkeleton extends StatelessWidget {
  const _PathSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.all(GhinaSpace.page),
    children: [
      const Skeleton(height: 118, radius: 20),
      const SizedBox(height: 28),
      for (var i = 0; i < 5; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Center(
            child: Transform.translate(
              offset: Offset(_wave[i] * 70, 0),
              child: const Skeleton.circle(size: 70),
            ),
          ),
        ),
    ],
  );
}
