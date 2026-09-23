import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/game/game.dart';

/// Returns a list of problems with [q] (empty = well-formed).
List<String> validateQuestion(Question q) {
  final problems = <String>[];
  if (q.prompt.trim().isEmpty) problems.add('empty prompt');
  if (q.explanation.trim().length < 10) problems.add('explanation too short');

  void checkOptions(List<String> options, int correct) {
    if (options.length < 2 || options.length > 5) {
      problems.add('needs 2-5 options');
    }
    if (options.toSet().length != options.length) {
      problems.add('duplicate options');
    }
    if (options.any((o) => o.trim().isEmpty)) problems.add('empty option');
    if (correct < 0 || correct >= options.length) {
      problems.add('correctIndex out of range');
    }
  }

  switch (q) {
    case MultipleChoiceQuestion(:final options, :final correctIndex):
      checkOptions(options, correctIndex);
    case FillBlankQuestion(:final options, :final correctIndex):
      checkOptions(options, correctIndex);
      if (FillBlankQuestion.blank.allMatches(q.prompt).length != 1) {
        problems.add('fill-blank needs exactly one ___');
      }
    case TrueFalseQuestion(:final answer):
      if (!q.check(BoolAnswer(answer)) || q.check(BoolAnswer(!answer))) {
        problems.add('true/false check broken');
      }
    case MatchPairsQuestion(:final pairs):
      if (pairs.length < 2 || pairs.length > 5) problems.add('needs 2-5 pairs');
      if (pairs.map((p) => p.left).toSet().length != pairs.length) {
        problems.add('duplicate left');
      }
      if (pairs.map((p) => p.right).toSet().length != pairs.length) {
        problems.add('duplicate right');
      }
      if (!q.check(
        PairsAnswer({for (var i = 0; i < pairs.length; i++) i: i}),
      )) {
        problems.add('identity mapping rejected');
      }
      if (pairs.length >= 2 &&
          q.check(
            PairsAnswer({
              0: 1,
              1: 0,
              for (var i = 2; i < pairs.length; i++) i: i,
            }),
          )) {
        problems.add('swapped mapping accepted');
      }
    case OrderStepsQuestion(:final steps):
      if (steps.length < 3 || steps.length > 6) problems.add('needs 3-6 steps');
      if (steps.toSet().length != steps.length) problems.add('duplicate steps');
      if (!q.check(OrderAnswer([for (var i = 0; i < steps.length; i++) i]))) {
        problems.add('correct order rejected');
      }
      if (q.check(
        OrderAnswer([for (var i = steps.length - 1; i >= 0; i--) i]),
      )) {
        problems.add('reversed order accepted');
      }
    case NumericQuestion(:final answer, :final tolerance):
      if (tolerance < 0) problems.add('negative tolerance');
      if (!q.check(NumericAnswer(answer))) problems.add('answer rejected');
      if (q.check(NumericAnswer(answer + tolerance + 1))) {
        problems.add('wrong answer accepted');
      }
  }
  if (problems.isEmpty && q.correctAnswerText.trim().isEmpty) {
    problems.add('empty correctAnswerText');
  }
  return problems;
}

void main() {
  final lessons = [for (final u in learnUnits) ...u.lessons];

  test('path shape: 6 units x 4-5 lessons x 5-8 questions', () {
    expect(learnUnits.length, 6);
    for (final u in learnUnits) {
      expect(u.lessons.length, inInclusiveRange(4, 5), reason: u.id);
      for (final l in u.lessons) {
        expect(l.questions.length, inInclusiveRange(5, 8), reason: l.id);
      }
    }
  });

  test('ids are unique and follow uXlY', () {
    final unitIds = learnUnits.map((u) => u.id).toList();
    expect(unitIds.toSet().length, unitIds.length);
    final ids = lessons.map((l) => l.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final u in learnUnits) {
      for (var i = 0; i < u.lessons.length; i++) {
        expect(u.lessons[i].id, '${u.id}l${i + 1}');
      }
    }
  });

  test('titles and descriptions are present', () {
    for (final u in learnUnits) {
      expect(u.title.trim(), isNotEmpty);
      expect(u.description.trim(), isNotEmpty);
      expect(u.icon.trim(), isNotEmpty);
      for (final l in u.lessons) {
        expect(l.title.trim(), isNotEmpty, reason: l.id);
        expect(l.description.trim(), isNotEmpty, reason: l.id);
      }
    }
  });

  test('every question is well-formed with a valid answer', () {
    final problems = <String>[];
    for (final l in lessons) {
      for (var i = 0; i < l.questions.length; i++) {
        for (final p in validateQuestion(l.questions[i])) {
          problems.add('${l.id} q${i + 1}: $p');
        }
      }
    }
    expect(problems, isEmpty);
  });

  test('every unit uses every question type', () {
    for (final u in learnUnits) {
      final types = {
        for (final l in u.lessons)
          for (final q in l.questions) q.type,
      };
      expect(types, QuestionType.values.toSet(), reason: u.id);
    }
  });

  test('no duplicate prompts within a lesson', () {
    for (final l in lessons) {
      final prompts = l.questions.map((q) => q.prompt).toList();
      expect(prompts.toSet().length, prompts.length, reason: l.id);
    }
  });

  test('correct option position is varied across the path', () {
    final positions = <int>{
      for (final l in lessons)
        for (final q in l.questions)
          if (q case MultipleChoiceQuestion(:final correctIndex)) correctIndex,
    };
    expect(positions.length, greaterThanOrEqualTo(3));
  });

  test('validator catches malformed questions', () {
    expect(
      validateQuestion(
        const MultipleChoiceQuestion(
          prompt: 'x',
          options: ['a', 'a'],
          correctIndex: 3,
          explanation: 'penjelasan panjang',
        ),
      ),
      isNotEmpty,
    );
    expect(
      validateQuestion(
        const FillBlankQuestion(
          prompt: 'tanpa blank',
          options: ['a', 'b'],
          correctIndex: 0,
          explanation: 'penjelasan panjang',
        ),
      ),
      contains('fill-blank needs exactly one ___'),
    );
  });
}
