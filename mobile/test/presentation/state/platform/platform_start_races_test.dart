/// Mic ownership while starting: stop / cancel / dispose during a slow start
/// must not leave the recognizer listening, and an unexpected recorder error
/// must not leave the recorder stuck in `starting`.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/platform/fakes.dart';
import 'package:ghina/domain/services/services.dart';
import 'package:ghina/presentation/state/platform/platform_state.dart';

/// [FakeSpeechTranscriber] whose `start` / `availability` wait for gates.
class GatedTranscriber implements SpeechTranscriber {
  final inner = FakeSpeechTranscriber();
  Completer<void>? startGate;
  Completer<void>? availabilityGate;

  @override
  Future<SpeechAvailability> availability({
    String locale = kDefaultSpeechLocale,
  }) async {
    if (availabilityGate != null) await availabilityGate!.future;
    return inner.availability(locale: locale);
  }

  @override
  Future<void> start({
    String locale = kDefaultSpeechLocale,
    bool preferOffline = true,
  }) async {
    if (startGate != null) await startGate!.future;
    return inner.start(locale: locale, preferOffline: preferOffline);
  }

  @override
  Future<bool> requestOfflineModel({String locale = kDefaultSpeechLocale}) =>
      inner.requestOfflineModel(locale: locale);
  @override
  Future<void> stop() => inner.stop();
  @override
  Future<void> cancel() => inner.cancel();
  @override
  bool get isListening => inner.isListening;
  @override
  Stream<TranscriptUpdate> get results => inner.results;
  @override
  Stream<SpeechSessionStatus> get status => inner.status;
  @override
  Stream<SpeechError> get errors => inner.errors;
  @override
  Stream<double> get levels => inner.levels;
  @override
  Future<void> dispose() => inner.dispose();
}

/// A recorder whose start fails with a non-[VoiceRecorderException].
class _ThrowingRecorder implements VoiceRecorder {
  final _levels = StreamController<double>.broadcast();
  @override
  bool get isSupported => true;
  @override
  Stream<double> get levels => _levels.stream;
  @override
  Future<void> start() async => throw StateError('no documents dir');
  @override
  Future<VoiceRecording?> stop() async => null;
  @override
  Future<void> cancel() async {}
  @override
  Future<void> deleteFile(String path) async {}
  @override
  Future<void> dispose() => _levels.close();
}

void main() {
  late GatedTranscriber speech;

  ProviderContainer container({VoiceRecorder? recorder}) {
    speech = GatedTranscriber();
    final c = ProviderContainer(
      overrides: [
        speechTranscriberProvider.overrideWithValue(speech),
        microphonePermissionProvider.overrideWithValue(
          FakeMicrophonePermission(),
        ),
        voiceRecorderProvider.overrideWithValue(
          recorder ?? FakeVoiceRecorder(),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('dictation: stop while the recognizer opens releases the mic', () async {
    final c = container();
    final sub = c.listen(dictationControllerProvider, (_, _) {});
    speech.startGate = Completer<void>();
    final ctl = c.read(dictationControllerProvider.notifier);
    final started = ctl.start();
    await pumpEventQueue();
    expect(c.read(dictationControllerProvider).isActive, isTrue);

    await ctl.stop();
    speech.startGate!.complete();
    expect(await started, isFalse);
    await pumpEventQueue();

    expect(speech.isListening, isFalse);
    expect(c.read(dictationControllerProvider).phase, DictationPhase.idle);
    sub.close();
  });

  test(
    'dictation: editor closed while the recognizer opens → cancelled',
    () async {
      final c = container();
      final sub = c.listen(dictationControllerProvider, (_, _) {});
      speech.startGate = Completer<void>();
      final started = c.read(dictationControllerProvider.notifier).start();
      await pumpEventQueue();

      sub.close(); // auto-dispose (editor gone)
      await pumpEventQueue();
      speech.startGate!.complete();
      expect(await started, isFalse);
      await pumpEventQueue();

      expect(speech.isListening, isFalse);
    },
  );

  test('dictation: cancel while checking availability never starts', () async {
    final c = container();
    final sub = c.listen(dictationControllerProvider, (_, _) {});
    speech.availabilityGate = Completer<void>();
    final ctl = c.read(dictationControllerProvider.notifier);
    final started = ctl.start();
    await pumpEventQueue();

    await ctl.cancel();
    speech.availabilityGate!.complete();
    expect(await started, isFalse);
    await pumpEventQueue();

    expect(speech.inner.starts, 0);
    expect(speech.isListening, isFalse);
    expect(c.read(dictationControllerProvider).phase, DictationPhase.idle);
    sub.close();
  });

  test(
    'recorder: unexpected start error → error, not stuck starting',
    () async {
      final c = container(recorder: _ThrowingRecorder());
      final sub = c.listen(voiceRecorderControllerProvider, (_, _) {});
      final ok = await c.read(voiceRecorderControllerProvider.notifier).start();
      expect(ok, isFalse);
      final s = c.read(voiceRecorderControllerProvider);
      expect(s.phase, VoiceRecorderPhase.error);
      expect(s.isBusy, isFalse);
      sub.close();
    },
  );
}
