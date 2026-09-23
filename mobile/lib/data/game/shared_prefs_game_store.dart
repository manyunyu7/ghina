import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/game/game_store.dart';

/// [GameStore] backed by shared_preferences. Constructible synchronously; the
/// preferences instance is resolved lazily on first use.
class SharedPrefsGameStore implements GameStore {
  SharedPrefsGameStore([Future<SharedPreferences>? prefs])
    : _prefs = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefs;

  @override
  Future<String?> read(String key) async => (await _prefs).getString(key);

  @override
  Future<void> write(String key, String value) async {
    await (await _prefs).setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await (await _prefs).remove(key);
  }
}
