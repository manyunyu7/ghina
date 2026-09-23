import 'package:flutter/material.dart';

import '../../../../domain/game/game.dart' show DailyGoalLevel;
import '../../../design_system/design_system.dart';

/// Visual identity of each daily goal level.
(IconData, ChunkySwatch) dailyGoalLook(DailyGoalLevel l) => switch (l) {
  DailyGoalLevel.santai => (Icons.spa_rounded, GhinaColors.green),
  DailyGoalLevel.reguler => (Icons.directions_walk_rounded, GhinaColors.blue),
  DailyGoalLevel.serius => (Icons.directions_run_rounded, GhinaColors.orange),
  DailyGoalLevel.intens => (
    Icons.local_fire_department_rounded,
    GhinaColors.red,
  ),
};

/// Duolingo-style list of daily goal options (big tappable cards).
class DailyGoalPicker extends StatelessWidget {
  const DailyGoalPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final DailyGoalLevel? selected;
  final ValueChanged<DailyGoalLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, level) in DailyGoalLevel.values.indexed) ...[
          if (i > 0) GhinaSpace.gapMd,
          Builder(
            builder: (context) {
              final (icon, color) = dailyGoalLook(level);
              final isSel = level == selected;
              return ChunkyCard(
                key: ValueKey('goal-${level.name}'),
                tinted: isSel ? GhinaColors.blue : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                onTap: () => onChanged(level),
                semanticLabel: '${level.label}, ${level.description}',
                child: Row(
                  children: [
                    CategoryAvatar(
                      icon: icon,
                      color: color.base,
                      size: 44,
                      soft: true,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            level.label,
                            style: GhinaType.h3.copyWith(color: g.textPrimary),
                          ),
                          Text(
                            level.description,
                            style: GhinaType.bodyS.copyWith(
                              color: g.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ChunkyPill(
                      label: '${level.target}/hari',
                      color: isSel ? GhinaColors.blue : GhinaColors.gray,
                      soft: !isSel,
                      uppercase: false,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
