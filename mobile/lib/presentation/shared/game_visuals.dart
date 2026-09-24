/// The one place that turns game-engine values into visuals: mascot mood
/// mapping, achievement tier colours/labels, game content icons and the
/// achievement badge. Every feature uses these; don't re-map ad hoc.
library;

import 'package:flutter/material.dart';

import '../../domain/game/game.dart' as game;
import '../design_system/design_system.dart';

// ---------------------------------------------------------------- mascot

/// Maps the engine's [game.MascotMood] (domain) onto the drawable
/// [MascotMood] (design system). The two enums live in different layers on
/// purpose; this is the only conversion between them.
MascotMood mascotMoodOf(game.MascotMood m) => switch (m) {
  game.MascotMood.celebrating => MascotMood.excited,
  game.MascotMood.happy => MascotMood.happy,
  game.MascotMood.encouraging => MascotMood.waving,
  game.MascotMood.worried => MascotMood.thinking,
  game.MascotMood.sad => MascotMood.sad,
  game.MascotMood.sleeping => MascotMood.sleeping,
};

// ---------------------------------------------------------------- tiers

/// Badge colour per achievement tier.
ChunkySwatch tierSwatch(game.AchievementTier t) => switch (t) {
  game.AchievementTier.bronze => GhinaColors.orange,
  game.AchievementTier.silver => GhinaColors.blue,
  game.AchievementTier.gold => GhinaColors.yellow,
  game.AchievementTier.diamond => GhinaColors.purple,
};

/// Indonesian tier name.
String tierLabel(game.AchievementTier t) => switch (t) {
  game.AchievementTier.bronze => 'Perunggu',
  game.AchievementTier.silver => 'Perak',
  game.AchievementTier.gold => 'Emas',
  game.AchievementTier.diamond => 'Berlian',
};

// ---------------------------------------------------------------- icons

/// Material icon names used by game content (units, achievements).
const Map<String, IconData> _gameIcons = {
  'account_balance_wallet': Icons.account_balance_wallet_rounded,
  'auto_awesome': Icons.auto_awesome_rounded,
  'bolt': Icons.bolt_rounded,
  'credit_card': Icons.credit_card_rounded,
  'edit_note': Icons.edit_note_rounded,
  'emoji_events': Icons.emoji_events_rounded,
  'event_available': Icons.event_available_rounded,
  'favorite': Icons.favorite_rounded,
  'inventory': Icons.inventory_2_rounded,
  'local_fire_department': Icons.local_fire_department_rounded,
  'menu_book': Icons.menu_book_rounded,
  'military_tech': Icons.military_tech_rounded,
  'monitor_weight': Icons.monitor_weight_rounded,
  'mosque': Icons.mosque_rounded,
  'nights_stay': Icons.nights_stay_rounded,
  'pie_chart': Icons.pie_chart_rounded,
  'receipt_long': Icons.receipt_long_rounded,
  'restaurant': Icons.restaurant_rounded,
  'savings': Icons.savings_rounded,
  'school': Icons.school_rounded,
  'shield': Icons.shield_rounded,
  'stars': Icons.stars_rounded,
  'swap_horiz': Icons.swap_horiz_rounded,
  'track_changes': Icons.track_changes_rounded,
  'trending_up': Icons.trending_up_rounded,
  'verified': Icons.verified_rounded,
  'wb_twilight': Icons.wb_twilight_rounded,
  'volunteer_activism': Icons.volunteer_activism_rounded,
  'whatshot': Icons.whatshot_rounded,
  'workspace_premium': Icons.workspace_premium_rounded,
};

/// Icon for a game content icon name (units, achievements); falls back to
/// the lucide registry, then a star.
IconData gameIcon(String name) =>
    _gameIcons[name] ?? GhinaIcons.of(name, fallback: Icons.star_rounded);

// ---------------------------------------------------------------- badge

/// Round achievement badge in its tier colour (grey when locked).
class AchievementBadge extends StatelessWidget {
  const AchievementBadge({
    super.key,
    required this.def,
    required this.unlocked,
    this.size = 64,
  });

  final game.AchievementDef def;
  final bool unlocked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = tierSwatch(def.tier);
    final face = unlocked ? sw.base : g.disabled;
    final edge = unlocked ? sw.edge : g.disabledEdge;
    return SizedBox(
      width: size,
      height: size + size * 0.08,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: size,
              decoration: BoxDecoration(color: edge, shape: BoxShape.circle),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              height: size,
              decoration: BoxDecoration(
                color: face,
                shape: BoxShape.circle,
                border: Border.all(
                  color: unlocked
                      ? Colors.white.withValues(alpha: 0.55)
                      : g.border,
                  width: size * 0.05,
                ),
              ),
              child: Icon(
                unlocked ? gameIcon(def.icon) : Icons.lock_rounded,
                size: size * 0.46,
                color: unlocked ? sw.on : g.onDisabled,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
