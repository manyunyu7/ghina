/// No-op implementations (unsupported platforms, `flutter test` defaults) and
/// controllable fakes for widget/controller tests.
library;

import 'dart:async';

import '../../domain/services/audio_playback.dart';
import '../../domain/services/microphone_permission.dart';
import '../../domain/services/share_intake.dart';
import '../../domain/services/speech_transcriber.dart';
import '../../domain/services/voice_recorder.dart';

// --- no-ops -------------------------------------------------------------------

final class NoopMicrophonePermission implements MicrophonePermission {
  const NoopMicrophonePermission();
  @override
  Future<MicPermissionStatus> status() async => MicPermissionStatus.unsupported;
  @override
  Future<MicPermissionStatus> request() async =>
      MicPermissionStatus.unsupported;
  @override
  Future<bool> openAppSettings() async => false;
}

final class NoopVoiceRecorder implements VoiceRecorder {
  const NoopVoiceRecorder();
  @override
  bool get isSupported => false;
  @override
  Future<void> start() async =>
      throw const VoiceRecorderException(VoiceRecorderErrorKind.unsupported);
  @override
  Future<VoiceRecording?> stop() async => null;
  @override
  Future<void> cancel() async {}
  @override
  Stream<double> get levels => const Stream.empty();
  @override
  Future<void> deleteFile(String path) async {}
  @override
  Future<void> dispose() async {}
}

final class NoopAudioPlayback implements AudioPlayback {
  const NoopAudioPlayback();
  @override
  Future<Duration?> loadFile(String path) async => null;
  @override
  Future<Duration?> loadUrl(String url, {Map<String, String>? headers}) async =>
      null;
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stop() async {}
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration?> get duration => const Stream.empty();
  @override
  Stream<PlaybackStatus> get status => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

final class NoopSpeechTranscriber implements SpeechTranscriber {
  const NoopSpeechTranscriber();
  @override
  Future<SpeechAvailability> availability({
    String locale = kDefaultSpeechLocale,
  }) async => SpeechAvailability.unavailable;
  @override
  Future<bool> requestOfflineModel({
    String locale = kDefaultSpeechLocale,
  }) async => false;
  @override
  Future<void> start({
    String locale = kDefaultSpeechLocale,
    bool preferOffline = true,
  }) async => throw const SpeechError(SpeechErrorKind.other, permanent: true);
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
  @override
  bool get isListening => false;
  @override
  Stream<TranscriptUpdate> get results => const Stream.empty();
  @override
  Stream<SpeechSessionStatus> get status => const Stream.empty();
  @override
  Stream<SpeechError> get errors => const Stream.empty();
  @override
  Stream<double> get levels => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

final class NoopShareIntake implements ShareIntake {
  const NoopShareIntake();
  @override
  Stream<SharedPayload> get payloads => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

// --- fakes --------------------------------------------------------------------

final class FakeMicrophonePermission implements MicrophonePermission {
  FakeMicrophonePermission([this.current = MicPermissionStatus.granted]);

  MicPermissionStatus current;

  /// What [request] turns [current] into (null = unchanged).
  MicPermissionStatus? afterRequest;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<MicPermissionStatus> status() async => current;
  @override
  Future<MicPermissionStatus> request() async {
    requests++;
    if (afterRequest != null) current = afterRequest!;
    return current;
  }

  @override
  Future<bool> openAppSettings() async {
    settingsOpened++;
    return true;
  }
}

/// Records calls; [stop] returns a clip whose duration is [durationOf]'s value.
final class FakeVoiceRecorder implements VoiceRecorder {
  FakeVoiceRecorder({this.durationOf});

  /// Supplies the duration of the clip returned by [stop].
  Duration Function()? durationOf;

  /// When set, [start] throws it.
  VoiceRecorderException? startError;

  /// Completes [start] only when this completes (simulates a slow start).
  Completer<void>? startGate;

  final calls = <String>[];
  final deleted = <String>[];
  bool recording = false;
  var _n = 0;
  final _levels = StreamController<double>.broadcast();

  void emitLevel(double v) => _levels.add(v);

  @override
  bool get isSupported => true;

  @override
  Future<void> start() async {
    calls.add('start');
    if (startGate != null) await startGate!.future;
    if (startError != null) throw startError!;
    recording = true;
  }

  @override
  Future<VoiceRecording?> stop() async {
    calls.add('stop');
    if (!recording) return null;
    recording = false;
    return VoiceRecording(
      path: '/fake/voice/${_n++}.m4a',
      duration: durationOf?.call() ?? const Duration(seconds: 1),
      sizeBytes: 4096,
    );
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
    recording = false;
  }

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<void> deleteFile(String path) async => deleted.add(path);

  @override
  Future<void> dispose() async => _levels.close();
}

/// Scriptable transcriber: push results/status/errors from the test.
final class FakeSpeechTranscriber implements SpeechTranscriber {
  FakeSpeechTranscriber({
    this.available = const SpeechAvailability(
      recognizerAvailable: true,
      offline: OfflineSpeechSupport.installed,
    ),
  });

  SpeechAvailability available;
  SpeechError? startError;
  final calls = <String>[];
  bool listening = false;

  final _results = StreamController<TranscriptUpdate>.broadcast(sync: true);
  final _status = StreamController<SpeechSessionStatus>.broadcast(sync: true);
  final _errors = StreamController<SpeechError>.broadcast(sync: true);
  final _levels = StreamController<double>.broadcast(sync: true);

  int get starts => calls.where((c) => c.startsWith('start')).length;

  void partial(String text) =>
      _results.add(TranscriptUpdate(text, isFinal: false));
  void finalResult(String text) =>
      _results.add(TranscriptUpdate(text, isFinal: true));

  /// Ends the current session like Android does after silence.
  void endSession() {
    listening = false;
    _status
      ..add(SpeechSessionStatus.notListening)
      ..add(SpeechSessionStatus.done);
  }

  void error(SpeechErrorKind kind, {bool permanent = false}) {
    _errors.add(SpeechError(kind, permanent: permanent));
  }

  @override
  Future<SpeechAvailability> availability({
    String locale = kDefaultSpeechLocale,
  }) async => available;

  @override
  Future<bool> requestOfflineModel({
    String locale = kDefaultSpeechLocale,
  }) async {
    calls.add('download:$locale');
    return true;
  }

  @override
  Future<void> start({
    String locale = kDefaultSpeechLocale,
    bool preferOffline = true,
  }) async {
    calls.add('start:$locale');
    if (startError != null) throw startError!;
    listening = true;
    _status.add(SpeechSessionStatus.listening);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    if (listening) endSession();
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
    if (listening) endSession();
  }

  @override
  bool get isListening => listening;
  @override
  Stream<TranscriptUpdate> get results => _results.stream;
  @override
  Stream<SpeechSessionStatus> get status => _status.stream;
  @override
  Stream<SpeechError> get errors => _errors.stream;
  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<void> dispose() async {
    await _results.close();
    await _status.close();
    await _errors.close();
    await _levels.close();
  }
}

final class FakeShareIntake implements ShareIntake {
  final _c = StreamController<SharedPayload>.broadcast(sync: true);

  void share(SharedPayload p) => _c.add(p);

  @override
  Stream<SharedPayload> get payloads => _c.stream;

  @override
  Future<void> dispose() => _c.close();
}
