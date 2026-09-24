import 'dart:convert';

import 'daily_goal.dart';
import 'game_date.dart';

/// Minimal key-value persistence for local-only game state.
/// Implemented in `data/game` (shared_preferences); [InMemoryGameStore] for tests.
abstract interface class GameStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class InMemoryGameStore implements GameStore {
  InMemoryGameStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// One finished lesson session.
class LessonCompletion {
  const LessonCompletion({
    required this.lessonId,
    required this.at,
    required this.xp,
    required this.accuracy,
    required this.perfect,
    required this.practice,
  });

  factory LessonCompletion.fromJson(Map<String, dynamic> j) => LessonCompletion(
    lessonId: j['lessonId'] as String,
    at: DateTime.parse(j['at'] as String),
    xp: (j['xp'] as num).toInt(),
    accuracy: (j['accuracy'] as num).toDouble(),
    perfect: j['perfect'] as bool? ?? false,
    practice: j['practice'] as bool? ?? false,
  );

  final String lessonId;

  /// Local time it was completed.
  final DateTime at;
  final int xp;

  /// First-try accuracy 0.0 – 1.0.
  final double accuracy;
  final bool perfect;

  /// Replay of an already completed lesson.
  final bool practice;

  GameDate get day => GameDate.fromDateTime(at);

  Map<String, dynamic> toJson() => {
    'lessonId': lessonId,
    'at': at.toIso8601String(),
    'xp': xp,
    'accuracy': accuracy,
    'perfect': perfect,
    'practice': practice,
  };
}

/// All game state that cannot be derived from synced data.
class GameLocalState {
  const GameLocalState({
    this.lessonCompletions = const [],
    this.dailyGoalHistory = const [],
    this.usedFreezeDays = const {},
    this.grantedFreezes = const [],
    this.seenAchievements = const {},
    this.lastSeenLevel,
    this.celebrated = const {},
    this.onboardingDone = false,
    this.fireClearDays = const {},
  });

  static const storageKey = 'ghina.game.state.v1';

  factory GameLocalState.fromJson(Map<String, dynamic> j) {
    List<dynamic> list(String k) => (j[k] as List<dynamic>?) ?? const [];
    GameDate? date(dynamic v) => v is String ? GameDate.tryParse(v) : null;
    return GameLocalState(
      lessonCompletions: [
        for (final e in list('lessonCompletions'))
          LessonCompletion.fromJson((e as Map).cast<String, dynamic>()),
      ],
      dailyGoalHistory: [
        for (final e in list('dailyGoalHistory'))
          if (date((e as Map)['from']) case final from?)
            if (DailyGoalLevel.byName(e['level'] as String? ?? '')
                case final level?)
              DailyGoalChange(from, level),
      ],
      usedFreezeDays: {for (final e in list('usedFreezeDays')) ?date(e)},
      grantedFreezes: [for (final e in list('grantedFreezes')) ?date(e)],
      seenAchievements: {for (final e in list('seenAchievements')) e as String},
      lastSeenLevel: (j['lastSeenLevel'] as num?)?.toInt(),
      celebrated: {for (final e in list('celebrated')) e as String},
      onboardingDone: j['onboardingDone'] as bool? ?? false,
      fireClearDays: {for (final e in list('fireClearDays')) ?date(e)},
    );
  }

  /// Decodes stored JSON; corrupt data yields a fresh state instead of crashing.
  static GameLocalState decode(String? raw) {
    if (raw == null || raw.isEmpty) return const GameLocalState();
    try {
      return GameLocalState.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return const GameLocalState();
    }
  }

  final List<LessonCompletion> lessonCompletions;
  final List<DailyGoalChange> dailyGoalHistory;

  /// Missed days covered by a freeze (recorded so the streak stays stable).
  final Set<GameDate> usedFreezeDays;

  /// Extra freezes granted (rewards), by the day they were granted.
  final List<GameDate> grantedFreezes;
  final Set<String> seenAchievements;

  /// Last level the user saw (level-up celebration); null = not initialised.
  final int? lastSeenLevel;

  /// Celebration keys already shown (e.g. `goal:2026-09-23`, `streak:2026-09-23`).
  final Set<String> celebrated;
  final bool onboardingDone;

  /// Days that ended with 0 undone FIRE tasks in their focus areas ("FIRE
  /// kosong", see `fire_clear.dart`): a local daily snapshot, add-only.
  final Set<GameDate> fireClearDays;

  DailyGoalLevel get currentGoal => dailyGoalHistory.isEmpty
      ? DailyGoalLevel.defaultLevel
      : dailyGoalHistory.last.level;

  bool isLessonCompleted(String lessonId) =>
      lessonCompletions.any((c) => c.lessonId == lessonId);

  GameLocalState copyWith({
    List<LessonCompletion>? lessonCompletions,
    List<DailyGoalChange>? dailyGoalHistory,
    Set<GameDate>? usedFreezeDays,
    List<GameDate>? grantedFreezes,
    Set<String>? seenAchievements,
    int? lastSeenLevel,
    Set<String>? celebrated,
    bool? onboardingDone,
    Set<GameDate>? fireClearDays,
  }) => GameLocalState(
    lessonCompletions: lessonCompletions ?? this.lessonCompletions,
    dailyGoalHistory: dailyGoalHistory ?? this.dailyGoalHistory,
    usedFreezeDays: usedFreezeDays ?? this.usedFreezeDays,
    grantedFreezes: grantedFreezes ?? this.grantedFreezes,
    seenAchievements: seenAchievements ?? this.seenAchievements,
    lastSeenLevel: lastSeenLevel ?? this.lastSeenLevel,
    celebrated: celebrated ?? this.celebrated,
    onboardingDone: onboardingDone ?? this.onboardingDone,
    fireClearDays: fireClearDays ?? this.fireClearDays,
  );

  Map<String, dynamic> toJson() => {
    'lessonCompletions': [for (final c in lessonCompletions) c.toJson()],
    'dailyGoalHistory': [
      for (final c in dailyGoalHistory)
        {'from': c.from.toKey(), 'level': c.level.name},
    ],
    'usedFreezeDays': [for (final d in usedFreezeDays) d.toKey()],
    'grantedFreezes': [for (final d in grantedFreezes) d.toKey()],
    'seenAchievements': seenAchievements.toList(),
    'lastSeenLevel': lastSeenLevel,
    'celebrated': celebrated.toList(),
    'onboardingDone': onboardingDone,
    'fireClearDays': [for (final d in fireClearDays) d.toKey()],
  };

  String encode() => jsonEncode(toJson());
}

/// Loads/saves [GameLocalState] through a [GameStore].
class GameStateRepository {
  const GameStateRepository(this.store);

  final GameStore store;

  Future<GameLocalState> load() async =>
      GameLocalState.decode(await store.read(GameLocalState.storageKey));

  Future<void> save(GameLocalState state) =>
      store.write(GameLocalState.storageKey, state.encode());

  Future<void> clear() => store.delete(GameLocalState.storageKey);
}
