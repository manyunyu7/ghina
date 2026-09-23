/// One interactive widget per lesson question type. Each reports the current
/// (complete) answer through [onChanged] — `null` while incomplete — and shows
/// the correct/wrong reveal once [feedback] is set.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/game/game.dart' hide MascotMood;
import '../../../design_system/design_system.dart';

typedef AnswerChanged = void Function(QuestionAnswer? answer);

/// Human label shown above the prompt.
String questionKindLabel(Question q) => switch (q) {
  MultipleChoiceQuestion() => 'Pilih jawaban yang benar',
  TrueFalseQuestion() => 'Benar atau salah?',
  FillBlankQuestion() => 'Lengkapi kalimatnya',
  MatchPairsQuestion() => 'Pasangkan yang cocok',
  OrderStepsQuestion() => 'Urutkan langkahnya',
  NumericQuestion() => 'Hitung jawabannya',
};

IconData questionKindIcon(Question q) => switch (q) {
  MultipleChoiceQuestion() => Icons.quiz_rounded,
  TrueFalseQuestion() => Icons.rule_rounded,
  FillBlankQuestion() => Icons.edit_rounded,
  MatchPairsQuestion() => Icons.link_rounded,
  OrderStepsQuestion() => Icons.format_list_numbered_rounded,
  NumericQuestion() => Icons.calculate_rounded,
};

/// Deterministic shuffle of `0..n-1` (never the identity when n > 1).
List<int> shuffledIndices(int n, int seed) {
  final list = [for (var i = 0; i < n; i++) i]..shuffle(math.Random(seed));
  var identity = n > 1;
  for (var i = 0; i < n && identity; i++) {
    if (list[i] != i) identity = false;
  }
  if (identity) list.add(list.removeAt(0));
  return list;
}

/// Picks the right widget for [question].
class QuestionView extends StatelessWidget {
  const QuestionView({
    super.key,
    required this.question,
    required this.onChanged,
    required this.seed,
    this.feedback,
  });

  final Question question;
  final AnswerChanged onChanged;
  final LessonFeedback? feedback;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final q = question;
    return switch (q) {
      MultipleChoiceQuestion() => _ChoiceView(
        prompt: q.prompt,
        options: q.options,
        correctIndex: q.correctIndex,
        feedback: feedback,
        onChanged: onChanged,
      ),
      TrueFalseQuestion() => _TrueFalseView(
        question: q,
        feedback: feedback,
        onChanged: onChanged,
      ),
      FillBlankQuestion() => _FillBlankView(
        question: q,
        feedback: feedback,
        onChanged: onChanged,
      ),
      MatchPairsQuestion() => _MatchPairsView(
        question: q,
        feedback: feedback,
        onChanged: onChanged,
        seed: seed,
      ),
      OrderStepsQuestion() => _OrderStepsView(
        question: q,
        feedback: feedback,
        onChanged: onChanged,
        seed: seed,
      ),
      NumericQuestion() => _NumericView(
        question: q,
        feedback: feedback,
        onChanged: onChanged,
      ),
    };
  }
}

/// The mascot "asks" the prompt in a speech bubble.
class _Prompt extends StatelessWidget {
  const _Prompt(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      MascotSpeech(message: text, mood: MascotMood.thinking, mascotSize: 76);
}

// ---------------------------------------------------------------- choice

class _ChoiceView extends StatefulWidget {
  const _ChoiceView({
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.feedback,
    required this.onChanged,
  });

  final String prompt;
  final List<String> options;
  final int correctIndex;
  final LessonFeedback? feedback;
  final AnswerChanged onChanged;

  @override
  State<_ChoiceView> createState() => _ChoiceViewState();
}

class _ChoiceViewState extends State<_ChoiceView> {
  int? _selected;

  QuizOptionState _stateOf(int i) {
    if (widget.feedback == null) {
      return i == _selected ? QuizOptionState.selected : QuizOptionState.idle;
    }
    if (i == widget.correctIndex) return QuizOptionState.correct;
    if (i == _selected) return QuizOptionState.wrong;
    return QuizOptionState.disabled;
  }

  @override
  Widget build(BuildContext context) {
    final revealed = widget.feedback != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Prompt(widget.prompt),
        const SizedBox(height: 18),
        for (var i = 0; i < widget.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: QuizOptionTile(
              label: widget.options[i],
              index: i + 1,
              state: _stateOf(i),
              onTap: revealed
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      setState(() => _selected = i);
                      widget.onChanged(ChoiceAnswer(i));
                    },
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- true/false

class _TrueFalseView extends StatefulWidget {
  const _TrueFalseView({
    required this.question,
    required this.feedback,
    required this.onChanged,
  });

  final TrueFalseQuestion question;
  final LessonFeedback? feedback;
  final AnswerChanged onChanged;

  @override
  State<_TrueFalseView> createState() => _TrueFalseViewState();
}

class _TrueFalseViewState extends State<_TrueFalseView> {
  bool? _selected;

  QuizOptionState _stateOf(bool v) {
    if (widget.feedback == null) {
      return v == _selected ? QuizOptionState.selected : QuizOptionState.idle;
    }
    if (v == widget.question.answer) return QuizOptionState.correct;
    if (v == _selected) return QuizOptionState.wrong;
    return QuizOptionState.disabled;
  }

  Widget _tile(bool v) => QuizOptionTile(
    label: v ? 'Benar' : 'Salah',
    icon: v ? Icons.thumb_up_alt_rounded : Icons.thumb_down_alt_rounded,
    state: _stateOf(v),
    onTap: widget.feedback != null
        ? null
        : () {
            HapticFeedback.selectionClick();
            setState(() => _selected = v);
            widget.onChanged(BoolAnswer(v));
          },
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Prompt(widget.question.prompt),
      const SizedBox(height: 18),
      _tile(true),
      const SizedBox(height: 12),
      _tile(false),
    ],
  );
}

// ---------------------------------------------------------------- fill blank

class _FillBlankView extends StatefulWidget {
  const _FillBlankView({
    required this.question,
    required this.feedback,
    required this.onChanged,
  });

  final FillBlankQuestion question;
  final LessonFeedback? feedback;
  final AnswerChanged onChanged;

  @override
  State<_FillBlankView> createState() => _FillBlankViewState();
}

class _FillBlankViewState extends State<_FillBlankView> {
  int? _selected;

  void _pick(int? i) {
    if (widget.feedback != null) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = i);
    widget.onChanged(i == null ? null : ChoiceAnswer(i));
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final q = widget.question;
    final parts = q.prompt.split(FillBlankQuestion.blank);
    final before = parts.first;
    final after = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final revealed = widget.feedback != null;
    final ChunkySwatch blankColor = !revealed
        ? GhinaColors.blue
        : widget.feedback!.correct
        ? GhinaColors.green
        : GhinaColors.red;
    final sentenceStyle = GhinaType.h3
        .w(800)
        .copyWith(color: g.textPrimary, height: 1.9);

    final blank = GestureDetector(
      onTap: _selected == null ? null : () => _pick(null),
      child: AnimatedContainer(
        duration: GhinaMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        constraints: const BoxConstraints(minWidth: 90),
        decoration: BoxDecoration(
          color: _selected == null
              ? g.surfaceAlt
              : blankColor.tint(g.brightness),
          borderRadius: GhinaRadii.rMd,
          border: Border.all(
            color: _selected == null
                ? g.border
                : blankColor.tintBorder(g.brightness),
            width: 2,
          ),
        ),
        child: Text(
          _selected == null ? ' ' : q.options[_selected!],
          textAlign: TextAlign.center,
          style: GhinaType.h3
              .w(900)
              .copyWith(
                color: _selected == null
                    ? g.textMuted
                    : (g.isDark ? blankColor.base : blankColor.edge),
              ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const MascotView(mood: MascotMood.thinking, size: 64),
            const SizedBox(width: 10),
            Expanded(
              child: ChunkyCard(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Text.rich(
                  TextSpan(
                    style: sentenceStyle,
                    children: [
                      TextSpan(text: before),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: blank,
                      ),
                      TextSpan(text: after),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 12,
          children: [
            for (var i = 0; i < q.options.length; i++)
              _WordTile(
                label: q.options[i],
                used: _selected == i,
                onTap: revealed || _selected == i ? null : () => _pick(i),
              ),
          ],
        ),
      ],
    );
  }
}

/// A tappable word/phrase chip; [used] leaves an empty placeholder.
class _WordTile extends StatelessWidget {
  const _WordTile({required this.label, required this.used, this.onTap});

  final String label;
  final bool used;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final text = Text(
      label,
      style: GhinaType.bodyL
          .w(800)
          .copyWith(color: used ? Colors.transparent : g.textPrimary),
    );
    if (used) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: g.surfaceAlt,
          borderRadius: GhinaRadii.rLg,
        ),
        child: text,
      );
    }
    return ChunkySurface(
      color: g.surface,
      edgeColor: g.borderEdge,
      borderColor: g.border,
      depth: GhinaDepth.md,
      borderRadius: GhinaRadii.rLg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onTap: onTap,
      enabled: onTap != null,
      semanticLabel: label,
      child: text,
    );
  }
}

// ---------------------------------------------------------------- match pairs

const _pairColors = [
  GhinaColors.blue,
  GhinaColors.purple,
  GhinaColors.orange,
  GhinaColors.pink,
  GhinaColors.lime,
  GhinaColors.yellow,
];

class _MatchPairsView extends StatefulWidget {
  const _MatchPairsView({
    required this.question,
    required this.feedback,
    required this.onChanged,
    required this.seed,
  });

  final MatchPairsQuestion question;
  final LessonFeedback? feedback;
  final AnswerChanged onChanged;
  final int seed;

  @override
  State<_MatchPairsView> createState() => _MatchPairsViewState();
}

class _MatchPairsViewState extends State<_MatchPairsView> {
  late final List<int> _rightOrder = shuffledIndices(
    widget.question.pairs.length,
    widget.seed,
  );

  /// left index -> right (original) index.
  final Map<int, int> _pairs = {};

  /// Order in which pairs were made (for stable colours).
  final List<int> _pairOrder = [];
  int? _left;
  int? _right;

  int get _n => widget.question.pairs.length;

  void _emit() => widget.onChanged(
    _pairs.length == _n ? PairsAnswer(Map.of(_pairs)) : null,
  );

  void _unpairLeft(int l) {
    _pairs.remove(l);
    _pairOrder.remove(l);
  }

  void _tryPair() {
    if (_left != null && _right != null) {
      _pairs[_left!] = _right!;
      _pairOrder.add(_left!);
      _left = null;
      _right = null;
      HapticFeedback.lightImpact();
    }
  }

  void _tapLeft(int l) {
    setState(() {
      if (_pairs.containsKey(l)) {
        _unpairLeft(l);
      } else {
        _left = _left == l ? null : l;
        _tryPair();
      }
    });
    _emit();
  }

  void _tapRight(int r) {
    setState(() {
      final owner = _pairs.entries.where((e) => e.value == r).firstOrNull;
      if (owner != null) {
        _unpairLeft(owner.key);
      } else {
        _right = _right == r ? null : r;
        _tryPair();
      }
    });
    _emit();
  }

  bool _isCorrect(int l) {
    final r = _pairs[l];
    return r != null &&
        widget.question.pairs[r].right == widget.question.pairs[l].right;
  }

  ChunkySwatch? _leftColor(int l) {
    if (widget.feedback != null) {
      return _isCorrect(l) ? GhinaColors.green : GhinaColors.red;
    }
    if (_pairs.containsKey(l)) {
      return _pairColors[_pairOrder.indexOf(l) % _pairColors.length];
    }
    return l == _left ? GhinaColors.blue : null;
  }

  ChunkySwatch? _rightColor(int r) {
    final owner = _pairs.entries.where((e) => e.value == r).firstOrNull;
    if (widget.feedback != null) {
      if (owner == null) return null;
      return _isCorrect(owner.key) ? GhinaColors.green : GhinaColors.red;
    }
    if (owner != null) {
      return _pairColors[_pairOrder.indexOf(owner.key) % _pairColors.length];
    }
    return r == _right ? GhinaColors.blue : null;
  }

  int? _badge(int l) =>
      _pairs.containsKey(l) ? _pairOrder.indexOf(l) + 1 : null;

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final revealed = widget.feedback != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Prompt(q.prompt),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  for (var l = 0; l < _n; l++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MatchTile(
                        key: ValueKey('left-$l'),
                        label: q.pairs[l].left,
                        color: _leftColor(l),
                        badge: _badge(l),
                        onTap: revealed ? null : () => _tapLeft(l),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                children: [
                  for (final r in _rightOrder)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MatchTile(
                        key: ValueKey('right-$r'),
                        label: q.pairs[r].right,
                        color: _rightColor(r),
                        badge: () {
                          final owner = _pairs.entries
                              .where((e) => e.value == r)
                              .firstOrNull;
                          return owner == null ? null : _badge(owner.key);
                        }(),
                        onTap: revealed ? null : () => _tapRight(r),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (revealed && !widget.feedback!.correct) ...[
          const SizedBox(height: 8),
          _CorrectAnswerCard(
            lines: [for (final p in q.pairs) '${p.left} → ${p.right}'],
          ),
        ],
      ],
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({
    super.key,
    required this.label,
    this.color,
    this.badge,
    this.onTap,
  });

  final String label;
  final ChunkySwatch? color;
  final int? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final b = g.brightness;
    final sw = color;
    final fg = sw == null ? g.textPrimary : (g.isDark ? sw.base : sw.edge);
    return ChunkySurface(
      color: sw?.tint(b) ?? g.surface,
      edgeColor: sw?.tintBorder(b) ?? g.borderEdge,
      borderColor: sw?.tintBorder(b) ?? g.border,
      depth: GhinaDepth.md,
      borderRadius: GhinaRadii.rLg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      onTap: onTap,
      semanticLabel: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GhinaType.body.w(800).copyWith(color: fg),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sw?.base ?? g.border,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$badge',
                  style: GhinaType.caption
                      .w(900)
                      .copyWith(color: sw?.on ?? g.textPrimary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CorrectAnswerCard extends StatelessWidget {
  const _CorrectAnswerCard({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      tinted: GhinaColors.green,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'JAWABAN YANG BENAR',
            style: GhinaType.overline.copyWith(
              color: g.isDark ? GhinaColors.green.base : GhinaColors.green.edge,
            ),
          ),
          const SizedBox(height: 6),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(l, style: GhinaType.body.w(700)),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- order steps

class _OrderStepsView extends StatefulWidget {
  const _OrderStepsView({
    required this.question,
    required this.feedback,
    required this.onChanged,
    required this.seed,
  });

  final OrderStepsQuestion question;
  final LessonFeedback? feedback;
  final AnswerChanged onChanged;
  final int seed;

  @override
  State<_OrderStepsView> createState() => _OrderStepsViewState();
}

class _OrderStepsViewState extends State<_OrderStepsView> {
  late final List<int> _bank = shuffledIndices(
    widget.question.steps.length,
    widget.seed,
  );
  final List<int> _chosen = [];

  int get _n => widget.question.steps.length;

  void _toggle(int i) {
    if (widget.feedback != null) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (!_chosen.remove(i)) _chosen.add(i);
    });
    widget.onChanged(
      _chosen.length == _n ? OrderAnswer(List.of(_chosen)) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final q = widget.question;
    final revealed = widget.feedback != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Prompt(q.prompt),
        const SizedBox(height: 16),
        Text(
          'URUTANMU · ${_chosen.length}/$_n',
          style: GhinaType.overline.copyWith(color: g.textMuted),
        ),
        const SizedBox(height: 8),
        for (var k = 0; k < _chosen.length; k++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PopIn(
              key: ValueKey('chosen-${_chosen[k]}'),
              fromScale: 0.9,
              child: _StepTile(
                number: k + 1,
                label: q.steps[_chosen[k]],
                color: !revealed
                    ? GhinaColors.blue
                    : q.steps[_chosen[k]] == q.steps[k]
                    ? GhinaColors.green
                    : GhinaColors.red,
                onTap: revealed ? null : () => _toggle(_chosen[k]),
              ),
            ),
          ),
        if (_chosen.length < _n) _EmptySlot(number: _chosen.length + 1),
        const SizedBox(height: 10),
        if (!revealed) ...[
          Text(
            'KETUK UNTUK MENYUSUN',
            style: GhinaType.overline.copyWith(color: g.textMuted),
          ),
          const SizedBox(height: 8),
          for (final i in _bank)
            if (!_chosen.contains(i))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _StepTile(
                  key: ValueKey('bank-$i'),
                  label: q.steps[i],
                  onTap: () => _toggle(i),
                ),
              ),
        ] else if (!widget.feedback!.correct)
          _CorrectAnswerCard(
            lines: [for (var i = 0; i < _n; i++) '${i + 1}. ${q.steps[i]}'],
          ),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    super.key,
    required this.label,
    this.number,
    this.color,
    this.onTap,
  });

  final String label;
  final int? number;
  final ChunkySwatch? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final b = g.brightness;
    final sw = color;
    final fg = sw == null ? g.textPrimary : (g.isDark ? sw.base : sw.edge);
    return ChunkySurface(
      color: sw?.tint(b) ?? g.surface,
      edgeColor: sw?.tintBorder(b) ?? g.borderEdge,
      borderColor: sw?.tintBorder(b) ?? g.border,
      depth: GhinaDepth.md,
      borderRadius: GhinaRadii.rLg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      semanticLabel: label,
      child: Row(
        children: [
          if (number != null) ...[
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sw?.base ?? g.border,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$number',
                style: GhinaType.caption.w(900).copyWith(color: sw?.on),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              style: GhinaType.body.w(800).copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: g.surfaceAlt,
        borderRadius: GhinaRadii.rLg,
        border: Border.all(color: g.border, width: 2),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        number == 1 ? 'Ketuk langkah pertama di bawah' : 'Langkah ke-$number…',
        style: GhinaType.body.w(800).copyWith(color: g.textMuted),
      ),
    );
  }
}

// ---------------------------------------------------------------- numeric

class _NumericView extends StatefulWidget {
  const _NumericView({
    required this.question,
    required this.feedback,
    required this.onChanged,
  });

  final NumericQuestion question;
  final LessonFeedback? feedback;
  final AnswerChanged onChanged;

  @override
  State<_NumericView> createState() => _NumericViewState();
}

class _NumericViewState extends State<_NumericView> {
  String _raw = '';

  static const _maxDigits = 12;

  num? get _value {
    if (_raw.isEmpty || _raw == ',') return null;
    return num.tryParse(_raw.replaceAll(',', '.'));
  }

  void _key(String k) {
    if (widget.feedback != null) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (k == '⌫') {
        if (_raw.isNotEmpty) _raw = _raw.substring(0, _raw.length - 1);
      } else if (k == ',') {
        if (!_raw.contains(',')) _raw = _raw.isEmpty ? '0,' : '$_raw,';
      } else {
        final digits = _raw.replaceAll(',', '').length;
        if (digits >= _maxDigits) return;
        final decimals = _raw.contains(',') ? _raw.split(',')[1].length : 0;
        if (decimals >= 2) return;
        _raw = _raw == '0' ? k : '$_raw$k';
      }
    });
    final v = _value;
    widget.onChanged(v == null ? null : NumericAnswer(v));
  }

  String get _display {
    if (_raw.isEmpty) return '0';
    final parts = _raw.split(',');
    final intPart = parts[0].isEmpty ? '0' : parts[0];
    final grouped = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) grouped.write('.');
      grouped.write(intPart[i]);
    }
    return parts.length > 1 ? '$grouped,${parts[1]}' : grouped.toString();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final q = widget.question;
    final fb = widget.feedback;
    final ChunkySwatch? sw = fb == null
        ? (_raw.isEmpty ? null : GhinaColors.blue)
        : fb.correct
        ? GhinaColors.green
        : GhinaColors.red;
    final fg = sw == null ? g.textMuted : (g.isDark ? sw.base : sw.edge);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Prompt(q.prompt),
        const SizedBox(height: 16),
        Shake(
          trigger: fb != null && !fb.correct ? fb : null,
          child: AnimatedContainer(
            duration: GhinaMotion.fast,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: sw?.tint(g.brightness) ?? g.surfaceAlt,
              borderRadius: GhinaRadii.rXl,
              border: Border.all(
                color: sw?.tintBorder(g.brightness) ?? g.border,
                width: 2,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (q.prefix != null) ...[
                    Text(
                      q.prefix!,
                      style: GhinaType.moneyM.w(800).copyWith(color: fg),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    _display,
                    key: const ValueKey('numeric-display'),
                    style: GhinaType.moneyL.copyWith(color: fg),
                  ),
                  if (q.suffix != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      q.suffix!,
                      style: GhinaType.moneyM.w(800).copyWith(color: fg),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Keypad(onKey: fb == null ? _key : null),
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey});

  final ValueChanged<String>? onKey;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    [',', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      children: [
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (var i = 0; i < row.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: ChunkySurface(
                      color: g.surface,
                      edgeColor: g.borderEdge,
                      borderColor: g.border,
                      depth: GhinaDepth.sm,
                      borderRadius: GhinaRadii.rLg,
                      onTap: onKey == null ? null : () => onKey!(row[i]),
                      enabled: onKey != null,
                      semanticLabel: row[i] == '⌫' ? 'Hapus' : row[i],
                      child: SizedBox(
                        height: 46,
                        child: Center(
                          child: row[i] == '⌫'
                              ? Icon(
                                  Icons.backspace_rounded,
                                  color: g.textSecondary,
                                )
                              : Text(
                                  row[i],
                                  style: GhinaType.h2
                                      .w(900)
                                      .copyWith(color: g.textPrimary),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
