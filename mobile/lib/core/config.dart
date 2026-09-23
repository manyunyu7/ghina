/// App-wide configuration.
abstract final class AppConfig {
  static const _fromEnv = String.fromEnvironment('API_BASE_URL');

  /// Production server (see ../docs/mobile-sync.md).
  static const productionUrl = 'https://ghina.tentrem.space';

  /// Server base URL. Defaults to production; point at a local dev server with
  /// `--dart-define=API_BASE_URL=http://10.0.2.2:3000` (Android emulator) or
  /// `http://localhost:3000` (iOS simulator).
  static String get apiBaseUrl =>
      _fromEnv.isNotEmpty ? _stripSlash(_fromEnv) : productionUrl;

  /// Turns a server-relative path such as `/uploads/abc.jpg` into an absolute URL.
  /// Absolute URLs are returned unchanged; null/empty stays null.
  static String? resolveUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$apiBaseUrl${path.startsWith('/') ? '' : '/'}$path';
  }

  static String _stripSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;
}
