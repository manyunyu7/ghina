/// Playback of voice clips — local file (not uploaded yet) or remote URL.
library;

enum PlaybackStatus {
  idle,
  loading,

  /// Loaded, not playing (also after [AudioPlayback.pause]).
  ready,
  playing,

  /// Reached the end; [AudioPlayback.play] restarts from 0.
  completed,
  error,
}

abstract interface class AudioPlayback {
  /// Loads a local file; returns its duration when known.
  Future<Duration?> loadFile(String path);

  /// Loads a remote clip (e.g. an uploaded note audio). [headers] can carry an
  /// `Authorization` header when the file URL is not public.
  Future<Duration?> loadUrl(String url, {Map<String, String>? headers});

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// Stops and releases the current source (back to [PlaybackStatus.idle]).
  Future<void> stop();

  /// Current position, ≈ every 200 ms while playing. Broadcast.
  Stream<Duration> get position;

  /// Duration of the loaded source (null while unknown). Broadcast.
  Stream<Duration?> get duration;

  Stream<PlaybackStatus> get status;

  Future<void> dispose();
}
