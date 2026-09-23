import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/game/game.dart' hide MascotMood;
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/game/game_providers.dart';
import '../../../shared/rewards/rewards.dart';
import '../widgets/question_views.dart';

/// Lesson player: tip intro → questions (with a "fix your mistakes" round at
/// the end) → result celebration → back to the path.
class LessonPage extends ConsumerStatefulWidget {
  const LessonPage({super.key, required this.lessonId});

  final String lessonId;

  @override
  ConsumerState<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends ConsumerState<LessonPage> {
  bool _introDone = false;
  QuestionAnswer? _answer;
  bool _busy = false;
  bool? _unitWasDone;

  LessonSessionController get _controller =>
      ref.read(lessonSessionProvider(widget.lessonId).notifier);

  /// Remembers whether the lesson's unit was already complete before this
  /// session, to celebrate finishing a unit.
  void _rememberUnit(LessonSession s) {
    if (_unitWasDone != null || s.records.isNotEmpty) return;
    final path = ref.read(learnPathProvider).value;
    final l = path?.lessonById(widget.lessonId);
    if (path == null || l == null) return;
    _unitWasDone = path.units
        .firstWhere((u) => u.unit.id == l.unitId)
        .isCompleted;
  }

  Future<void> _quit(LessonSession s) async {
    if (s.records.isEmpty || s.isFinished) {
      if (mounted) context.pop();
      return;
    }
    final ok = await showChunkyConfirm(
      context,
      title: 'Yakin mau berhenti?',
      message: 'Progres pelajaran ini bakal hilang. Tinggal sedikit lagi lho!',
      confirmLabel: 'Keluar',
      cancelLabel: 'Lanjut belajar',
      destructive: true,
    );
    if (ok && mounted) context.pop();
  }

  void _check() {
    final a = _answer;
    if (a == null) return;
    final fb = _controller.submit(a);
    if (fb.correct) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    setState(() {});
  }

  Future<void> _continue() async {
    if (_busy) return;
    setState(() => _busy = true);
    final rewards = RewardTracker.start(ref);
    final result = await _controller.next();
    if (!mounted) return;
    setState(() {
      _answer = null;
      _busy = result != null;
    });
    if (result != null) await _finish(result, rewards);
  }

  Future<void> _finish(LessonResult result, RewardTracker rewards) async {
    final pct = (result.accuracy * 100).round();
    await showCelebration(
      context,
      title: result.perfect ? 'Sempurna!' : 'Pelajaran selesai!',
      subtitle: result.practice
          ? 'Latihan beres. Ingatanmu makin kuat 💪'
          : result.perfect
          ? 'Tanpa salah sama sekali. Keren banget!'
          : 'Mantap! Kesalahan tadi juga sudah kamu perbaiki.',
      xp: result.xp,
      stats: [
        CelebrationStat(
          label: 'Akurasi',
          value: '$pct%',
          icon: Icons.track_changes_rounded,
          color: pct >= 80 ? GhinaColors.green : GhinaColors.blue,
        ),
        if (result.perfect)
          const CelebrationStat(
            label: 'Bonus',
            value: 'Sempurna',
            icon: Icons.stars_rounded,
            color: GhinaColors.purple,
          ),
      ],
    );
    if (!mounted) return;

    // Unit finished just now?
    try {
      final path = await ref.read(learnPathProvider.future);
      final l = path.lessonById(widget.lessonId);
      if (l != null && _unitWasDone == false && mounted) {
        final i = path.units.indexWhere((u) => u.unit.id == l.unitId);
        final unit = path.units[i];
        if (unit.isCompleted) {
          await showCelebration(
            context,
            title: 'Unit ${i + 1} tamat! 🏆',
            subtitle:
                'Kamu menuntaskan "${unit.unit.title}". Lanjut ke unit berikutnya, yuk!',
            stats: [
              CelebrationStat(
                label: 'Pelajaran',
                value: '${unit.totalLessons}/${unit.totalLessons}',
                icon: Icons.emoji_events_rounded,
                color: GhinaColors.yellow,
              ),
            ],
          );
        }
      }
    } catch (_) {
      // Path unavailable: skip the unit celebration.
    }
    if (!mounted) return;
    await rewards.finish(context);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final found = findLesson(widget.lessonId, ref.watch(learnUnitsProvider));
    if (found == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          title: 'Pelajaran nggak ketemu',
          message:
              'Mungkin materinya sudah diperbarui. Balik ke jalur belajar, yuk.',
          mood: MascotMood.thinking,
          actionLabel: 'Kembali',
          onAction: () => context.pop(),
        ),
      );
    }
    // The session starts once saved progress is loaded (see
    // lessonSessionProvider), so replays of finished lessons are practice.
    final LessonSession s;
    switch (ref.watch(lessonSessionProvider(widget.lessonId))) {
      case AsyncData(:final value):
        s = value;
      case AsyncError():
        return Scaffold(
          appBar: AppBar(),
          body: ErrorRetry(
            onRetry: () =>
                ref.invalidate(lessonSessionProvider(widget.lessonId)),
          ),
        );
      default:
        return Scaffold(
          backgroundColor: g.background,
          body: const Center(
            child: MascotView(mood: MascotMood.thinking, size: 110),
          ),
        );
    }
    ref.watch(learnPathProvider);
    _rememberUnit(s);
    final lesson = s.lesson;
    final showIntro = !_introDone && lesson.tip != null && s.records.isEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _quit(s);
      },
      child: Scaffold(
        backgroundColor: g.background,
        body: SafeArea(
          bottom: false,
          child: showIntro
              ? _Intro(
                  lesson: lesson,
                  practice: s.practice,
                  onClose: () => _quit(s),
                  onStart: () => setState(() => _introDone = true),
                )
              : _player(s),
        ),
      ),
    );
  }

  Widget _player(LessonSession s) {
    final g = context.ghina;
    final fb = s.feedback;
    final q = s.currentQuestion;
    final combo = _combo(s);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, GhinaSpace.page, 4),
          child: Row(
            children: [
              ChunkyIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Tutup',
                onPressed: () => _quit(s),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChunkyProgressBar(
                  key: const ValueKey('lesson-progress'),
                  value: s.progress,
                  height: 18,
                ),
              ),
              if (s.practice) ...[
                const SizedBox(width: 10),
                const ChunkyPill(
                  label: 'Latihan',
                  color: GhinaColors.purple,
                  soft: true,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              12,
              GhinaSpace.page,
              24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (s.isRetry)
                      const ChunkyPill(
                        label: 'Perbaiki kesalahan',
                        icon: Icons.replay_rounded,
                        color: GhinaColors.orange,
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            questionKindIcon(q),
                            size: 18,
                            color: GhinaColors.purple.base,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              questionKindLabel(q).toUpperCase(),
                              style: GhinaType.overline.copyWith(
                                color: GhinaColors.purple.base,
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (combo >= 3)
                      PopIn(
                        child: ChunkyPill(
                          label: '$combo benar beruntun!',
                          icon: Icons.local_fire_department_rounded,
                          color: GhinaColors.orange,
                          soft: true,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                KeyedSubtree(
                  key: ValueKey('q-${s.position}'),
                  child: QuestionView(
                    question: q,
                    feedback: fb,
                    seed: Object.hash(lessonIdHash, s.position),
                    onChanged: (a) => setState(() => _answer = a),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (fb != null)
          AnswerFeedbackBar(
            key: ValueKey('fb-${s.position}'),
            correct: fb.correct,
            title: fb.correct ? _praise(s.position) : null,
            message: _feedbackMessage(fb),
            onContinue: _continue,
          )
        else
          Container(
            padding: EdgeInsets.fromLTRB(
              GhinaSpace.page,
              12,
              GhinaSpace.page,
              12 + MediaQuery.paddingOf(context).bottom,
            ),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: g.border, width: 2)),
            ),
            child: ChunkyButton(
              label: 'Cek',
              onPressed: _answer == null ? null : _check,
            ),
          ),
      ],
    );
  }

  int get lessonIdHash => widget.lessonId.hashCode;

  static const _praises = [
    'Mantap, benar!',
    'Keren!',
    'Tepat sekali!',
    'Hebat!',
    'Pinter!',
  ];

  String _praise(int position) => _praises[position % _praises.length];

  String _feedbackMessage(LessonFeedback fb) {
    final q = fb.question;
    final buf = StringBuffer();
    if (!fb.correct) {
      // Choice tiles and pairs/steps reveal the answer visually already.
      final short = q is FillBlankQuestion || q is NumericQuestion;
      if (short) buf.writeln('Jawaban benar: ${fb.correctAnswerText}');
    }
    buf.write(fb.explanation);
    if (fb.willRetry) buf.write('\nSoal ini bakal muncul lagi nanti.');
    return buf.toString();
  }

  /// Consecutive correct answers ending at the latest one.
  int _combo(LessonSession s) {
    var n = 0;
    for (final r in s.records.reversed) {
      if (!r.correct) break;
      n++;
    }
    return n;
  }
}

class _Intro extends StatelessWidget {
  const _Intro({
    required this.lesson,
    required this.practice,
    required this.onClose,
    required this.onStart,
  });

  final Lesson lesson;
  final bool practice;
  final VoidCallback onClose;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final xp = practice ? XpRules.practiceBase : XpRules.lessonBase;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ChunkyIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Tutup',
              onPressed: onClose,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(GhinaSpace.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  practice ? 'LATIHAN' : 'PELAJARAN BARU',
                  style: GhinaType.overline.copyWith(
                    color: GhinaColors.purple.base,
                  ),
                ),
                const SizedBox(height: 4),
                Text(lesson.title, style: GhinaType.h1),
                const SizedBox(height: 6),
                Text(
                  lesson.description,
                  style: GhinaType.body.copyWith(color: g.textSecondary),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatPill(
                      icon: Icons.help_rounded,
                      value: '${lesson.questions.length} soal',
                      color: GhinaColors.blue,
                    ),
                    StatPill(
                      icon: Icons.bolt_rounded,
                      value: '+$xp XP',
                      color: GhinaColors.yellow,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                PopIn(
                  child: MascotSpeech(
                    title: 'Tips dulu, yuk!',
                    message: lesson.tip!,
                    mood: MascotMood.thinking,
                    mascotSize: 120,
                    bubbleColor: GhinaColors.blue,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            GhinaSpace.page,
            8,
            GhinaSpace.page,
            12 + MediaQuery.paddingOf(context).bottom,
          ),
          child: ChunkyButton(label: 'Mulai belajar', onPressed: onStart),
        ),
      ],
    );
  }
}
