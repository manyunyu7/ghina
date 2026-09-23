import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/game/shared_prefs_game_store.dart';
import 'package:ghina/domain/game/game.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('read / write / delete', () async {
    final store = SharedPrefsGameStore();
    expect(await store.read('k'), isNull);
    await store.write('k', 'v');
    expect(await store.read('k'), 'v');
    await store.delete('k');
    expect(await store.read('k'), isNull);
  });

  test('persists GameLocalState through the repository', () async {
    final repo = GameStateRepository(SharedPrefsGameStore());
    await repo.save(
      const GameLocalState(onboardingDone: true, lastSeenLevel: 3),
    );
    final loaded = await GameStateRepository(SharedPrefsGameStore()).load();
    expect(loaded.onboardingDone, isTrue);
    expect(loaded.lastSeenLevel, 3);
  });
}
