import '../game_store.dart';
import 'learn_models.dart';

enum LessonStatus { locked, available, completed }

class LessonProgress {
  const LessonProgress({
    required this.lesson,
    required this.unitId,
    required this.status,
    required this.completions,
    required this.bestAccuracy,
    required this.perfect,
    required this.isNext,
  });

  final Lesson lesson;
  final String unitId;
  final LessonStatus status;

  /// Number of finished sessions (first run + practice replays).
  final int completions;

  /// Best first-try accuracy 0.0 – 1.0 (0 if never completed).
  final double bestAccuracy;

  /// Ever finished without a mistake.
  final bool perfect;

  /// The lesson the path should highlight ("MULAI").
  final bool isNext;

  static const maxStars = 3;

  /// Crowns/stars 0–3: one per completion (practice to fill them up).
  int get stars => completions > maxStars ? maxStars : completions;

  bool get isCompleted => status == LessonStatus.completed;
  bool get isLocked => status == LessonStatus.locked;
  bool get canStart => status != LessonStatus.locked;

  /// Starting a completed lesson again is a practice session.
  bool get isPractice => isCompleted;
}

class UnitProgress {
  const UnitProgress({required this.unit, required this.lessons});

  final LearnUnit unit;
  final List<LessonProgress> lessons;

  int get completedLessons => lessons.where((l) => l.isCompleted).length;
  int get totalLessons => lessons.length;
  bool get isUnlocked => lessons.isNotEmpty && !lessons.first.isLocked;
  bool get isCompleted =>
      lessons.isNotEmpty && completedLessons == totalLessons;
  double get fraction =>
      totalLessons == 0 ? 0 : completedLessons / totalLessons;
}

class LearnPathProgress {
  const LearnPathProgress({required this.units});

  final List<UnitProgress> units;

  Iterable<LessonProgress> get allLessons => units.expand((u) => u.lessons);
  int get totalLessons => allLessons.length;
  int get completedLessons => allLessons.where((l) => l.isCompleted).length;
  int get completedUnits => units.where((u) => u.isCompleted).length;
  bool get isCompleted => totalLessons > 0 && completedLessons == totalLessons;
  double get fraction =>
      totalLessons == 0 ? 0 : completedLessons / totalLessons;

  /// Next lesson to take (null when everything is done).
  LessonProgress? get nextLesson {
    for (final l in allLessons) {
      if (l.isNext) return l;
    }
    return null;
  }

  LessonProgress? lessonById(String id) {
    for (final l in allLessons) {
      if (l.lesson.id == id) return l;
    }
    return null;
  }
}

/// Builds path progress: lessons unlock strictly in order (across units).
abstract final class LearnPathCalculator {
  static LearnPathProgress compute(
    List<LearnUnit> units,
    Iterable<LessonCompletion> completions,
  ) {
    final count = <String, int>{};
    final best = <String, double>{};
    final perfect = <String>{};
    for (final c in completions) {
      count[c.lessonId] = (count[c.lessonId] ?? 0) + 1;
      if (c.accuracy > (best[c.lessonId] ?? 0)) best[c.lessonId] = c.accuracy;
      if (c.perfect) perfect.add(c.lessonId);
    }

    var previousDone = true;
    var nextAssigned = false;
    final result = <UnitProgress>[];
    for (final unit in units) {
      final lessons = <LessonProgress>[];
      for (final lesson in unit.lessons) {
        final done = (count[lesson.id] ?? 0) > 0;
        final status = done
            ? LessonStatus.completed
            : previousDone
            ? LessonStatus.available
            : LessonStatus.locked;
        final isNext = status == LessonStatus.available && !nextAssigned;
        if (isNext) nextAssigned = true;
        lessons.add(
          LessonProgress(
            lesson: lesson,
            unitId: unit.id,
            status: status,
            completions: count[lesson.id] ?? 0,
            bestAccuracy: best[lesson.id] ?? 0,
            perfect: perfect.contains(lesson.id),
            isNext: isNext,
          ),
        );
        previousDone = done;
      }
      result.add(UnitProgress(unit: unit, lessons: lessons));
    }
    return LearnPathProgress(units: result);
  }
}
