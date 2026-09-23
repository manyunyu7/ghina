import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/game/game.dart';

const lesson = Lesson(
  id: 't1',
  title: 'Tes',
  description: 'Tes',
  questions: [
    MultipleChoiceQuestion(
      prompt: 'Q0',
      options: ['a', 'b', 'c'],
      correctIndex: 1,
      explanation: 'karena b',
    ),
    TrueFalseQuestion(prompt: 'Q1', answer: true, explanation: 'benar dong'),
    NumericQuestion(
      prompt: 'Q2',
      answer: 100,
      tolerance: 0.5,
      explanation: 'seratus',
    ),
    MatchPairsQuestion(
      prompt: 'Q3',
      pairs: [MatchPair('x', '1'), MatchPair('y', '2'), MatchPair('z', '3')],
      explanation: 'cocok',
    ),
    OrderStepsQuestion(
      prompt: 'Q4',
      steps: ['s1', 's2', 's3'],
      explanation: 'urut',
    ),
  ],
);

const right = <QuestionAnswer>[
  ChoiceAnswer(1),
  BoolAnswer(true),
  NumericAnswer(100),
  PairsAnswer({0: 0, 1: 1, 2: 2}),
  OrderAnswer([0, 1, 2]),
];
const wrong = <QuestionAnswer>[
  ChoiceAnswer(0),
  BoolAnswer(false),
  NumericAnswer(99),
  PairsAnswer({0: 1, 1: 0, 2: 2}),
  OrderAnswer([1, 0, 2]),
];

LessonSession answer(LessonSession s, bool correct) {
  final a = correct
      ? right[s.currentQuestionIndex]
      : wrong[s.currentQuestionIndex];
  return s.submit(a).next();
}

void main() {
  group('Question checks', () {
    test('right answers pass, wrong fail, wrong kinds fail', () {
      for (var i = 0; i < lesson.questions.length; i++) {
        expect(lesson.questions[i].check(right[i]), isTrue, reason: 'q$i');
        expect(lesson.questions[i].check(wrong[i]), isFalse, reason: 'q$i');
        expect(lesson.questions[i].check(const ChoiceAnswer(99)), isFalse);
      }
    });

    test('numeric tolerance and formatting', () {
      const q = NumericQuestion(
        prompt: 'p',
        answer: 1500000,
        explanation: 'e',
        prefix: 'Rp',
      );
      expect(q.check(const NumericAnswer(1500000)), isTrue);
      expect(q.check(const NumericAnswer(1500001)), isFalse);
      expect(q.correctAnswerText, 'Rp 1.500.000');
      expect(lesson.questions[2].check(const NumericAnswer(100.4)), isTrue);
    });

    test('match pairs with an incomplete mapping fail', () {
      expect(
        lesson.questions[3].check(const PairsAnswer({0: 0, 1: 1})),
        isFalse,
      );
    });

    test('fill blank answer text', () {
      const q = FillBlankQuestion(
        prompt: 'Simpan ___ dulu',
        options: ['uang', 'utang'],
        correctIndex: 0,
        explanation: 'e',
      );
      expect(q.correctAnswerText, 'Simpan uang dulu');
    });
  });

  group('LessonSession', () {
    test('perfect run', () {
      var s = LessonSession.start(lesson);
      expect(s.phase, LessonPhase.answering);
      for (var i = 0; i < 5; i++) {
        s = s.submit(right[s.currentQuestionIndex]);
        expect(s.phase, LessonPhase.feedback);
        expect(s.feedback!.correct, isTrue);
        s = s.next();
      }
      expect(s.isFinished, isTrue);
      final r = s.result!;
      expect(r.perfect, isTrue);
      expect(r.accuracy, 1);
      expect(r.xp, XpRules.lessonBase + XpRules.lessonPerfectBonus);
      expect(s.progress, 1);
    });

    test('mistakes are retried at the end', () {
      var s = LessonSession.start(lesson);
      s = s.submit(wrong[0]);
      expect(s.feedback!.correct, isFalse);
      expect(s.feedback!.willRetry, isTrue);
      expect(s.feedback!.correctAnswerText, 'b');
      expect(s.feedback!.explanation, 'karena b');
      s = s.next();
      for (var i = 0; i < 4; i++) {
        s = answer(s, true);
      }
      expect(s.isFinished, isFalse);
      expect(s.isRetry, isTrue);
      expect(s.currentQuestionIndex, 0);
      s = answer(s, true);
      expect(s.isFinished, isTrue);
      final r = s.result!;
      expect(r.mistakes, 1);
      expect(r.correctFirstTry, 4);
      expect(r.accuracy, closeTo(0.8, 1e-9));
      expect(r.perfect, isFalse);
      expect(r.xp, XpRules.lessonBase - XpRules.lessonMistakePenalty);
    });

    test('retries are capped so the lesson always ends (no failing)', () {
      var s = LessonSession.start(lesson);
      var steps = 0;
      while (!s.isFinished) {
        s = answer(s, false);
        steps++;
        expect(steps, lessThan(100));
      }
      // 5 questions × (1 + maxRetries) attempts.
      expect(steps, 5 * (1 + LessonSession.maxRetriesPerQuestion));
      final r = s.result!;
      expect(r.accuracy, 0);
      expect(r.xp, XpRules.lessonMinimum);
    });

    test('progress bar grows only on cleared questions', () {
      var s = LessonSession.start(lesson);
      expect(s.progress, 0);
      s = answer(s, false);
      expect(s.progress, 0);
      s = answer(s, true);
      expect(s.progress, closeTo(0.2, 1e-9));
    });

    test('invalid transitions throw', () {
      final s = LessonSession.start(lesson);
      expect(s.next, throwsStateError);
      final f = s.submit(right[0]);
      expect(() => f.submit(right[1]), throwsStateError);
      expect(s.result, isNull);
    });

    test('practice sessions earn practice XP', () {
      var s = LessonSession.start(lesson, practice: true);
      while (!s.isFinished) {
        s = answer(s, true);
      }
      expect(s.result!.xp, XpRules.practiceBase + XpRules.practicePerfectBonus);
      expect(s.result!.practice, isTrue);
    });
  });

  group('Learn path', () {
    LessonCompletion done(
      String id, {
      bool perfect = false,
      double acc = 0.8,
    }) => LessonCompletion(
      lessonId: id,
      at: DateTime(2026, 9, 10),
      xp: 15,
      accuracy: acc,
      perfect: perfect,
      practice: false,
    );

    test('fresh path: only the first lesson is available', () {
      final p = LearnPathCalculator.compute(learnUnits, const []);
      expect(p.nextLesson!.lesson.id, 'u1l1');
      expect(p.allLessons.where((l) => l.canStart).length, 1);
      expect(p.units.first.isUnlocked, isTrue);
      expect(p.units[1].isUnlocked, isFalse);
      expect(p.completedLessons, 0);
    });

    test('sequential unlock across units, stars and practice', () {
      final u1 = learnUnits.first.lessons.map((l) => l.id).toList();
      final p = LearnPathCalculator.compute(learnUnits, [
        for (final id in u1) done(id),
        done(u1.first, perfect: true, acc: 1),
        done(u1.first),
        done(u1.first),
      ]);
      expect(p.units.first.isCompleted, isTrue);
      expect(p.completedUnits, 1);
      expect(p.units[1].isUnlocked, isTrue);
      expect(p.nextLesson!.lesson.id, 'u2l1');
      final first = p.lessonById(u1.first)!;
      expect(first.stars, LessonProgress.maxStars);
      expect(first.perfect, isTrue);
      expect(first.bestAccuracy, 1);
      expect(first.isPractice, isTrue);
      expect(p.lessonById('u2l2')!.isLocked, isTrue);
    });

    test('everything done', () {
      final p = LearnPathCalculator.compute(learnUnits, [
        for (final u in learnUnits)
          for (final l in u.lessons) done(l.id),
      ]);
      expect(p.isCompleted, isTrue);
      expect(p.nextLesson, isNull);
      expect(p.fraction, 1);
    });

    test('findLesson', () {
      final f = findLesson('u2l3')!;
      expect(f.unit.id, 'u2');
      expect(f.lessonIndex, 2);
      expect(findLesson('nope'), isNull);
    });
  });
}
