/// Colors, icons and small shared pieces of the prayers feature.
library;

import 'package:flutter/material.dart';

import '../../../../domain/entities/entities.dart';
import '../../../../domain/game/game.dart' show XpRules;
import '../../../design_system/design_system.dart';

/// Look of each prayer (tile icon, time of day, accent).
typedef PrayerStyle = ({IconData icon, String time, ChunkySwatch color});

const Map<Prayer, PrayerStyle> prayerStyles = {
  Prayer.subuh: (
    icon: Icons.wb_twilight_rounded,
    time: 'Fajar',
    color: GhinaColors.purple,
  ),
  Prayer.dzuhur: (
    icon: Icons.wb_sunny_rounded,
    time: 'Siang',
    color: GhinaColors.yellow,
  ),
  Prayer.ashar: (
    icon: Icons.brightness_medium_rounded,
    time: 'Sore',
    color: GhinaColors.orange,
  ),
  Prayer.maghrib: (
    icon: Icons.nights_stay_rounded,
    time: 'Senja',
    color: GhinaColors.pink,
  ),
  Prayer.isya: (
    icon: Icons.dark_mode_rounded,
    time: 'Malam',
    color: GhinaColors.blue,
  ),
  Prayer.dhuha: (
    icon: Icons.light_mode_rounded,
    time: 'Pagi',
    color: GhinaColors.orange,
  ),
  Prayer.tahajud: (
    icon: Icons.bedtime_rounded,
    time: 'Sepertiga malam',
    color: GhinaColors.blue,
  ),
  Prayer.witir: (
    icon: Icons.star_rounded,
    time: 'Penutup malam',
    color: GhinaColors.purple,
  ),
};

/// Three-letter column label for the color map.
String prayerShort(Prayer p) => switch (p) {
  Prayer.subuh => 'Sub',
  Prayer.dzuhur => 'Dzu',
  Prayer.ashar => 'Ash',
  Prayer.maghrib => 'Mag',
  Prayer.isya => 'Isy',
  Prayer.dhuha => 'Dhu',
  Prayer.tahajud => 'Tah',
  Prayer.witir => 'Wit',
};

/// Spec color of a status (exact hex from `docs/prayer-quality.md`).
Color prayerStatusColor(PrayerStatus s) => Color(s.argb);

/// "Belum diisi" cell color for the current theme.
Color prayerEmptyColor(BuildContext context) => Color(
  context.ghina.isDark ? PrayerStatus.emptyArgbDark : PrayerStatus.emptyArgb,
);

/// Color of a cell (null = not filled in).
Color prayerCellColor(BuildContext context, PrayerStatus? s) =>
    s == null ? prayerEmptyColor(context) : prayerStatusColor(s);

ChunkySwatch prayerStatusSwatch(PrayerStatus s) =>
    ChunkySwatch.fromColor(prayerStatusColor(s));

IconData prayerStatusIcon(PrayerStatus s) => switch (s) {
  PrayerStatus.masjid => Icons.mosque_rounded,
  PrayerStatus.jamaah => Icons.groups_rounded,
  PrayerStatus.ontime => Icons.person_rounded,
  PrayerStatus.late => Icons.hourglass_bottom_rounded,
  PrayerStatus.qadha => Icons.history_rounded,
  PrayerStatus.missed => Icons.close_rounded,
  PrayerStatus.excused => Icons.spa_rounded,
  PrayerStatus.done => Icons.check_rounded,
};

/// XP a fardhu row with [s] earns (spec points; missed/excused 0).
int prayerStatusXp(PrayerStatus s) => XpRules.prayerXp(s.wire);

/// Sunnah dot colors on the color map (spec: dhuha #F472B6, tahajud #6366F1,
/// witir #14B8A6).
Color sunnahDotColor(Prayer p) => switch (p) {
  Prayer.dhuha => const Color(0xFFF472B6),
  Prayer.tahajud => const Color(0xFF6366F1),
  _ => const Color(0xFF14B8A6),
};

/// One legend entry: a color square and a label.
class PrayerLegendItem extends StatelessWidget {
  const PrayerLegendItem({
    super.key,
    required this.color,
    required this.label,
    this.round = false,
  });

  final Color color;
  final String label;
  final bool round;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: round ? 10 : 14,
        height: round ? 10 : 14,
        decoration: BoxDecoration(
          color: color,
          shape: round ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: round ? null : GhinaRadii.rSm,
        ),
      ),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          label,
          style: GhinaType.caption.copyWith(color: context.ghina.textSecondary),
        ),
      ),
    ],
  );
}

/// Legend of the 7 statuses + "Belum diisi".
class PrayerStatusLegend extends StatelessWidget {
  const PrayerStatusLegend({super.key, this.extra = const []});

  /// Extra items appended at the end (e.g. sunnah dots).
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 6,
    alignment: WrapAlignment.center,
    children: [
      for (final s in PrayerStatus.fardhu)
        PrayerLegendItem(color: prayerStatusColor(s), label: s.shortLabel),
      PrayerLegendItem(color: prayerEmptyColor(context), label: 'Belum diisi'),
      ...extra,
    ],
  );
}

/// Floating "+XP" that rises and fades (key it by a counter to replay).
class XpPop extends StatelessWidget {
  const XpPop({super.key, required this.xp});

  final int xp;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOut,
      builder: (_, t, child) => Opacity(
        opacity: (t < 0.7 ? 1.0 : 1 - (t - 0.7) / 0.3).clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, -26 * t),
          child: Transform.scale(
            scale: 0.8 + 0.4 * (t < 0.3 ? t / 0.3 : 1),
            child: child,
          ),
        ),
      ),
      child: XpBadge(xp: xp, plus: true),
    ),
  );
}
