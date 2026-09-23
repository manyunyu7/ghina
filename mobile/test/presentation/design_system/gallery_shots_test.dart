import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/design_system/gallery/ui_gallery_screen.dart';

import '_helpers.dart';

/// Renders every gallery section in light & dark. Set GHINA_SHOTS_DIR to
/// write PNGs for visual review:
///   GHINA_SHOTS_DIR=/tmp/shots flutter test test/presentation/design_system/gallery_shots_test.dart
void main() {
  setUpAll(loadGhinaFonts);

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    for (var i = 0; i < UiGallery.sections.length; i++) {
      final section = UiGallery.sections[i];
      testWidgets('gallery section "${section.title}" renders ($mode)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(840, 4000);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        const key = ValueKey('shot');
        await tester.pumpWidget(
          wrap(
            SingleChildScrollView(
              child: RepaintBoundary(
                key: key,
                child: Builder(
                  builder: (context) => Container(
                    color: context.ghina.background,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionHeader(title: section.title),
                        section.builder(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            dark: dark,
          ),
        );
        await tester.pump(const Duration(milliseconds: 900));
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.takeException(), isNull);
        await saveShot(
          tester,
          key,
          '${(i + 1).toString().padLeft(2, '0')}_${section.title.replaceAll(RegExp(r'[^A-Za-z]+'), '_').toLowerCase()}_$mode',
        );
      });
    }

    testWidgets('nav bar + celebration render ($mode)', (tester) async {
      tester.view.physicalSize = const Size(780, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      const key = ValueKey('shot');
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? GhinaTheme.dark() : GhinaTheme.light(),
            home: const CelebrationScreen(
              subtitle: 'Kamu mencatat 3 transaksi hari ini.',
              streak: 6,
              confetti: false,
              stats: [
                CelebrationStat(
                  label: 'Total XP',
                  value: '+15',
                  icon: Icons.bolt_rounded,
                  color: GhinaColors.yellow,
                ),
                CelebrationStat(
                  label: 'Hemat',
                  value: '92%',
                  icon: Icons.savings_rounded,
                  color: GhinaColors.green,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 500));
      await saveShot(tester, key, '20_celebration_$mode', pixelRatio: 1);

      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? GhinaTheme.dark() : GhinaTheme.light(),
            home: Scaffold(
              appBar: AppBar(
                title: const Text('Beranda'),
                actions: const [
                  Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SyncBadge(
                      state: SyncIndicatorState.offline,
                      pendingCount: 2,
                    ),
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      StreakFlame(count: 12),
                      GemCounter(gems: 120),
                      HeartsRow(hearts: 4, size: 22),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const MascotSpeech(
                    mood: MascotMood.waving,
                    message: 'Halo Rani! Hari ini kamu belum mencatat apa-apa.',
                  ),
                  const SizedBox(height: 16),
                  ChunkyCard(
                    child: Row(
                      children: [
                        ProgressRing(
                          value: 0.6,
                          size: 90,
                          stroke: 10,
                          child: Text('60%', style: GhinaType.h3.w(900)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Target harian', style: GhinaType.h3),
                              const SizedBox(height: 8),
                              ChunkyProgressBar.budget(used: 0.6),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionHeader(
                    title: 'Transaksi terbaru',
                    actionLabel: 'Lihat semua',
                    onAction: _noop,
                  ),
                  const ChunkyTile(
                    leading: CategoryAvatar(
                      iconName: 'coffee',
                      colorHex: '#f59e0b',
                    ),
                    title: 'Kopi susu',
                    subtitle: 'GoPay · 09:12',
                    trailing: MoneyText(amount: 22000, tone: MoneyTone.expense),
                  ),
                ],
              ),
              bottomNavigationBar: ChunkyNavBar(
                currentIndex: 0,
                onTap: (_) {},
                onCenterTap: () {},
                items: UiGallery.navItems,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1000));
      await saveShot(tester, key, '21_home_mock_$mode', pixelRatio: 1);
    });
  }
}

void _noop() {}
