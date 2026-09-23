import '../game_store.dart';
import '../xp_rules.dart';
import 'learn_models.dart';

enum LessonPhase {
  /// Waiting for an answer to [LessonSession.currentQuestion].
  answering,

  /// Answer checked; show [LessonSession.feedback], then call `next()`.
  feedback,

  /// All questions cleared; [LessonSession.result] is available.
  finished,
}

/// One submitted answer.
class AnswerRecord {
  const AnswerRecord({
    required this.questionIndex,
    required this.correct,
    required this.isRetry,
  });
  final int questionIndex;
  final bool correct;

  /// Answered during the "fix your mistakes" round at the end.
  final bool isRetry;
}

/// Feedback for the last answer (green/red bottom sheet).
class LessonFeedback {
  const LessonFeedback({
    required this.correct,
    required this.question,
    required this.willRetry,
  });

  final bool correct;
  final Question question;

  /// Wrong answer that will come back at the end of the lesson.
  final bool willRetry;

  String get explanation => question.explanation;
  String get correctAnswerText => question.correctAnswerText;
}

class LessonResult {
  const LessonResult({
    required this.lessonId,
    required this.practice,
    required this.totalQuestions,
    required this.correctFirstTry,
    required this.mistakes,
    required this.xp,
  });

  final String lessonId;
  final bool practice;
  final int totalQuestions;
  final int correctFirstTry;

  /// Total wrong answers (including wrong retries).
  final int mistakes;
  final int xp;

  bool get perfect => mistakes == 0;

  /// First-try accuracy 0.0 – 1.0.
  double get accuracy =>
      totalQuestions == 0 ? 1 : correctFirstTry / totalQuestions;

  LessonCompletion toCompletion(DateTime at) => LessonCompletion(
    lessonId: lessonId,
    at: at,
    xp: xp,
    accuracy: accuracy,
    perfect: perfect,
    practice: practice,
  );
}

/// Immutable Duolingo-style lesson state machine.
///
/// Questions are asked in order; a wrong answer re-queues the question at the
/// end (at most [maxRetriesPerQuestion] times), so the lesson ends with a
/// "fix your mistakes" round. There is no failing — mistakes only reduce XP.
class LessonSession {
  const LessonSession._({
    required this.lesson,
    required this.practice,
    required this.queue,
    required this.position,
    required this.records,
    required this.phase,
    required this.feedback,
  });

  factory LessonSession.start(Lesson lesson, {bool practice = false}) =>
      LessonSession._(
        lesson: lesson,
        practice: practice,
        queue: [for (var i = 0; i < lesson.questions.length; i++) i],
        position: 0,
        records: const [],
        phase: lesson.questions.isEmpty
            ? LessonPhase.finished
            : LessonPhase.answering,
        feedback: null,
      );

  static const maxRetriesPerQuestion = 2;

  final Lesson lesson;
  final bool practice;

  /// Question indices to ask, retries appended at the end.
  final List<int> queue;

  /// Index into [queue].
  final int position;
  final List<AnswerRecord> records;
  final LessonPhase phase;
  final LessonFeedback? feedback;

  int get totalQuestions => lesson.questions.length;

  int get currentQuestionIndex =>
      queue[position < queue.length ? position : queue.length - 1];
  Question get currentQuestion => lesson.questions[currentQuestionIndex];

  /// True while answering the end-of-lesson mistakes round.
  bool get isRetry => position >= totalQuestions;

  int get mistakes => records.where((r) => !r.correct).length;

  /// Questions answered correctly at least once.
  Set<int> get cleared => {
    for (final r in records)
      if (r.correct) r.questionIndex,
  };

  /// Progress bar 0.0 – 1.0 (cleared questions / total, Duolingo-style).
  double get progress {
    if (phase == LessonPhase.finished) return 1;
    final done = {
      ...cleared,
      // Questions that ran out of retries count as done too.
      for (final i in _exhausted) i,
    };
    return totalQuestions == 0 ? 1 : done.length / totalQuestions;
  }

  Iterable<int> get _exhausted sync* {
    for (var i = 0; i < totalQuestions; i++) {
      final wrong = records
          .where((r) => r.questionIndex == i && !r.correct)
          .length;
      if (wrong > maxRetriesPerQuestion) yield i;
    }
  }

  /// Check [answer] for the current question.
  LessonSession submit(QuestionAnswer answer) {
    if (phase != LessonPhase.answering) {
      throw StateError('submit() called in phase $phase');
    }
    final qi = currentQuestionIndex;
    final question = lesson.questions[qi];
    final correct = question.check(answer);
    final record = AnswerRecord(
      questionIndex: qi,
      correct: correct,
      isRetry: isRetry,
    );
    var newQueue = queue;
    var willRetry = false;
    if (!correct) {
      final wrongSoFar = records
          .where((r) => r.questionIndex == qi && !r.correct)
          .length;
      if (wrongSoFar < maxRetriesPerQuestion) {
        newQueue = [...queue, qi];
        willRetry = true;
      }
    }
    return LessonSession._(
      lesson: lesson,
      practice: practice,
      queue: newQueue,
      position: position,
      records: [...records, record],
      phase: LessonPhase.feedback,
      feedback: LessonFeedback(
        correct: correct,
        question: question,
        willRetry: willRetry,
      ),
    );
  }

  /// Move on after feedback. Finishes when the queue is exhausted.
  LessonSession next() {
    if (phase != LessonPhase.feedback) {
      throw StateError('next() called in phase $phase');
    }
    final nextPos = position + 1;
    return LessonSession._(
      lesson: lesson,
      practice: practice,
      queue: queue,
      position: nextPos,
      records: records,
      phase: nextPos >= queue.length
          ? LessonPhase.finished
          : LessonPhase.answering,
      feedback: null,
    );
  }

  bool get isFinished => phase == LessonPhase.finished;

  /// Available once [isFinished].
  LessonResult? get result {
    if (!isFinished) return null;
    final firstTry = <int, bool>{};
    for (final r in records) {
      firstTry.putIfAbsent(r.questionIndex, () => r.correct);
    }
    final m = mistakes;
    return LessonResult(
      lessonId: lesson.id,
      practice: practice,
      totalQuestions: totalQuestions,
      correctFirstTry: firstTry.values.where((c) => c).length,
      mistakes: m,
      xp: XpRules.lessonXp(mistakes: m, practice: practice),
    );
  }
}
