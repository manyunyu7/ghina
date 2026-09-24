import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/platform/fakes.dart';
import 'package:ghina/domain/services/share_intake.dart';
import 'package:ghina/presentation/state/platform/platform_state.dart';

void main() {
  test('queues shares FIFO; take() pops and exposes the next', () {
    final intake = FakeShareIntake();
    final c = ProviderContainer(
      overrides: [shareIntakeProvider.overrideWithValue(intake)],
    );
    addTearDown(c.dispose);
    final seen = <SharedPayload?>[];
    c.listen<SharedPayload?>(
      pendingShareProvider,
      (_, next) => seen.add(next),
      fireImmediately: true,
    );
    expect(seen, [null]);

    final a = SharedPayload.normalize(texts: ['a https://a.id']);
    final b = SharedPayload.normalize(texts: ['b']);
    intake.share(a);
    intake.share(b);
    intake.share(const SharedPayload()); // empty → ignored
    expect(c.read(pendingShareProvider), a);
    expect(c.read(pendingShareProvider.notifier).pendingCount, 2);

    expect(c.read(pendingShareProvider.notifier).take(), a);
    expect(c.read(pendingShareProvider), b);
    expect(c.read(pendingShareProvider.notifier).take(), b);
    expect(c.read(pendingShareProvider), isNull);
    expect(c.read(pendingShareProvider.notifier).take(), isNull);

    intake.share(a);
    c.read(pendingShareProvider.notifier).clear();
    expect(c.read(pendingShareProvider), isNull);
  });

  test('default (flutter test) intake is a no-op', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(pendingShareProvider), isNull);
    expect(c.read(shareIntakeProvider), isA<NoopShareIntake>());
    expect(c.read(voiceRecorderProvider), isA<NoopVoiceRecorder>());
    expect(c.read(speechTranscriberProvider), isA<NoopSpeechTranscriber>());
    expect(c.read(audioPlaybackProvider), isA<NoopAudioPlayback>());
    expect(
      c.read(microphonePermissionProvider),
      isA<NoopMicrophonePermission>(),
    );
  });
}
