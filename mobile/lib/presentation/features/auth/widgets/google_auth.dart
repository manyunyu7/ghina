import 'package:google_sign_in/google_sign_in.dart';

/// Google sign-in is shown only when the OAuth client ids are provided at build time:
///
/// ```
/// flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id used by the server>
///             --dart-define=GOOGLE_CLIENT_ID=<iOS client id>   # iOS only
/// ```
///
/// iOS also needs the reversed client id as a URL scheme in `Info.plist`, and Android
/// needs the app's SHA-1 registered in the Google Cloud console.
const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
const googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
const googleSignInEnabled = googleServerClientId != '';

Future<void>? _init;

/// Runs the native Google flow and returns the ID token for the server,
/// or null when the user cancels. Throws on other failures.
Future<String?> obtainGoogleIdToken() async {
  final gsi = GoogleSignIn.instance;
  _init ??= gsi.initialize(
    clientId: googleClientId.isEmpty ? null : googleClientId,
    serverClientId: googleServerClientId,
  );
  await _init;
  try {
    final account = await gsi.authenticate();
    return account.authentication.idToken;
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) return null;
    rethrow;
  }
}
