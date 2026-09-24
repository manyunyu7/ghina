/// Voice-note recording (docs/notes.md → Voice notes).
///
/// Low-level device port: the recording *state machine* (permission, ticking
/// elapsed time, 10-minute auto-stop, waveform buffer) lives in
/// `presentation/state/platform/voice_recorder_controller.dart` — UI code should
/// use that controller, not this interface directly.
library;

/// Hard cap for one clip (spec: max 10 min). ~4.8 MB at 64 kbps, well under the
/// 20 MB `audio/*` upload limit.
const kMaxVoiceNoteDuration = Duration(minutes: 10);

/// MIME type of the files produced by [VoiceRecorder] (AAC-LC in MPEG-4 → `.m4a`).
const kVoiceNoteMimeType = 'audio/mp4';

/// A finished clip stored in app documents (`<documents>/voice/<id>.m4a`).
final class VoiceRecording {
  const VoiceRecording({
    required this.path,
    required this.duration,
    required this.sizeBytes,
    this.mimeType = kVoiceNoteMimeType,
  });

  /// Absolute local path (persistent storage, not a temp dir).
  final String path;
  final Duration duration;
  final int sizeBytes;
  final String mimeType;

  int get durationMs => duration.inMilliseconds;

  @override
  String toString() =>
      'VoiceRecording($path, ${duration.inMilliseconds} ms, $sizeBytes B)';
}

enum VoiceRecorderErrorKind {
  /// Microphone permission missing.
  permission,

  /// The mic is held by someone else (call, another recorder, dictation).
  busy,

  /// Platform without recording support (tests / desktop / web).
  unsupported,

  /// Anything else (encoder failure, storage full, …).
  failed,
}

final class VoiceRecorderException implements Exception {
  const VoiceRecorderException(this.kind, [this.message]);

  final VoiceRecorderErrorKind kind;
  final String? message;

  @override
  String toString() =>
      'VoiceRecorderException($kind${message == null ? '' : ': $message'})';
}

abstract interface class VoiceRecorder {
  /// Whether this platform can record at all.
  bool get isSupported;

  /// Starts a new clip (AAC-LC/m4a, mono, 64 kbps, 44.1 kHz). Does NOT prompt
  /// for permission — check [MicrophonePermission] first.
  ///
  /// Throws [VoiceRecorderException].
  Future<void> start();

  /// Finishes the clip and returns it; `null` when nothing was recording or the
  /// file is empty/unusable (it is deleted in that case).
  Future<VoiceRecording?> stop();

  /// Stops and deletes the current clip (no-op when idle).
  Future<void> cancel();

  /// Input level normalised to 0..1 (≈ every 80 ms while recording) — feed a
  /// waveform. Broadcast; emits nothing while idle.
  Stream<double> get levels;

  /// Deletes a clip file produced earlier (e.g. the user discards the draft).
  Future<void> deleteFile(String path);

  Future<void> dispose();
}
