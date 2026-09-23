/// Data model for the Duolingo-style learning path.
///
/// All content is `const` Dart data (see `content/`), so it works offline.
/// Questions carry no ids: a question is addressed by its index inside its
/// lesson. Lesson ids are stable strings (e.g. `u1l2`) because lesson progress
/// is persisted by id.
library;

/// A unit = a themed group of lessons (one "section" of the path).
class LearnUnit {
  const LearnUnit({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.lessons,
  });

  /// Stable id, e.g. `u1`.
  final String id;
  final String title;
  final String description;

  /// Material icon name hint for the UI (e.g. `savings`, `shield`).
  final String icon;
  final List<Lesson> lessons;
}

class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.description,
    required this.questions,
    this.tip,
  });

  /// Stable id, e.g. `u1l2`. Persisted in lesson progress — never rename.
  final String id;
  final String title;
  final String description;

  /// Optional short "tips" card shown before the lesson starts.
  final String? tip;
  final List<Question> questions;
}

enum QuestionType {
  multipleChoice,
  trueFalse,
  fillBlank,
  matchPairs,
  orderSteps,
  numeric,
}

/// Base class of all question kinds. [explanation] is shown after answering.
sealed class Question {
  const Question({required this.prompt, required this.explanation});

  final String prompt;
  final String explanation;

  QuestionType get type;

  /// Whether [answer] is correct. Answers of the wrong kind are incorrect.
  bool check(QuestionAnswer answer);

  /// Human-readable correct answer (for the "Jawaban benar: ..." banner).
  String get correctAnswerText;
}

/// Pick one of [options].
class MultipleChoiceQuestion extends Question {
  const MultipleChoiceQuestion({
    required super.prompt,
    required this.options,
    required this.correctIndex,
    required super.explanation,
  });

  final List<String> options;
  final int correctIndex;

  @override
  QuestionType get type => QuestionType.multipleChoice;

  @override
  bool check(QuestionAnswer answer) =>
      answer is ChoiceAnswer && answer.index == correctIndex;

  @override
  String get correctAnswerText => options[correctIndex];
}

/// "Benar atau salah?" — [prompt] is the statement.
class TrueFalseQuestion extends Question {
  const TrueFalseQuestion({
    required super.prompt,
    required this.answer,
    required super.explanation,
  });

  final bool answer;

  @override
  QuestionType get type => QuestionType.trueFalse;

  @override
  bool check(QuestionAnswer answer) =>
      answer is BoolAnswer && answer.value == this.answer;

  @override
  String get correctAnswerText => answer ? 'Benar' : 'Salah';
}

/// A sentence with exactly one blank marker [blank] (`___`) and word options.
class FillBlankQuestion extends Question {
  const FillBlankQuestion({
    required super.prompt,
    required this.options,
    required this.correctIndex,
    required super.explanation,
  });

  static const blank = '___';

  final List<String> options;
  final int correctIndex;

  @override
  QuestionType get type => QuestionType.fillBlank;

  @override
  bool check(QuestionAnswer answer) =>
      answer is ChoiceAnswer && answer.index == correctIndex;

  @override
  String get correctAnswerText =>
      prompt.replaceFirst(blank, options[correctIndex]);
}

class MatchPair {
  const MatchPair(this.left, this.right);
  final String left;
  final String right;
}

/// Match every left item to its right item. The UI shuffles the right column;
/// the answer maps left index -> right index (indices into [pairs]).
class MatchPairsQuestion extends Question {
  const MatchPairsQuestion({
    required super.prompt,
    required this.pairs,
    required super.explanation,
  });

  final List<MatchPair> pairs;

  @override
  QuestionType get type => QuestionType.matchPairs;

  @override
  bool check(QuestionAnswer answer) {
    if (answer is! PairsAnswer) return false;
    if (answer.mapping.length != pairs.length) return false;
    for (var i = 0; i < pairs.length; i++) {
      final j = answer.mapping[i];
      if (j == null) return false;
      // Accept a right item with identical text (duplicates are allowed to be swapped).
      if (j < 0 || j >= pairs.length || pairs[j].right != pairs[i].right) {
        return false;
      }
    }
    return true;
  }

  @override
  String get correctAnswerText =>
      pairs.map((p) => '${p.left} → ${p.right}').join('\n');
}

/// Put [steps] in the right order. [steps] is stored in the CORRECT order; the
/// UI shuffles it. The answer lists original indices in the order chosen.
class OrderStepsQuestion extends Question {
  const OrderStepsQuestion({
    required super.prompt,
    required this.steps,
    required super.explanation,
  });

  final List<String> steps;

  @override
  QuestionType get type => QuestionType.orderSteps;

  @override
  bool check(QuestionAnswer answer) {
    if (answer is! OrderAnswer) return false;
    if (answer.order.length != steps.length) return false;
    for (var i = 0; i < steps.length; i++) {
      // Compare by text so identical steps can't make a correct answer wrong.
      final j = answer.order[i];
      if (j < 0 || j >= steps.length || steps[j] != steps[i]) return false;
    }
    return true;
  }

  @override
  String get correctAnswerText => [
    for (var i = 0; i < steps.length; i++) '${i + 1}. ${steps[i]}',
  ].join('\n');
}

/// Simple calculation with a numeric answer.
class NumericQuestion extends Question {
  const NumericQuestion({
    required super.prompt,
    required this.answer,
    required super.explanation,
    this.tolerance = 0,
    this.prefix,
    this.suffix,
  });

  final num answer;

  /// Absolute tolerance accepted (e.g. 0.5 for rounding).
  final num tolerance;

  /// Displayed before the input, e.g. `Rp`.
  final String? prefix;

  /// Displayed after the input, e.g. `%` or `bulan`.
  final String? suffix;

  @override
  QuestionType get type => QuestionType.numeric;

  @override
  bool check(QuestionAnswer answer) =>
      answer is NumericAnswer &&
      (answer.value - this.answer).abs() <= tolerance;

  @override
  String get correctAnswerText {
    final v = answer == answer.roundToDouble()
        ? _thousands(answer.round())
        : answer.toString();
    return [?prefix, v, ?suffix].join(' ');
  }

  static String _thousands(int v) {
    final s = v.abs().toString();
    final b = StringBuffer(v < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// A user's answer to a question.
sealed class QuestionAnswer {
  const QuestionAnswer();
}

/// For [MultipleChoiceQuestion] and [FillBlankQuestion].
class ChoiceAnswer extends QuestionAnswer {
  const ChoiceAnswer(this.index);
  final int index;
}

/// For [TrueFalseQuestion].
class BoolAnswer extends QuestionAnswer {
  const BoolAnswer(this.value);
  final bool value;
}

/// For [MatchPairsQuestion]: left index -> right index.
class PairsAnswer extends QuestionAnswer {
  const PairsAnswer(this.mapping);
  final Map<int, int> mapping;
}

/// For [OrderStepsQuestion]: original step indices in the chosen order.
class OrderAnswer extends QuestionAnswer {
  const OrderAnswer(this.order);
  final List<int> order;
}

/// For [NumericQuestion].
class NumericAnswer extends QuestionAnswer {
  const NumericAnswer(this.value);
  final num value;
}
