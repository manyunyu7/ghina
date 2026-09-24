import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../di/core_providers.dart' show clockProvider;
import '../../../domain/services/services.dart';
import 'dictation_controller.dart';
import 'platform_providers.dart';

enum VoiceRecorderPhase {
  idle,

  /// Asking for permission / opening the mic.
  starting,
  recording,

  /// Finalising the file.
  stopping,

  /// Last attempt failed — see [VoiceRecorderState.error].
  error,
}

final class VoiceRecorderState {
  const VoiceRecorderState({
    this.phase = VoiceRecorderPhase.idle,
    this.elapsed = Duration.zero,
    this.maxDuration = kMaxVoiceNoteDuration,
    this.levels = const [],
    this.lastRecording,
    this.autoStopped = false,
    this.error,
    this.permission,
  });

  final VoiceRecorderPhase phase;

  /// Time recorded so far (ticks ≈ 5×/s).
  final Duration elapsed;
  final Duration maxDuration;

  /// Recent input levels 0..1, oldest first, at most
  /// [VoiceRecorderController.waveformSamples] — draw them as bars.
  final List<double> levels;

  /// The finished clip, until taken with [VoiceRecorderController.takeRecording].
  final VoiceRecording? lastRecording;

  /// [lastRecording] ended because it reached [maxDuration].
  final bool autoStopped;

  final VoiceRecorderErrorKind? error;

  /// Set when [error] is a permission problem — `permanentlyDenied` means
  /// "show Buka Pengaturan".
  final MicPermissionStatus? permission;

  bool get isRecording => phase == VoiceRecorderPhase.recording;
  bool get isBusy =>
      phase == VoiceRecorderPhase.starting ||
      phase == VoiceRecorderPhase.recording ||
      phase == VoiceRecorderPhase.stopping;

  Duration get remaining {
    final r = maxDuration - elapsed;
    return r.isNegative ? Duration.zero : r;
  }

  /// 0..1 progress towards the limit (for a ring).
  double get progress => maxDuration.inMilliseconds == 0
      ? 0
      : (elapsed.inMilliseconds / maxDuration.inMilliseconds).clamp(0.0, 1.0);

  VoiceRecorderState copyWith({
    VoiceRecorderPhase? phase,
    Duration? elapsed,
    List<double>? levels,
  }) => VoiceRecorderState(
    phase: phase ?? this.phase,
    elapsed: elapsed ?? this.elapsed,
    maxDuration: maxDuration,
    levels: levels ?? this.levels,
    lastRecording: lastRecording,
    autoStopped: autoStopped,
    error: error,
    permission: permission,
  );
}

/// Voice-clip recording state machine ("Rekam suara"):
///
/// `idle → starting → recording → stopping → idle(lastRecording)`, or
/// `→ error`. Stops by itself at [maxVoiceDurationProvider] (10 min) with
/// `autoStopped = true`. Starting a recording cancels an active dictation (one
/// mic owner). Disposing the provider (sheet closed) discards an unfinished
/// clip.
///
/// ```dart
/// final s = ref.watch(voiceRecorderControllerProvider);
/// final c = ref.read(voiceRecorderControllerProvider.notifier);
/// await c.start();                 // tap / long-press down
/// final clip = await c.stop();     // tap again / release  → VoiceRecording?
/// ref.listen(voiceRecorderControllerProvider, (_, s) {
///   if (s.autoStopped && s.lastRecording != null) save(c.takeRecording()!);
/// });
/// ```
class VoiceRecorderController extends Notifier<VoiceRecorderState> {
  static const waveformSamples = 48;
  static const tick = Duration(milliseconds: 200);

  Timer? _ticker;
  Timer? _autoStop;
  StreamSubscription<double>? _levelSub;
  DateTime? _startedAt;
  bool _stopRequested = false;
  bool _cancelRequested = false;
  Future<VoiceRecording?>? _finishing;

  late VoiceRecorder _recorder;
  Clock get _clock => ref.read(clockProvider);

  @override
  VoiceRecorderState build() {
    final recorder = _recorder = ref.read(voiceRecorderProvider);
    ref.onDispose(() {
      final wasActive = _startedAt != null;
      _teardown();
      if (wasActive) unawaited(recorder.cancel());
    });
    return VoiceRecorderState(maxDuration: ref.read(maxVoiceDurationProvider));
  }

  void _teardown() {
    _ticker?.cancel();
    _autoStop?.cancel();
    _ticker = _autoStop = null;
    unawaited(_levelSub?.cancel());
    _levelSub = null;
    _startedAt = null;
  }

  void _set(VoiceRecorderState s) {
    if (ref.mounted) state = s;
  }

  VoiceRecorderState _fresh({
    VoiceRecorderPhase phase = VoiceRecorderPhase.idle,
    VoiceRecording? recording,
    bool autoStopped = false,
    Duration elapsed = Duration.zero,
    VoiceRecorderErrorKind? error,
    MicPermissionStatus? permission,
  }) => VoiceRecorderState(
    phase: phase,
    elapsed: elapsed,
    maxDuration: state.maxDuration,
    lastRecording: recording,
    autoStopped: autoStopped,
    error: error,
    permission: permission,
  );

  /// Requests the mic permission if needed and starts recording. Returns false
  /// (state → error) when it couldn't.
  Future<bool> start() async {
    if (state.isBusy) return false;
    _stopRequested = _cancelRequested = false;
    _set(_fresh(phase: VoiceRecorderPhase.starting));

    if (ref.exists(dictationControllerProvider)) {
      await ref.read(dictationControllerProvider.notifier).cancel();
    }

    final perm = ref.read(microphonePermissionProvider);
    var status = await perm.status();
    if (!status.isGranted && status != MicPermissionStatus.unsupported) {
      status = await perm.request();
    }
    if (!ref.mounted) return false;
    if (!status.isGranted) {
      _set(
        _fresh(
          phase: VoiceRecorderPhase.error,
          error: status == MicPermissionStatus.unsupported
              ? VoiceRecorderErrorKind.unsupported
              : VoiceRecorderErrorKind.permission,
          permission: status,
        ),
      );
      return false;
    }
    if (_cancelRequested) {
      _set(_fresh());
      return false;
    }

    try {
      await _recorder.start();
    } on VoiceRecorderException catch (e) {
      _set(_fresh(phase: VoiceRecorderPhase.error, error: e.kind));
      return false;
    } catch (_) {
      // Anything else (storage dir, plugin) — don't stay stuck in `starting`.
      _set(
        _fresh(
          phase: VoiceRecorderPhase.error,
          error: VoiceRecorderErrorKind.failed,
        ),
      );
      return false;
    }
    if (!ref.mounted) {
      unawaited(_recorder.cancel());
      return false;
    }

    _startedAt = _clock.now();
    _set(_fresh(phase: VoiceRecorderPhase.recording));
    _levelSub = _recorder.levels.listen(_onLevel);
    _ticker = Timer.periodic(tick, (_) => _tick());
    final max = state.maxDuration;
    _autoStop = Timer(max, () => unawaited(_finish(auto: true)));

    if (_cancelRequested) {
      await cancel();
      return false;
    }
    if (_stopRequested) await _finish(auto: false);
    return true;
  }

  void _onLevel(double v) {
    if (!state.isRecording) return;
    final l = [...state.levels, v.clamp(0.0, 1.0).toDouble()];
    _set(
      state.copyWith(
        levels: l.length > waveformSamples
            ? l.sublist(l.length - waveformSamples)
            : l,
      ),
    );
  }

  Duration _elapsed() {
    final s = _startedAt;
    if (s == null) return state.elapsed;
    final e = _clock.now().difference(s);
    return e > state.maxDuration ? state.maxDuration : e;
  }

  void _tick() {
    if (!state.isRecording) return;
    final e = _elapsed();
    _set(state.copyWith(elapsed: e));
    // Belt and braces in case the one-shot timer was delayed.
    if (e >= state.maxDuration) unawaited(_finish(auto: true));
  }

  /// Stops and returns the clip (null when too short / nothing recorded).
  /// Called while still starting (quick hold-release) → stops right after the
  /// start completes; the result then lands in [VoiceRecorderState.lastRecording].
  Future<VoiceRecording?> stop() async {
    switch (state.phase) {
      case VoiceRecorderPhase.starting:
        _stopRequested = true;
        return null;
      case VoiceRecorderPhase.recording:
        return _finish(auto: false);
      case VoiceRecorderPhase.stopping:
        return _finishing;
      case VoiceRecorderPhase.idle:
      case VoiceRecorderPhase.error:
        return null;
    }
  }

  Future<VoiceRecording?> _finish({required bool auto}) {
    return _finishing ??= () async {
      final elapsed = _elapsed();
      _teardown();
      _set(
        state.copyWith(phase: VoiceRecorderPhase.stopping, elapsed: elapsed),
      );
      VoiceRecording? rec;
      try {
        rec = await _recorder.stop();
      } catch (_) {
        rec = null;
      }
      _set(
        _fresh(
          recording: rec,
          autoStopped: auto && rec != null,
          elapsed: rec?.duration ?? elapsed,
        ),
      );
      _finishing = null;
      return rec;
    }();
  }

  /// Discards the clip being recorded (no-op when idle).
  Future<void> cancel() async {
    switch (state.phase) {
      case VoiceRecorderPhase.starting:
        _cancelRequested = true;
        return;
      case VoiceRecorderPhase.recording:
        _teardown();
        await _recorder.cancel();
        _set(_fresh());
        return;
      case VoiceRecorderPhase.stopping:
      case VoiceRecorderPhase.idle:
      case VoiceRecorderPhase.error:
        return;
    }
  }

  /// Returns the finished clip once and clears it from the state.
  VoiceRecording? takeRecording() {
    final r = state.lastRecording;
    if (r != null) _set(_fresh());
    return r;
  }

  /// Deletes the finished clip's file (user tapped "Buang").
  Future<void> discardRecording() async {
    final r = takeRecording();
    if (r != null) await _recorder.deleteFile(r.path);
  }

  void clearError() {
    if (state.phase == VoiceRecorderPhase.error) _set(_fresh());
  }

  Future<bool> openSettings() =>
      ref.read(microphonePermissionProvider).openAppSettings();
}

/// Auto-disposed: closing the recorder UI releases the mic and discards an
/// unfinished clip.
final voiceRecorderControllerProvider =
    NotifierProvider.autoDispose<VoiceRecorderController, VoiceRecorderState>(
      VoiceRecorderController.new,
    );
