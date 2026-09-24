import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/services.dart';
import 'platform_providers.dart';

final class VoicePlayerState {
  const VoicePlayerState({
    this.key,
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration,
  });

  /// Which clip is loaded (the caller's id, e.g. the attachment id).
  final String? key;
  final PlaybackStatus status;
  final Duration position;
  final Duration? duration;

  bool isPlaying(String clipKey) =>
      key == clipKey && status == PlaybackStatus.playing;

  /// Position for [clipKey] (zero when another clip is loaded).
  Duration positionOf(String clipKey) =>
      key == clipKey ? position : Duration.zero;

  VoicePlayerState copyWith({
    String? key,
    PlaybackStatus? status,
    Duration? position,
    Duration? duration,
  }) => VoicePlayerState(
    key: key ?? this.key,
    status: status ?? this.status,
    position: position ?? this.position,
    duration: duration ?? this.duration,
  );
}

/// One shared player for voice clips — starting a clip stops the previous one.
///
/// ```dart
/// final p = ref.watch(voicePlayerControllerProvider);
/// ref.read(voicePlayerControllerProvider.notifier)
///    .toggle(clip.id, filePath: clip.localPath, url: clip.remoteUrl);
/// Slider(value: p.positionOf(clip.id)…, onChanged: (v) => c.seek(…));
/// ```
class VoicePlayerController extends Notifier<VoicePlayerState> {
  late AudioPlayback _player;

  @override
  VoicePlayerState build() {
    final player = _player = ref.read(audioPlaybackProvider);
    final subs = <StreamSubscription<Object?>>[
      player.status.listen((s) => _set(state.copyWith(status: s))),
      player.position.listen((p) => _set(state.copyWith(position: p))),
      player.duration.listen((d) {
        if (d != null) _set(state.copyWith(duration: d));
      }),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        unawaited(s.cancel());
      }
      unawaited(player.stop());
    });
    return const VoicePlayerState();
  }

  void _set(VoicePlayerState s) {
    if (ref.mounted) state = s;
  }

  /// Plays/pauses [key]. Loads it first when another (or no) clip is loaded —
  /// the local [filePath] wins over [url] when the file exists.
  Future<void> toggle(
    String key, {
    String? filePath,
    String? url,
    Map<String, String>? headers,
  }) async {
    if (state.key == key && state.status != PlaybackStatus.error) {
      if (state.status == PlaybackStatus.playing) return _player.pause();
      return _player.play();
    }
    await _player.stop();
    _set(VoicePlayerState(key: key, status: PlaybackStatus.loading));
    try {
      final d = filePath != null
          ? await _player.loadFile(filePath)
          : url != null
          ? await _player.loadUrl(url, headers: headers)
          : null;
      if (d == null && filePath == null && url == null) {
        _set(state.copyWith(status: PlaybackStatus.error));
        return;
      }
      if (d != null) _set(state.copyWith(duration: d));
      await _player.play();
    } catch (_) {
      if (filePath != null && url != null) {
        // Local copy gone (e.g. app data cleared) → stream the uploaded one.
        _set(const VoicePlayerState());
        return toggle(key, url: url, headers: headers);
      }
      _set(state.copyWith(status: PlaybackStatus.error));
    }
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> stop() async {
    await _player.stop();
    _set(const VoicePlayerState());
  }
}

/// Auto-disposed: playback stops when no widget shows a clip any more.
final voicePlayerControllerProvider =
    NotifierProvider.autoDispose<VoicePlayerController, VoicePlayerState>(
      VoicePlayerController.new,
    );
