import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/data/platform/fakes.dart';
import 'package:ghina/di/core_providers.dart' show clockProvider;
import 'package:ghina/domain/services/services.dart';
import 'package:ghina/presentation/state/platform/platform_state.dart';

/// "Now" follows fake_async's virtual time.
final class FakeAsyncClock implements Clock {
  FakeAsyncClock(this.fa);
  final FakeAsync fa;
  final _base = DateTime(2026, 9, 24, 10);
  @override
  DateTime now() => _base.add(fa.elapsed);
}

void main() {
  late FakeVoiceRecorder recorder;
  late FakeMicrophonePermission permission;
  late FakeSpeechTranscriber speech;

  ProviderContainer makeContainer(
    FakeAsync fa, {
    Duration max = const Duration(minutes: 10),
  }) {
    final clock = FakeAsyncClock(fa);
    final start = clock.now();
    recorder = FakeVoiceRecorder(
      durationOf: () => clock.now().difference(start),
    );
    permission = FakeMicrophonePermission();
    speech = FakeSpeechTranscriber();
    final c = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(clock),
        voiceRecorderProvider.overrideWithValue(recorder),
        microphonePermissionProvider.overrideWithValue(permission),
        speechTranscriberProvider.overrideWithValue(speech),
        maxVoiceDurationProvider.overrideWithValue(max),
      ],
    );
    c.listen(voiceRecorderControllerProvider, (_, _) {});
    return c;
  }

  VoiceRecorderState stateOf(ProviderContainer c) =>
      c.read(voiceRecorderControllerProvider);
  VoiceRecorderController ctl(ProviderContainer c) =>
      c.read(voiceRecorderControllerProvider.notifier);

  test('idle → recording → stop returns the clip', () {
    fakeAsync((fa) {
      final c = makeContainer(fa);
      bool? started;
      ctl(c).start().then((v) => started = v);
      fa.flushMicrotasks();
      expect(started, isTrue);
      expect(stateOf(c).phase, VoiceRecorderPhase.recording);

      fa.elapse(const Duration(seconds: 3));
      expect(stateOf(c).elapsed, const Duration(seconds: 3));

      recorder.emitLevel(0.5);
      recorder.emitLevel(2); // clamped
      fa.flushMicrotasks();
      expect(stateOf(c).levels, [0.5, 1.0]);

      VoiceRecording? clip;
      ctl(c).stop().then((r) => clip = r);
      fa.flushMicrotasks();
      expect(clip, isNotNull);
      expect(clip!.duration, const Duration(seconds: 3));
      expect(stateOf(c).phase, VoiceRecorderPhase.idle);
      expect(stateOf(c).lastRecording, clip);
      expect(stateOf(c).autoStopped, isFalse);

      expect(ctl(c).takeRecording(), clip);
      expect(stateOf(c).lastRecording, isNull);
      c.dispose();
    });
  });

  test('auto-stops at the max duration', () {
    fakeAsync((fa) {
      final c = makeContainer(fa, max: const Duration(minutes: 10));
      ctl(c).start();
      fa.flushMicrotasks();

      fa.elapse(const Duration(minutes: 9, seconds: 59));
      expect(stateOf(c).phase, VoiceRecorderPhase.recording);
      expect(
        stateOf(c).remaining,
        lessThanOrEqualTo(const Duration(seconds: 1)),
      );

      fa.elapse(const Duration(seconds: 2));
      final s = stateOf(c);
      expect(s.phase, VoiceRecorderPhase.idle);
      expect(s.autoStopped, isTrue);
      expect(s.lastRecording!.duration, const Duration(minutes: 10));
      expect(recorder.calls.where((x) => x == 'stop'), hasLength(1));

      // No timers left running.
      fa.elapse(const Duration(minutes: 5));
      expect(recorder.calls.where((x) => x == 'stop'), hasLength(1));
      expect(fa.pendingTimers, isEmpty);
      c.dispose();
    });
  });

  test('waveform keeps only the last N samples', () {
    fakeAsync((fa) {
      final c = makeContainer(fa);
      ctl(c).start();
      fa.flushMicrotasks();
      for (var i = 0; i < VoiceRecorderController.waveformSamples + 10; i++) {
        recorder.emitLevel(i / 100);
      }
      fa.flushMicrotasks();
      final l = stateOf(c).levels;
      expect(l, hasLength(VoiceRecorderController.waveformSamples));
      expect(l.last, (VoiceRecorderController.waveformSamples + 9) / 100);
      c.dispose();
    });
  });

  test('permission denied → error with status, no recording', () {
    fakeAsync((fa) {
      final c = makeContainer(fa);
      permission
        ..current = MicPermissionStatus.denied
        ..afterRequest = MicPermissionStatus.permanentlyDenied;
      bool? started;
      ctl(c).start().then((v) => started = v);
      fa.flushMicrotasks();
      expect(started, isFalse);
      expect(permission.requests, 1);
      final s = stateOf(c);
      expect(s.phase, VoiceRecorderPhase.error);
      expect(s.error, VoiceRecorderErrorKind.permission);
      expect(s.permission, MicPermissionStatus.permanentlyDenied);
      expect(recorder.calls, isEmpty);

      ctl(c).clearError();
      expect(stateOf(c).phase, VoiceRecorderPhase.idle);
      c.dispose();
    });
  });

  test('recorder start failure (mic busy) → error', () {
    fakeAsync((fa) {
      final c = makeContainer(fa);
      recorder.startError = const VoiceRecorderException(
        VoiceRecorderErrorKind.busy,
      );
      ctl(c).start();
      fa.flushMicrotasks();
      expect(stateOf(c).phase, VoiceRecorderPhase.error);
      expect(stateOf(c).error, VoiceRecorderErrorKind.busy);
      expect(fa.pendingTimers, isEmpty);
      c.dispose();
    });
  });

  test('stop while still starting (quick hold-release) stops after start', () {
    fakeAsync((fa) {
      final c = makeContainer(fa);
      final gate = recorder.startGate = Completer<void>();
      ctl(c).start();
      fa.flushMicrotasks();
      expect(stateOf(c).phase, VoiceRecorderPhase.starting);

      ctl(c).stop();
      gate.complete();
      fa.flushMicrotasks();
      expect(recorder.calls, ['start', 'stop']);
      expect(stateOf(c).phase, VoiceRecorderPhase.idle);
      expect(fa.pendingTimers, isEmpty);
      c.dispose();
    });
  });

  test('cancel discards the clip; start is refused while busy', () {
    fakeAsync((fa) {
      final c = makeContainer(fa);
      ctl(c).start();
      fa.flushMicrotasks();
      bool? second;
      ctl(c).start().then((v) => second = v);
      fa.flushMicrotasks();
      expect(second, isFalse);

      ctl(c).cancel();
      fa.flushMicrotasks();
      expect(recorder.calls, ['start', 'cancel']);
      expect(stateOf(c).phase, VoiceRecorderPhase.idle);
      expect(stateOf(c).lastRecording, isNull);
      expect(fa.pendingTimers, isEmpty);
      c.dispose();
    });
  });

  test('disposing the provider while recording cancels the recorder', () {
    fakeAsync((fa) {
      final c = makeContainer(fa);
      ctl(c).start();
      fa.flushMicrotasks();
      c.dispose();
      fa.flushMicrotasks();
      expect(recorder.calls, ['start', 'cancel']);
    });
  });

  test('discardRecording deletes the file', () {
    fakeAsync((fa) {
      final c = makeContainer(fa);
      ctl(c).start();
      fa.flushMicrotasks();
      fa.elapse(const Duration(seconds: 2));
      ctl(c).stop();
      fa.flushMicrotasks();
      final path = stateOf(c).lastRecording!.path;
      ctl(c).discardRecording();
      fa.flushMicrotasks();
      expect(recorder.deleted, [path]);
      expect(stateOf(c).lastRecording, isNull);
      c.dispose();
    });
  });

  test('starting a recording cancels an active dictation (one mic owner)', () {
    fakeAsync((fa) {
      final c = makeContainer(fa);
      c.listen(dictationControllerProvider, (_, _) {});
      c.read(dictationControllerProvider.notifier).start();
      fa.flushMicrotasks();
      expect(
        c.read(dictationControllerProvider).phase,
        DictationPhase.listening,
      );

      ctl(c).start();
      fa.flushMicrotasks();
      expect(speech.calls, contains('cancel'));
      expect(c.read(dictationControllerProvider).phase, DictationPhase.idle);
      expect(stateOf(c).phase, VoiceRecorderPhase.recording);
      c.dispose();
    });
  });
}
