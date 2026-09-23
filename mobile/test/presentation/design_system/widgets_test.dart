import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';

import '_helpers.dart';

AnimatedContainer _face(WidgetTester tester, Finder surface) =>
    tester.widget<AnimatedContainer>(
      find
          .descendant(of: surface, matching: find.byType(AnimatedContainer))
          .first,
    );

void main() {
  group('ChunkyButton', () {
    testWidgets('renders caps label and fires onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          Center(
            child: ChunkyButton(label: 'Simpan', onPressed: () => taps++),
          ),
        ),
      );
      expect(find.text('SIMPAN'), findsOneWidget);
      await tester.tap(find.byType(ChunkyButton));
      await tester.pump(const Duration(milliseconds: 200));
      expect(taps, 1);
    });

    testWidgets('face sinks while pressed and pops back on release', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Center(
            child: ChunkyButton(label: 'Lanjut', onPressed: () {}),
          ),
        ),
      );
      final surface = find.byType(ChunkySurface);
      expect((_face(tester, surface).margin as EdgeInsets).top, 0);

      final gesture = await tester.startGesture(tester.getCenter(surface));
      await tester.pump(const Duration(milliseconds: 150));
      final pressed = _face(tester, surface).margin as EdgeInsets;
      expect(pressed.top, greaterThan(0));
      expect(pressed.bottom, 0);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 200));
      expect((_face(tester, surface).margin as EdgeInsets).top, 0);
    });

    testWidgets('quick tap still shows the press briefly', (tester) async {
      await tester.pumpWidget(
        wrap(
          Center(
            child: ChunkyButton(label: 'Lanjut', onPressed: () {}),
          ),
        ),
      );
      final surface = find.byType(ChunkySurface);
      await tester.tap(surface);
      await tester.pump();
      expect((_face(tester, surface).margin as EdgeInsets).top, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 200));
      expect((_face(tester, surface).margin as EdgeInsets).top, 0);
    });

    testWidgets('disabled button ignores taps and does not sink', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const Center(child: ChunkyButton(label: 'Nanti', onPressed: null)),
        ),
      );
      final surface = find.byType(ChunkySurface);
      final gesture = await tester.startGesture(tester.getCenter(surface));
      await tester.pump(const Duration(milliseconds: 150));
      expect((_face(tester, surface).margin as EdgeInsets).top, 0);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('loading shows spinner and blocks taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          Center(
            child: ChunkyButton(
              label: 'Simpan',
              loading: true,
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('SIMPAN'), findsNothing);
      await tester.tap(find.byType(ChunkyButton));
      await tester.pump(const Duration(milliseconds: 200));
      expect(taps, 0);
    });

    for (final v in ChunkyButtonVariant.values) {
      testWidgets('variant $v renders in dark theme', (tester) async {
        await tester.pumpWidget(
          wrap(
            Center(
              child: ChunkyButton(label: 'X', variant: v, onPressed: () {}),
            ),
            dark: true,
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ChunkyProgressBar', () {
    testWidgets('animates to value and clamps overflow', (tester) async {
      await tester.pumpWidget(
        wrap(
          const Padding(
            padding: EdgeInsets.all(20),
            child: ChunkyProgressBar(value: 1.7),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final mid = tester.widget<TweenAnimationBuilder<double>>(
        find.byType(TweenAnimationBuilder<double>),
      );
      expect(mid.tween.end, 1.0);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('.*')), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('budget factory picks colors by usage', (tester) async {
      expect(ChunkyProgressBar.budget(used: 0.2).color, GhinaColors.green);
      expect(ChunkyProgressBar.budget(used: 0.8).color, GhinaColors.orange);
      expect(ChunkyProgressBar.budget(used: 1.2).color, GhinaColors.red);
    });

    testWidgets('handles NaN and zero without throwing', (tester) async {
      await tester.pumpWidget(
        wrap(
          const Column(
            children: [
              ChunkyProgressBar(value: double.nan, animate: false),
              ChunkyProgressBar(value: 0),
              ProgressRing(value: double.nan),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Mascot', () {
    for (final mood in MascotMood.values) {
      for (final dark in [false, true]) {
        testWidgets('paints $mood (${dark ? 'dark' : 'light'})', (
          tester,
        ) async {
          await tester.pumpWidget(
            wrap(
              Center(child: MascotView(mood: mood, size: 160)),
              dark: dark,
            ),
          );
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 333));
          }
          expect(tester.takeException(), isNull);
          expect(find.byType(CustomPaint), findsWidgets);
        });
      }
    }

    test('painter paints every mood at many phases', () {
      for (final mood in MascotMood.values) {
        for (var p = 0.0; p <= 1.0; p += 0.05) {
          final recorder = PictureRecorder();
          MascotPainter(
            mood: mood,
            phase: p,
            shadowColor: Colors.black12,
          ).paint(Canvas(recorder), const Size(200, 200));
          recorder.endRecording().dispose();
        }
      }
    });

    testWidgets('mood change pops without error; static mode does not tick', (
      tester,
    ) async {
      var mood = MascotMood.happy;
      late StateSetter set;
      await tester.pumpWidget(
        wrap(
          StatefulBuilder(
            builder: (c, s) {
              set = s;
              return MascotView(mood: mood);
            },
          ),
        ),
      );
      set(() => mood = MascotMood.excited);
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });

    testWidgets('static mascot schedules no frames', (tester) async {
      await tester.pumpWidget(
        wrap(const MascotView(mood: MascotMood.sad, animate: false)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('MascotSpeech shows message', (tester) async {
      await tester.pumpWidget(
        wrap(const MascotSpeech(message: 'Halo!', title: 'Tips')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Halo!'), findsOneWidget);
      expect(find.text('Tips'), findsOneWidget);
    });
  });

  group('Celebration', () {
    testWidgets('showCelebration shows title, stats and pops on continue', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: GhinaTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ChunkyButton(
                  label: 'Go',
                  expand: false,
                  onPressed: () => showCelebration(
                    context,
                    xp: 15,
                    streak: 6,
                    subtitle: 'Hebat!',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('GO'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('Mantap!'), findsOneWidget);
      expect(find.text('Hebat!'), findsOneWidget);
      expect(find.text('+15'), findsOneWidget);
      expect(find.text('6 hari'), findsOneWidget);
      expect(find.byType(CelebrationScreen), findsOneWidget);

      await tester.tap(find.text('LANJUT'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CelebrationScreen), findsNothing);
      // Let confetti & mascot controllers wind down.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('toast badge appears and auto-dismisses', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: GhinaTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ChunkyButton(
                  label: 'Toast',
                  expand: false,
                  onPressed: () => showToastBadge(context, message: '+10 XP'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('TOAST'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('+10 XP'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('+10 XP'), findsNothing);
    });

    testWidgets('showChunkyConfirm resolves true on confirm', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: GhinaTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ChunkyButton(
                  label: 'Del',
                  expand: false,
                  onPressed: () async => result = await showChunkyConfirm(
                    context,
                    title: 'Hapus?',
                    confirmLabel: 'Hapus',
                    destructive: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('DEL'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Hapus?'), findsOneWidget);
      await tester.tap(find.text('HAPUS'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(result, isTrue);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('Inputs', () {
    testWidgets('ChunkySegmented reports the tapped segment', (tester) async {
      String? picked;
      await tester.pumpWidget(
        wrap(
          Padding(
            padding: const EdgeInsets.all(20),
            child: ChunkySegmented<String>(
              segments: const [
                ChunkySegment(
                  value: 'expense',
                  label: 'Pengeluaran',
                  color: GhinaColors.red,
                ),
                ChunkySegment(
                  value: 'income',
                  label: 'Pemasukan',
                  color: GhinaColors.green,
                ),
              ],
              value: 'expense',
              onChanged: (v) => picked = v,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pemasukan'));
      expect(picked, 'income');
    });

    testWidgets('ChunkyChoiceChips single & multi select', (tester) async {
      Set<int>? got;
      await tester.pumpWidget(
        wrap(
          ChunkyChoiceChips<int>(
            options: const [
              ChunkyChoice(value: 1, label: 'A'),
              ChunkyChoice(value: 2, label: 'B'),
            ],
            selected: const {1},
            multi: true,
            onChanged: (s) => got = s,
          ),
        ),
      );
      await tester.tap(find.text('B'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(got, {1, 2});
    });

    testWidgets('AmountKeypad types into controller', (tester) async {
      final c = AmountController();
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              AmountDisplay(controller: c),
              AmountKeypad(
                controller: c,
                quickAmounts: const [10000],
                onSubmit: () {},
              ),
            ],
          ),
        ),
      );
      for (final k in ['2', '5', '000']) {
        await tester.tap(find.text(k).last);
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(c.amount, 25000);
      expect(find.text('25.000'), findsOneWidget);
      await tester.tap(find.text('+10 rb'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(c.amount, 35000);
    });

    testWidgets('ChunkyTextField shows label, error and toggles obscure', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const Padding(
            padding: EdgeInsets.all(20),
            child: ChunkyTextField(
              label: 'Kata sandi',
              obscureText: true,
              errorText: 'Salah',
            ),
          ),
        ),
      );
      expect(find.text('Kata sandi'), findsOneWidget);
      expect(find.text('Salah'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.visibility_rounded));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_off_rounded), findsOneWidget);
    });

    testWidgets('pickers report selections', (tester) async {
      String? icon, color;
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            child: Column(
              children: [
                ChunkyColorPicker(
                  selected: '#f97316',
                  onChanged: (c) => color = c,
                ),
                IconGridPicker(
                  selected: 'utensils',
                  onChanged: (n) => icon = n,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.flight_rounded));
      await tester.tap(find.bySemanticsLabel('Warna #3b82f6'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(icon, 'plane');
      expect(color, '#3b82f6');
    });
  });

  group('Misc widgets render', () {
    testWidgets('nav bar, sync badge, skeleton, empty state, money, learning', (
      tester,
    ) async {
      var tab = -1, center = 0;
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: GhinaTheme.dark(),
          home: Scaffold(
            body: const SingleChildScrollView(
              child: Column(
                children: [
                  SyncBadge(state: SyncIndicatorState.syncing, pendingCount: 2),
                  SkeletonList(count: 2),
                  EmptyState(
                    title: 'Kosong',
                    actionLabel: 'Tambah',
                    onAction: _noop,
                  ),
                  MoneyText(amount: -25000),
                  MoneyText(amount: 12000, countUp: true),
                  HeartsRow(hearts: 2),
                  StreakFlame(count: 3),
                  LevelBadge(level: 4),
                  XpBadge(xp: 10),
                  GemCounter(gems: 5),
                  PathNode(
                    state: PathNodeState.current,
                    icon: Icons.star_rounded,
                    progress: 0.5,
                  ),
                  QuizOptionTile(
                    label: 'Dana darurat',
                    state: QuizOptionState.wrong,
                  ),
                  AnswerFeedbackBar(correct: true, onContinue: _noop),
                  CategoryAvatar(iconName: 'HeartPulse', colorHex: '#ef4444'),
                ],
              ),
            ),
            bottomNavigationBar: ChunkyNavBar(
              currentIndex: 0,
              onTap: (i) => tab = i,
              onCenterTap: () => center++,
              items: const [
                ChunkyNavItem(icon: Icons.home_rounded, label: 'Beranda'),
                ChunkyNavItem(
                  icon: Icons.receipt_long_rounded,
                  label: 'Transaksi',
                ),
                ChunkyNavItem(icon: Icons.school_rounded, label: 'Belajar'),
                ChunkyNavItem(icon: Icons.person_rounded, label: 'Profil'),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('-Rp 25.000'), findsOneWidget);
      expect(find.text('Menyinkron · 2'), findsOneWidget);
      await tester.tap(find.text('Belajar'));
      await tester.tap(find.bySemanticsLabel('Tambah transaksi'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tab, 2);
      expect(center, 1);
      expect(tester.takeException(), isNull);
    });
  });
}

void _noop() {}
