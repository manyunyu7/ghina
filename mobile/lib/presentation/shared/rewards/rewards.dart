/// Reward flow shared by every feature: XP toast after a write, pending
/// celebrations (daily goal, streak milestone, level up, badges) shown once
/// and acknowledged in one place. See `lib/presentation/shared/README.md`.
library;

export 'celebrations.dart'
    show
        CelebrationGate,
        celebrationGateProvider,
        presentNewAchievements,
        presentPendingCelebrations,
        showAchievementsUnlocked;
export 'reward_tracker.dart' show RewardTracker;
