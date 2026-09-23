import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';

/// "Hari ini" / "Besok" / "3 hari lagi" / "Telat 2 hari", colored by urgency.
class DueChip extends StatelessWidget {
  const DueChip({super.key, required this.days});
  final int days;

  static String label(int days) => days < 0
      ? 'Telat ${-days} hari'
      : days == 0
      ? 'Hari ini'
      : days == 1
      ? 'Besok'
      : '$days hari lagi';

  @override
  Widget build(BuildContext context) {
    final sw = days <= 1
        ? GhinaColors.red
        : days <= 3
        ? GhinaColors.orange
        : days <= 7
        ? GhinaColors.yellow
        : GhinaColors.blue;
    return ChunkyPill(
      label: label(days),
      color: sw,
      soft: true,
      uppercase: false,
      icon: days <= 1 ? Icons.alarm_rounded : Icons.schedule_rounded,
    );
  }
}
