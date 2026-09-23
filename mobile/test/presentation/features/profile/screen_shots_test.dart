/// Renders the learn / profile / prayers / health / food screens with
/// realistic data at 390×844 (light + dark) and on a small phone with large
/// text. Always asserts no layout exceptions; set GHINA_SHOTS_DIR to also
/// write PNGs:
///   GHINA_SHOTS_DIR=/tmp/shots flutter test test/presentation/features/profile/screen_shots_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/dates.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/game/game.dart' hide MascotMood;
import 'package:ghina/presentation/design_system/design_system.dart'
    show PathNode, QuizOptionTile;
import 'package:ghina/presentation/features/food/pages/food_form_page.dart';
import 'package:ghina/presentation/features/food/pages/food_page.dart';
import 'package:ghina/presentation/features/health/pages/health_form_page.dart';
import 'package:ghina/presentation/features/health/pages/health_page.dart';
import 'package:ghina/presentation/features/learn/pages/learn_page.dart';
import 'package:ghina/presentation/features/learn/pages/lesson_page.dart';
import 'package:ghina/presentation/features/prayers/pages/prayers_page.dart';
import 'package:ghina/presentation/features/profile/pages/achievements_page.dart';
import 'package:ghina/presentation/features/profile/pages/profile_page.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/_helpers.dart';
import '_harness.dart';

final _routes = <RouteBase>[
  GoRoute(path: '/learn', builder: (_, _) => const LearnPage()),
  GoRoute(
    path: '/learn/lesson/:lessonId',
    builder: (_, s) => LessonPage(lessonId: s.pathParameters['lessonId']!),
  ),
  GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
  GoRoute(path: '/achievements', builder: (_, _) => const AchievementsPage()),
  GoRoute(path: '/prayers', builder: (_, _) => const PrayersPage()),
  GoRoute(path: '/health', builder: (_, _) => const HealthPage()),
  GoRoute(path: '/health/new', builder: (_, _) => const HealthFormPage()),
  GoRoute(
    path: '/health/:id',
    builder: (_, s) => HealthFormPage(id: s.pathParameters['id']),
  ),
  GoRoute(path: '/food', builder: (_, _) => const FoodPage()),
  GoRoute(path: '/food/new', builder: (_, _) => const FoodFormPage()),
  GoRoute(
    path: '/food/:id',
    builder: (_, s) => FoodFormPage(id: s.pathParameters['id']),
  ),
];

LessonCompletion _done(String id, int daysAgo, {double acc = 1}) =>
    LessonCompletion(
      lessonId: id,
      at: harnessNow.subtract(Duration(days: daysAgo)),
      xp: 15,
      accuracy: acc,
      perfect: acc == 1,
      practice: false,
    );

Harness _seeded() {
  final h = Harness()..seedStreak(9);
  h.seedGame(
    GameLocalState(
      lessonCompletions: [
        _done('u1l1', 5),
        _done('u1l1', 4),
        _done('u1l2', 3, acc: 0.8),
        _done('u1l3', 1),
        _done('u1l1', 1),
      ],
      lastSeenLevel: 3,
      seenAchievements: {for (final a in achievementDefs) a.id},
      onboardingDone: true,
      celebrated: {'goal:${dateKey(harnessNow)}'},
    ),
  );
  // Prayers: a colourful month.
  for (var i = 0; i < 22; i++) {
    final d = addDays(harnessNow, -i);
    final n = i == 0 ? 3 : (i % 5 == 3 ? 0 : (i % 3 == 1 ? 4 : 5));
    h.prayers.seed(d, Prayer.values.take(n));
  }
  // Health.
  final weights = [70.4, 70.1, 69.8, 69.9, 69.5, 69.2, 69.0, 68.7, 68.9, 68.5];
  for (var i = 0; i < weights.length; i++) {
    final d = addDays(
      harnessNow,
      -(weights.length - 1 - i) * 2,
    ).subtract(const Duration(hours: 4));
    final bp = i.isEven;
    h.health.s.put(
      HealthEntry(
        id: 'h$i',
        date: d,
        weight: weights[i],
        systolic: bp ? 118 + i * 2 : null,
        diastolic: bp ? 76 + i : null,
        pulse: bp ? 70 + i : null,
        note: i == weights.length - 1 ? 'Habis jogging' : null,
        createdAt: d,
        updatedAt: d,
      ),
    );
  }
  // Food.
  final foods = [
    ('f1', 'Bubur ayam', MealType.breakfast, 380, 0, 7, null),
    (
      'f2',
      'Nasi padang rendang',
      MealType.lunch,
      820,
      0,
      12,
      'Kepedesan tapi enak',
    ),
    ('f3', 'Es kopi susu', MealType.snack, 180, 0, 15, null),
    ('f4', 'Soto betawi', MealType.dinner, 540, 1, 19, null),
    ('f5', 'Roti bakar', MealType.breakfast, 300, 1, 8, null),
    ('f6', 'Gado-gado', MealType.lunch, 450, 2, 12, 'Porsi jumbo'),
  ];
  for (final (id, name, meal, kcal, ago, hour, note) in foods) {
    final d = DateTime(
      harnessNow.year,
      harnessNow.month,
      harnessNow.day - ago,
      hour,
      15,
    );
    h.food.s.put(
      FoodLog(
        id: id,
        date: d,
        name: name,
        meal: meal,
        calories: kcal,
        note: note,
        createdAt: d,
        updatedAt: d,
      ),
    );
  }
  return h;
}

Future<void> _shot(
  WidgetTester tester,
  String name,
  String location, {
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  Future<void> Function()? then,
}) async {
  const key = ValueKey('shot');
  final h = _seeded();
  await pumpScreen(
    tester,
    h,
    location: location,
    routes: _routes,
    dark: dark,
    size: size,
    textScale: textScale,
    boundaryKey: key,
  );
  if (then != null) await then();
  await settle(tester, 10);
  expect(tester.takeException(), isNull);
  await saveShot(tester, key, name, pixelRatio: 2);
  await drain(tester);
}

Future<void> _startLesson(WidgetTester tester) async {
  await tester.tap(find.text('MULAI BELAJAR'));
  await settle(tester, 4);
}

Future<void> _answerWrong(WidgetTester tester) async {
  await _startLesson(tester);
  await tester.tap(find.byType(QuizOptionTile).first);
  await settle(tester, 2);
  await tester.tap(find.text('CEK'));
  await settle(tester, 4);
}

void main() {
  setUpAll(loadGhinaFonts);

  final screens = <(String, String, Future<void> Function(WidgetTester)?)>[
    ('learn_path', '/learn', null),
    (
      'learn_popover',
      '/learn',
      (t) async {
        await t.tap(find.byType(PathNode).at(3));
        await settle(t, 6);
      },
    ),
    ('learn_intro', '/learn/lesson/u1l4', null),
    ('learn_question', '/learn/lesson/u1l4', _startLesson),
    ('learn_feedback', '/learn/lesson/u1l1', _answerWrong),
    ('profile_top', '/profile', null),
    (
      'profile_streak',
      '/profile',
      (t) async {
        await scrollTo(t, find.text('Target harian'));
      },
    ),
    (
      'profile_menu',
      '/profile',
      (t) async {
        await scrollTo(t, find.text('Catatan makan'), delta: 500);
      },
    ),
    ('achievements', '/achievements', null),
    ('prayers_top', '/prayers', null),
    (
      'prayers_calendar',
      '/prayers',
      (t) async {
        await scrollTo(t, find.text('Kalender'));
        await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
      },
    ),
    ('health', '/health', null),
    (
      'health_charts',
      '/health',
      (t) async {
        await t.drag(find.byType(Scrollable).first, const Offset(0, -420));
      },
    ),
    ('health_form_bp', '/health/new?mode=bp', null),
    ('food', '/food', null),
    ('food_form', '/food/new', null),
    ('food_edit', '/food/f2', null),
  ];

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    for (final (name, loc, then) in screens) {
      testWidgets('$name renders ($mode)', (tester) async {
        await _shot(
          tester,
          '${name}_$mode',
          loc,
          dark: dark,
          then: then == null ? null : () => then(tester),
        );
      });
    }
  }

  // Small phone + large text: layout must not overflow.
  for (final (name, loc, then) in screens) {
    testWidgets('$name fits 360×640 at 1.3× text', (tester) async {
      await _shot(
        tester,
        '${name}_small',
        loc,
        size: const Size(360, 640),
        textScale: 1.3,
        then: then == null ? null : () => then(tester),
      );
    });
  }
}
