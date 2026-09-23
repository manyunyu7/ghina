import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/domain/game/game.dart' hide MascotMood;
import 'package:ghina/presentation/design_system/design_system.dart'
    show PathNode;
import 'package:ghina/presentation/features/learn/pages/learn_page.dart';
import 'package:ghina/presentation/features/learn/pages/lesson_page.dart';
import 'package:ghina/presentation/state/game/game_providers.dart';
import 'package:go_router/go_router.dart';

import '../profile/_harness.dart';

final _routes = [
  GoRoute(path: '/learn', builder: (_, _) => const LearnPage()),
  GoRoute(
    path: '/learn/lesson/:lessonId',
    builder: (_, s) => LessonPage(lessonId: s.pathParameters['lessonId']!),
  ),
];

const _unit = LearnUnit(
  id: 'tu1',
  title: 'Unit Uji',
  description: 'Unit kecil untuk tes.',
  icon: 'savings',
  lessons: [
    Lesson(
      id: 'tl1',
      title: 'Semua Jenis Soal',
      description: 'Satu soal per jenis.',
      tip: 'Catat setiap hari ya.',
      questions: [
        MultipleChoiceQuestion(
          prompt: 'Warna daun?',
          options: ['Merah', 'Hijau', 'Biru'],
          correctIndex: 1,
          explanation: 'Daun berklorofil.',
        ),
        TrueFalseQuestion(
          prompt: 'Jajan kecil nggak perlu dicatat.',
          answer: false,
          explanation: 'Justru sering bocor.',
        ),
        FillBlankQuestion(
          prompt: 'Mencatat paling mudah dilakukan ___.',
          options: ['setahun sekali', 'setiap hari'],
          correctIndex: 1,
          explanation: 'Rutin itu kunci.',
        ),
        NumericQuestion(
          prompt: 'Rp 5.000 × 20 hari = ?',
          answer: 100000,
          prefix: 'Rp',
          explanation: 'Seratus ribu.',
        ),
        MatchPairsQuestion(
          prompt: 'Pasangkan.',
          pairs: [
            MatchPair('Kebutuhan', 'Makan'),
            MatchPair('Keinginan', 'Konser'),
          ],
          explanation: 'Makan itu wajib.',
        ),
        OrderStepsQuestion(
          prompt: 'Urutkan.',
          steps: ['Catat pemasukan', 'Sisihkan tabungan', 'Belanja'],
          explanation: 'Bayar diri sendiri dulu.',
        ),
      ],
    ),
    Lesson(
      id: 'tl2',
      title: 'Pelajaran Kedua',
      description: 'Masih terkunci.',
      questions: [
        TrueFalseQuestion(
          prompt: 'Nabung itu baik.',
          answer: true,
          explanation: 'Iya.',
        ),
      ],
    ),
  ],
);

final _extra = [
  learnUnitsProvider.overrideWithValue(const [_unit]),
];

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pump(const Duration(milliseconds: 150));
}

Future<void> _check(WidgetTester tester) async {
  await tester.tap(find.text('CEK'));
  await settle(tester, 4);
}

Future<void> _next(WidgetTester tester) async {
  final btn = find.text('LANJUT').evaluate().isNotEmpty
      ? 'LANJUT'
      : 'OKE, PAHAM';
  await tester.tap(find.text(btn).last);
  await settle(tester, 4);
}

void main() {
  testWidgets('path shows the unit banner and the current node popover', (
    tester,
  ) async {
    final h = Harness();
    await pumpScreen(
      tester,
      h,
      location: '/learn',
      routes: _routes,
      extra: _extra,
    );
    expect(find.text('Unit Uji'), findsOneWidget);
    expect(find.text('UNIT 1 · 0/2'), findsOneWidget);
    expect(find.text('MULAI'), findsOneWidget); // bubble on the current node

    await tester.tap(find.byType(PathNode).first);
    await settle(tester, 4);
    expect(find.text('Semua Jenis Soal'), findsOneWidget);
    await tester.tap(find.text('MULAI +15 XP'));
    await settle(tester, 6);
    expect(find.text('Tips dulu, yuk!'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('locked lessons explain why', (tester) async {
    final h = Harness();
    await pumpScreen(
      tester,
      h,
      location: '/learn',
      routes: _routes,
      extra: _extra,
    );
    await tester.tap(find.byType(PathNode).at(1));
    await settle(tester, 4);
    expect(find.text('Pelajaran Kedua'), findsOneWidget);
    expect(find.text('TERKUNCI'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('full lesson: every question type, a retry, then the result', (
    tester,
  ) async {
    final h = Harness();
    await pumpScreen(
      tester,
      h,
      location: '/learn/lesson/tl1',
      routes: _routes,
      extra: _extra,
    );
    expect(find.text('Tips dulu, yuk!'), findsOneWidget);
    await _tapText(tester, 'MULAI BELAJAR');
    await settle(tester, 3);

    // 1. Multiple choice — answer wrong first.
    expect(find.text('Warna daun?'), findsOneWidget);
    await _tapText(tester, 'Merah');
    await _check(tester);
    expect(find.text('Kurang tepat'), findsOneWidget);
    expect(find.textContaining('Daun berklorofil.'), findsOneWidget);
    expect(find.textContaining('muncul lagi nanti'), findsOneWidget);
    await _next(tester);

    // 2. True / false.
    await _tapText(tester, 'Salah');
    await _check(tester);
    expect(find.text('Kurang tepat'), findsNothing);
    await _next(tester);

    // 3. Fill in the blank.
    await _tapText(tester, 'setiap hari');
    await _check(tester);
    expect(find.text('Kurang tepat'), findsNothing);
    await _next(tester);

    // 4. Numeric keypad.
    for (final k in ['1', '0', '0', '0', '0', '0']) {
      await _tapText(tester, k);
    }
    expect(find.text('100.000'), findsOneWidget);
    await _check(tester);
    expect(find.text('Kurang tepat'), findsNothing);
    await _next(tester);

    // 5. Match pairs.
    await _tapText(tester, 'Kebutuhan');
    await _tapText(tester, 'Makan');
    await _tapText(tester, 'Keinginan');
    await _tapText(tester, 'Konser');
    await _check(tester);
    expect(find.text('Kurang tepat'), findsNothing);
    await _next(tester);

    // 6. Order steps.
    await _tapText(tester, 'Catat pemasukan');
    await _tapText(tester, 'Sisihkan tabungan');
    await _tapText(tester, 'Belanja');
    await _check(tester);
    expect(find.text('Kurang tepat'), findsNothing);
    await _next(tester);

    // Retry round: the missed question comes back.
    expect(find.text('PERBAIKI KESALAHAN'), findsOneWidget);
    await _tapText(tester, 'Hijau');
    await _check(tester);
    await _next(tester);
    await settle(tester, 10);

    // Result screen.
    expect(find.text('Pelajaran selesai!'), findsOneWidget);
    expect(find.text('+13'), findsOneWidget); // 15 − 2 for one mistake
    expect(find.text('83%'), findsOneWidget); // 5 of 6 right first try
    for (var i = 0; i < 6 && find.text('HOME').evaluate().isEmpty; i++) {
      final btn = find.text('LANJUT').evaluate().isNotEmpty
          ? 'LANJUT'
          : 'MANTAP!';
      if (find.text(btn).evaluate().isEmpty) break;
      await tester.tap(find.text(btn).last);
      await settle(tester, 10);
    }
    await drain(tester);
    expect(find.text('HOME'), findsOneWidget);
    final saved = GameLocalState.decode(
      h.gameStore.values[GameLocalState.storageKey],
    );
    expect(saved.lessonCompletions.single.lessonId, 'tl1');
    expect(saved.lessonCompletions.single.xp, 13);
  });

  testWidgets('quitting mid-lesson asks for confirmation', (tester) async {
    final h = Harness();
    await pumpScreen(
      tester,
      h,
      location: '/learn/lesson/tl1',
      routes: _routes,
      extra: _extra,
    );
    await _tapText(tester, 'MULAI BELAJAR');
    await settle(tester, 3);
    expect(find.text('CEK'), findsOneWidget);
    await _tapText(tester, 'Hijau');
    await _check(tester);
    await _next(tester);
    await tester.tap(find.byTooltip('Tutup'));
    await settle(tester, 4);
    expect(find.text('Yakin mau berhenti?'), findsOneWidget);
    await tester.tap(find.text('KELUAR'));
    await settle(tester, 6);
    expect(find.text('HOME'), findsOneWidget);
    await drain(tester);
  });
}
