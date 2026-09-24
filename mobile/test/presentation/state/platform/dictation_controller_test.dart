import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/platform/fakes.dart';
import 'package:ghina/domain/services/services.dart';
import 'package:ghina/presentation/state/platform/platform_state.dart';

void main() {
  late FakeSpeechTranscriber speech;
  late FakeMicrophonePermission permission;
  late FakeVoiceRecorder recorder;

  ProviderContainer makeContainer({bool allowNetwork = false}) {
    speech = FakeSpeechTranscriber();
    permission = FakeMicrophonePermission();
    recorder = FakeVoiceRecorder();
    final c = ProviderContainer(
      overrides: [
        speechTranscriberProvider.overrideWithValue(speech),
        microphonePermissionProvider.overrideWithValue(permission),
        voiceRecorderProvider.overrideWithValue(recorder),
        dictationAllowsNetworkProvider.overrideWithValue(allowNetwork),
      ],
    );
    c.listen(dictationControllerProvider, (_, _) {});
    return c;
  }

  DictationState st(ProviderContainer c) => c.read(dictationControllerProvider);
  DictationController ctl(ProviderContainer c) =>
      c.read(dictationControllerProvider.notifier);

  test('joinTranscript', () {
    expect(joinTranscript('', ''), '');
    expect(joinTranscript(' a ', ''), 'a');
    expect(joinTranscript('', 'b'), 'b');
    expect(joinTranscript('a', ' b'), 'a b');
  });

  test('partials replace each other; final is committed', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      expect(st(c).phase, DictationPhase.listening);
      expect(speech.calls, ['start:id-ID']);

      speech.partial('beli');
      expect(st(c).partial, 'beli');
      speech.partial('beli susu');
      expect(st(c).partial, 'beli susu');
      expect(st(c).text, 'beli susu');
      speech.finalResult('beli susu dan roti');
      expect(st(c).committed, 'beli susu dan roti');
      expect(st(c).partial, '');
      c.dispose();
    });
  });

  test(
    'restarts after Android ends the session; accumulates across sessions',
    () {
      fakeAsync((fa) {
        final c = makeContainer();
        ctl(c).start();
        fa.flushMicrotasks();

        speech.partial('satu');
        speech.finalResult('satu');
        speech.endSession(); // silence timeout
        expect(st(c).phase, DictationPhase.restarting);
        fa.elapse(DictationController.restartDelay);
        expect(speech.starts, 2);
        expect(st(c).phase, DictationPhase.listening);

        speech.partial('dua');
        // Session ends without a final result → partial is committed.
        speech.endSession();
        expect(st(c).committed, 'satu dua');
        fa.elapse(DictationController.restartDelay);
        expect(speech.starts, 3);

        // The new session's result counts.
        speech.finalResult('tiga');
        expect(st(c).text, 'satu dua tiga');
        c.dispose();
      });
    },
  );

  test('late duplicate final after the session ended is ignored', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      speech.finalResult('halo');
      speech.finalResult('halo'); // plugin's finalTimeout duplicate
      expect(st(c).committed, 'halo');
      c.dispose();
    });
  });

  test('stop waits for the final result and returns the full text', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      speech.finalResult('pertama');
      speech.endSession();
      fa.elapse(DictationController.restartDelay);
      speech.partial('kedua ya');

      String? out;
      ctl(c).stop().then((t) => out = t);
      fa.flushMicrotasks();
      // FakeSpeechTranscriber.stop ends the session (no final) → partial kept.
      expect(out, 'pertama kedua ya');
      expect(st(c).phase, DictationPhase.idle);
      expect(fa.pendingTimers, isEmpty);

      expect(ctl(c).takeText(), 'pertama kedua ya');
      expect(st(c).text, '');
      c.dispose();
    });
  });

  test('stop times out when the recognizer never answers', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      speech.partial('menggantung');
      speech.listening = false; // stop() will not emit anything
      String? out;
      ctl(c).stop().then((t) => out = t);
      fa.flushMicrotasks();
      expect(out, isNull);
      expect(st(c).phase, DictationPhase.stopping);
      fa.elapse(DictationController.finalizeTimeout);
      expect(out, 'menggantung');
      expect(st(c).phase, DictationPhase.idle);
      c.dispose();
    });
  });

  test('transient errors restart; too many silent sessions stop dictation', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      for (var i = 0; i < DictationController.maxSilentSessions - 1; i++) {
        speech.error(SpeechErrorKind.noMatch);
        speech.endSession(); // error + done for the same session → counted once
        fa.elapse(DictationController.restartDelay);
      }
      expect(speech.starts, DictationController.maxSilentSessions);
      expect(st(c).phase, DictationPhase.listening);

      speech.error(SpeechErrorKind.speechTimeout);
      fa.elapse(DictationController.restartDelay);
      expect(st(c).phase, DictationPhase.idle);
      expect(speech.starts, DictationController.maxSilentSessions);
      c.dispose();
    });
  });

  test('words reset the silent-session counter', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      for (var round = 0; round < 3; round++) {
        speech.error(SpeechErrorKind.noMatch);
        fa.elapse(DictationController.restartDelay);
        speech.error(SpeechErrorKind.noMatch);
        fa.elapse(DictationController.restartDelay);
        speech.finalResult('kata $round');
        speech.endSession();
        fa.elapse(DictationController.restartDelay);
      }
      expect(st(c).phase, DictationPhase.listening);
      expect(st(c).committed, 'kata 0 kata 1 kata 2');
      c.dispose();
    });
  });

  test('fatal error stops with error and keeps the text', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      speech.partial('sebagian');
      speech.error(SpeechErrorKind.network, permanent: true);
      expect(st(c).phase, DictationPhase.error);
      expect(st(c).error!.kind, SpeechErrorKind.network);
      expect(st(c).committed, 'sebagian');
      fa.elapse(const Duration(seconds: 5));
      expect(speech.starts, 1);
      c.dispose();
    });
  });

  test(
    'offline model missing and network not allowed → unavailable + hint',
    () {
      fakeAsync((fa) {
        final c = makeContainer();
        speech.available = const SpeechAvailability(
          recognizerAvailable: true,
          offline: OfflineSpeechSupport.downloadable,
        );
        bool? ok;
        ctl(c).start().then((v) => ok = v);
        fa.flushMicrotasks();
        expect(ok, isFalse);
        expect(st(c).phase, DictationPhase.unavailable);
        expect(st(c).hint, contains('Unduh'));
        expect(speech.starts, 0);

        ctl(c).downloadOfflineModel();
        fa.flushMicrotasks();
        expect(speech.calls, contains('download:id-ID'));
        c.dispose();
      });
    },
  );

  test('network allowed → dictation may start without offline model', () {
    fakeAsync((fa) {
      final c = makeContainer(allowNetwork: true);
      speech.available = const SpeechAvailability(
        recognizerAvailable: true,
        offline: OfflineSpeechSupport.unsupported,
      );
      ctl(c).start();
      fa.flushMicrotasks();
      expect(st(c).phase, DictationPhase.listening);
      c.dispose();
    });
  });

  test('permission denied → error, recognizer not started', () {
    fakeAsync((fa) {
      final c = makeContainer();
      permission
        ..current = MicPermissionStatus.denied
        ..afterRequest = MicPermissionStatus.denied;
      ctl(c).start();
      fa.flushMicrotasks();
      expect(st(c).phase, DictationPhase.error);
      expect(st(c).error!.kind, SpeechErrorKind.permission);
      expect(st(c).permission, MicPermissionStatus.denied);
      expect(speech.starts, 0);
      c.dispose();
    });
  });

  test('start failure from the recognizer → error', () {
    fakeAsync((fa) {
      final c = makeContainer();
      speech.startError = const SpeechError(
        SpeechErrorKind.languageUnavailable,
        permanent: true,
      );
      ctl(c).start();
      fa.flushMicrotasks();
      expect(st(c).phase, DictationPhase.error);
      expect(st(c).error!.kind, SpeechErrorKind.languageUnavailable);
      c.dispose();
    });
  });

  test('cancel drops the live partial and keeps committed text', () {
    fakeAsync((fa) {
      final c = makeContainer();
      ctl(c).start();
      fa.flushMicrotasks();
      speech.finalResult('simpan');
      speech.endSession();
      fa.elapse(DictationController.restartDelay);
      speech.partial('buang');
      ctl(c).cancel();
      fa.flushMicrotasks();
      expect(st(c).phase, DictationPhase.idle);
      expect(st(c).text, 'simpan');
      fa.elapse(const Duration(seconds: 5));
      expect(fa.pendingTimers, isEmpty);
      c.dispose();
    });
  });

  test('dictation stops an active voice recording first', () {
    fakeAsync((fa) {
      final c = makeContainer();
      c.listen(voiceRecorderControllerProvider, (_, _) {});
      c.read(voiceRecorderControllerProvider.notifier).start();
      fa.flushMicrotasks();
      expect(c.read(voiceRecorderControllerProvider).isRecording, isTrue);

      ctl(c).start();
      fa.flushMicrotasks();
      expect(recorder.calls, ['start', 'stop']);
      expect(c.read(voiceRecorderControllerProvider).isRecording, isFalse);
      expect(st(c).phase, DictationPhase.listening);
      c.dispose();
    });
  });
}
