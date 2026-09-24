/// Microphone runtime permission (Android `RECORD_AUDIO`, iOS microphone +
/// speech recognition prompts).
library;

enum MicPermissionStatus {
  granted,

  /// Not granted yet (or denied once) — asking again shows the system prompt.
  denied,

  /// Denied with "don't ask again" (Android) / denied once (iOS): only the
  /// system settings page can grant it → show a hint + "Buka Pengaturan".
  permanentlyDenied,

  /// No microphone support on this platform (tests, desktop, web).
  unsupported;

  bool get isGranted => this == granted;
}

abstract interface class MicrophonePermission {
  /// Current status without prompting. May report [MicPermissionStatus.denied]
  /// for a permanently denied permission until [request] was called once in
  /// this process (Android can only tell the two apart right after a request).
  Future<MicPermissionStatus> status();

  /// Shows the system prompt when possible and returns the resulting status.
  Future<MicPermissionStatus> request();

  /// Opens this app's page in the system settings. Returns false when the
  /// platform cannot do it (then tell the user where to go).
  Future<bool> openAppSettings();
}
