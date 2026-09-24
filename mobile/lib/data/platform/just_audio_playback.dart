import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../../domain/services/audio_playback.dart';

/// [AudioPlayback] with `just_audio` (ExoPlayer on Android, AVPlayer on iOS).
///
/// Chosen over `audioplayers` because it exposes a precise position stream +
/// duration + buffered position for scrubbing, supports request headers for
/// authenticated URLs, handles m4a/AAC from file and network identically, and
/// decodes seeks accurately on ExoPlayer.
final class JustAudioPlayback implements AudioPlayback {
  JustAudioPlayback({AudioPlayer Function()? createPlayer})
    : _createPlayer = createPlayer ?? AudioPlayer.new;

  final AudioPlayer Function() _createPlayer;
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  final _status = StreamController<PlaybackStatus>.broadcast();
  PlaybackStatus _last = PlaybackStatus.idle;

  AudioPlayer get _p {
    final existing = _player;
    if (existing != null) return existing;
    final p = _createPlayer();
    _stateSub = p.playerStateStream.listen(
      (s) => _emit(mapPlayerState(s.playing, s.processingState)),
      onError: (Object _) => _emit(PlaybackStatus.error),
    );
    return _player = p;
  }

  void _emit(PlaybackStatus s) {
    if (s == _last || _status.isClosed) return;
    _last = s;
    _status.add(s);
  }

  @override
  Future<Duration?> loadFile(String path) => _load(() => _p.setFilePath(path));

  @override
  Future<Duration?> loadUrl(String url, {Map<String, String>? headers}) =>
      _load(() => _p.setUrl(url, headers: headers));

  Future<Duration?> _load(Future<Duration?> Function() set) async {
    _emit(PlaybackStatus.loading);
    try {
      return await set();
    } catch (_) {
      _emit(PlaybackStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    final p = _p;
    if (p.processingState == ProcessingState.completed) {
      await p.seek(Duration.zero);
    }
    // just_audio's play() completes when playback pauses/ends — don't await.
    unawaited(p.play().catchError((Object _) => _emit(PlaybackStatus.error)));
  }

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> seek(Duration position) => _p.seek(position);

  @override
  Future<void> stop() async {
    await _player?.stop();
    _emit(PlaybackStatus.idle);
  }

  @override
  Stream<Duration> get position => _p.positionStream;

  @override
  Stream<Duration?> get duration => _p.durationStream;

  @override
  Stream<PlaybackStatus> get status => _status.stream;

  @override
  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _player?.dispose();
    _player = null;
    await _status.close();
  }
}

PlaybackStatus mapPlayerState(bool playing, ProcessingState state) =>
    switch (state) {
      ProcessingState.idle => PlaybackStatus.idle,
      ProcessingState.loading || ProcessingState.buffering =>
        playing ? PlaybackStatus.playing : PlaybackStatus.loading,
      ProcessingState.ready =>
        playing ? PlaybackStatus.playing : PlaybackStatus.ready,
      ProcessingState.completed => PlaybackStatus.completed,
    };
