import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/services.dart';
import 'platform_providers.dart';
import 'voice_recorder_controller.dart';

enum DictationPhase {
  idle,

  /// Checking availability / permission, opening the recognizer.
  starting,
  listening,

  /// Between two recognizer sessions (Android ends one after ~silence; we
  /// start the next one right away).
  restarting,

  /// User pressed stop; waiting for the final result.
  stopping,

  /// Dictation not possible here — show [DictationState.hint].
  unavailable,

  /// Failed — see [DictationState.error].
  error,
}

final class DictationState {
  const DictationState({
    this.phase = DictationPhase.idle,
    this.committed = '',
    this.partial = '',
    this.level = 0,
    this.availability,
    this.error,
    this.permission,
  });

  final DictationPhase phase;

  /// Finalised text of all sessions so far.
  final String committed;

  /// Live (not yet final) text of the current utterance — show it greyed.
  final String partial;

  /// Mic level 0..1.
  final double level;

  final SpeechAvailability? availability;
  final SpeechError? error;
  final MicPermissionStatus? permission;

  /// Everything recognised so far (committed + live partial).
  String get text => joinTranscript(committed, partial);

  bool get isActive =>
      phase == DictationPhase.starting ||
      phase == DictationPhase.listening ||
      phase == DictationPhase.restarting ||
      phase == DictationPhase.stopping;

  /// Indonesian hint for [DictationPhase.unavailable] (offline pack missing…).
  String? get hint => availability?.hint;

  DictationState copyWith({
    DictationPhase? phase,
    String? committed,
    String? partial,
    double? level,
    SpeechAvailability? availability,
    SpeechError? error,
    bool clearError = false,
    MicPermissionStatus? permission,
  }) => DictationState(
    phase: phase ?? this.phase,
    committed: committed ?? this.committed,
    partial: partial ?? this.partial,
    level: level ?? this.level,
    availability: availability ?? this.availability,
    error: clearError ? null : (error ?? this.error),
    permission: permission ?? this.permission,
  );
}

/// Joins transcript pieces with a single space (no leading/trailing spaces).
String joinTranscript(String a, String b) {
  final x = a.trim(), y = b.trim();
  if (x.isEmpty) return y;
  if (y.isEmpty) return x;
  return '$x $y';
}

/// Continuous dictation ("Dikte"): live speech-to-text into the note body.
///
/// * Partial results are cumulative within one recognizer session → they
///   replace [DictationState.partial]; a final result is appended to
///   [DictationState.committed].
/// * Android ends a session after a few seconds of silence (and on
///   `error_no_match`/`error_speech_timeout`); while the user hasn't pressed
///   stop, a new session starts after [restartDelay]. After
///   [maxSilentSessions] consecutive sessions without any words, dictation
///   stops by itself.
/// * Starting dictation cancels a running voice recording (one mic owner).
///
/// ```dart
/// final d = ref.watch(dictationControllerProvider);
/// await ref.read(dictationControllerProvider.notifier).start();
/// final text = await ref.read(dictationControllerProvider.notifier).stop();
/// insertIntoBody(text);   // then .clear()
/// ```
class DictationController extends Notifier<DictationState> {
  static const restartDelay = Duration(milliseconds: 250);
  static const maxSilentSessions = 3;

  /// How long to wait for the final result after stop / session end.
  static const finalizeTimeout = Duration(seconds: 3);

  late SpeechTranscriber _t;
  final _subs = <StreamSubscription<Object?>>[];
  bool _want = false;
  bool _sessionHadWords = false;
  bool _sessionClosed = true;
  bool _endHandled = true;
  int _silentSessions = 0;
  Timer? _restartTimer;
  Timer? _finalizeTimer;
  Completer<String>? _stopCompleter;

  @override
  DictationState build() {
    final t = _t = ref.read(speechTranscriberProvider);
    ref.onDispose(() {
      _want = false;
      _restartTimer?.cancel();
      _finalizeTimer?.cancel();
      for (final s in _subs) {
        unawaited(s.cancel());
      }
      _subs.clear();
      if (t.isListening) unawaited(t.cancel());
    });
    return const DictationState();
  }

  void _set(DictationState s) {
    if (ref.mounted) state = s;
  }

  void _subscribe() {
    if (_subs.isNotEmpty) return;
    _subs
      ..add(_t.results.listen(_onResult))
      ..add(_t.status.listen(_onStatus))
      ..add(_t.errors.listen(_onError))
      ..add(_t.levels.listen((l) => _set(state.copyWith(level: l))));
  }

  /// Starts dictating (keeps previously committed text — call [clear] first
  /// for a fresh transcript). Returns false when not possible (state tells
  /// why: `unavailable` + hint, or `error` + permission).
  Future<bool> start() async {
    if (state.isActive) return false;
    _set(
      state.copyWith(
        phase: DictationPhase.starting,
        partial: '',
        clearError: true,
      ),
    );

    if (ref.exists(voiceRecorderControllerProvider)) {
      final rec = ref.read(voiceRecorderControllerProvider.notifier);
      if (ref.read(voiceRecorderControllerProvider).isBusy) {
        await rec.stop();
      }
    }

    final availability = await _t.availability(
      locale: ref.read(speechLocaleProvider),
    );
    // Cancelled / stopped while starting → stay idle.
    if (!ref.mounted || state.phase != DictationPhase.starting) return false;
    if (!availability.canDictate(
      allowNetwork: ref.read(dictationAllowsNetworkProvider),
    )) {
      _set(
        state.copyWith(
          phase: DictationPhase.unavailable,
          availability: availability,
        ),
      );
      return false;
    }

    final perm = ref.read(microphonePermissionProvider);
    var status = await perm.status();
    if (!status.isGranted && status != MicPermissionStatus.unsupported) {
      status = await perm.request();
    }
    if (!ref.mounted || state.phase != DictationPhase.starting) return false;
    if (!status.isGranted) {
      _set(
        state.copyWith(
          phase: DictationPhase.error,
          availability: availability,
          permission: status,
          error: const SpeechError(SpeechErrorKind.permission, permanent: true),
        ),
      );
      return false;
    }

    _subscribe();
    _want = true;
    _silentSessions = 0;
    _set(state.copyWith(availability: availability, permission: status));
    return _listen();
  }

  Future<bool> _listen() async {
    _restartTimer?.cancel();
    _finalizeTimer?.cancel(); // stale timer of a previous session
    _finalizeTimer = null;
    _sessionHadWords = false;
    _sessionClosed = false;
    _endHandled = false;
    try {
      await _t.start(
        locale: ref.read(speechLocaleProvider),
        preferOffline: !ref.read(dictationAllowsNetworkProvider),
      );
    } on SpeechError catch (e) {
      _fail(e);
      return false;
    }
    if (!ref.mounted || !_want) {
      // Disposed (editor closed) or stopped/cancelled while the recognizer
      // was opening: release the mic now — nobody will stop it later.
      unawaited(_t.cancel());
      return false;
    }
    if (_want && state.phase != DictationPhase.stopping) {
      _set(state.copyWith(phase: DictationPhase.listening));
    }
    return true;
  }

  void _onResult(TranscriptUpdate r) {
    if (_sessionClosed) return; // late duplicate after the session ended
    final text = r.text.trim();
    if (text.isNotEmpty) {
      _sessionHadWords = true;
      _silentSessions = 0;
    }
    if (r.isFinal) {
      _sessionClosed = true;
      _set(
        state.copyWith(
          committed: joinTranscript(state.committed, text),
          partial: '',
        ),
      );
      if (state.phase == DictationPhase.stopping) _finalize();
    } else {
      _set(state.copyWith(partial: text));
    }
  }

  void _onStatus(SpeechSessionStatus s) {
    if (s == SpeechSessionStatus.listening) return;
    if (s == SpeechSessionStatus.notListening) {
      // Wait for `done` (all results delivered) but don't hang if it never
      // comes.
      _finalizeTimer ??= Timer(finalizeTimeout, _sessionEnded);
      return;
    }
    _sessionEnded();
  }

  void _onError(SpeechError e) {
    if (e.kind.isTransient) {
      _sessionEnded();
      return;
    }
    _fail(e);
  }

  /// A recognizer session is over: commit leftovers, then restart or finish.
  void _sessionEnded() {
    _finalizeTimer?.cancel();
    _finalizeTimer = null;
    if (_endHandled) {
      // Second signal for the same session (error + done, notListening + done).
      if (state.phase == DictationPhase.stopping) _finalize();
      return;
    }
    _endHandled = true;
    if (!_sessionClosed) {
      _sessionClosed = true;
      if (state.partial.isNotEmpty) {
        _set(
          state.copyWith(
            committed: joinTranscript(state.committed, state.partial),
            partial: '',
          ),
        );
      }
    }
    if (!ref.mounted) return;
    if (state.phase == DictationPhase.stopping || !_want) {
      _finalize();
      return;
    }
    if (!_sessionHadWords) _silentSessions++;
    if (_silentSessions >= maxSilentSessions) {
      _want = false;
      _finalize();
      return;
    }
    if (state.phase == DictationPhase.restarting) return;
    _set(state.copyWith(phase: DictationPhase.restarting, level: 0));
    _restartTimer = Timer(restartDelay, () {
      if (_want && ref.mounted) unawaited(_listen());
    });
  }

  void _fail(SpeechError e) {
    _want = false;
    _restartTimer?.cancel();
    _finalizeTimer?.cancel();
    _finalizeTimer = null;
    _sessionClosed = _endHandled = true;
    _set(
      state.copyWith(
        phase: DictationPhase.error,
        committed: joinTranscript(state.committed, state.partial),
        partial: '',
        error: e,
        level: 0,
      ),
    );
    _completeStop();
  }

  void _finalize() {
    _restartTimer?.cancel();
    _finalizeTimer?.cancel();
    _finalizeTimer = null;
    _sessionClosed = true;
    _set(
      state.copyWith(
        phase: DictationPhase.idle,
        committed: joinTranscript(state.committed, state.partial),
        partial: '',
        level: 0,
      ),
    );
    _completeStop();
  }

  void _completeStop() {
    final c = _stopCompleter;
    _stopCompleter = null;
    if (c != null && !c.isCompleted) c.complete(state.text);
  }

  /// Stops listening; completes with the full transcript once the final
  /// result arrived (or after [finalizeTimeout]).
  Future<String> stop() async {
    if (!state.isActive) return state.text;
    _want = false;
    _restartTimer?.cancel();
    if (state.phase == DictationPhase.restarting ||
        state.phase == DictationPhase.starting ||
        _sessionClosed) {
      _finalize();
      if (_t.isListening) await _t.cancel();
      return state.text;
    }
    final c = _stopCompleter ??= Completer<String>();
    _set(state.copyWith(phase: DictationPhase.stopping));
    _finalizeTimer ??= Timer(finalizeTimeout, _finalize);
    await _t.stop();
    return c.future;
  }

  /// Aborts listening; keeps text committed so far, drops the live partial.
  Future<void> cancel() async {
    if (!state.isActive) return;
    _want = false;
    _restartTimer?.cancel();
    _finalizeTimer?.cancel();
    _finalizeTimer = null;
    _sessionClosed = true;
    _set(state.copyWith(phase: DictationPhase.idle, partial: '', level: 0));
    _completeStop();
    await _t.cancel();
  }

  /// Returns the transcript and resets it (after inserting into the body).
  String takeText() {
    final t = state.text;
    clear();
    return t;
  }

  void clear() {
    if (state.isActive) return;
    _set(
      DictationState(
        phase: state.phase == DictationPhase.unavailable
            ? DictationPhase.unavailable
            : DictationPhase.idle,
        availability: state.availability,
      ),
    );
  }

  /// Android 13+: asks the OS to download the offline `id-ID` model.
  Future<bool> downloadOfflineModel() async {
    final ok = await _t.requestOfflineModel(
      locale: ref.read(speechLocaleProvider),
    );
    ref.invalidate(speechAvailabilityProvider);
    return ok;
  }

  Future<bool> openSettings() =>
      ref.read(microphonePermissionProvider).openAppSettings();
}

/// Auto-disposed: leaving the editor stops dictation and releases the mic.
final dictationControllerProvider =
    NotifierProvider.autoDispose<DictationController, DictationState>(
      DictationController.new,
    );
