import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/ids.dart';
import '../../domain/services/voice_recorder.dart';

/// Encoder settings for voice notes: AAC-LC in .m4a, mono, 64 kbps, 44.1 kHz.
///
/// Why 44.1 kHz rather than 16 kHz: every Android AAC encoder (incl. the
/// MediaTek ones in Infinix/Tecno phones) supports 44.1 kHz, while low rates are
/// occasionally renegotiated or rejected; 64 kbps mono at 44.1 kHz sounds
/// natural on playback, and any future server-side ASR resamples to 16 kHz
/// losslessly for the speech band. 10 min ≈ 4.8 MB.
const voiceNoteRecordConfig = RecordConfig(
  encoder: AudioEncoder.aacLc,
  bitRate: 64000,
  sampleRate: 44100,
  numChannels: 1,
  // Voice memos: let the platform clean up the signal a bit.
  autoGain: true,
  noiseSuppress: true,
  androidConfig: AndroidRecordConfig(
    audioSource: AndroidAudioSource.mic,
    // Don't force Bluetooth SCO (drops quality to 8/16 kHz and adds latency).
    manageBluetooth: false,
  ),
);

/// Maps a dBFS amplitude (-160..0) to 0..1 for a waveform, with [floor] dB
/// treated as silence.
double normalizeDbfs(double db, {double floor = -50}) {
  if (db.isNaN || db <= floor) return 0;
  if (db >= 0) return 1;
  return (db - floor) / -floor;
}

/// Directory for voice clips: `<app documents>/voice/` (persistent, not temp).
Future<Directory> voiceNotesDirectory() async {
  final dir = Directory(
    p.join((await getApplicationDocumentsDirectory()).path, 'voice'),
  );
  await dir.create(recursive: true);
  return dir;
}

/// [VoiceRecorder] on top of the `record` plugin.
final class RecordVoiceRecorder implements VoiceRecorder {
  RecordVoiceRecorder({
    AudioRecorder Function()? createRecorder,
    Future<Directory> Function()? directory,
    this.config = voiceNoteRecordConfig,
    this.amplitudeInterval = const Duration(milliseconds: 80),
  }) : _createRecorder = createRecorder ?? AudioRecorder.new,
       _directory = directory ?? voiceNotesDirectory;

  final AudioRecorder Function() _createRecorder;
  final Future<Directory> Function() _directory;
  final RecordConfig config;
  final Duration amplitudeInterval;

  AudioRecorder? _recorder;
  String? _path;
  final _stopwatch = Stopwatch();
  StreamSubscription<Amplitude>? _ampSub;
  StreamSubscription<RecordState>? _stateSub;
  final _levels = StreamController<double>.broadcast();

  AudioRecorder get _rec => _recorder ??= _createRecorder();

  @override
  bool get isSupported => true;

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<void> start() async {
    if (_path != null) {
      throw const VoiceRecorderException(
        VoiceRecorderErrorKind.busy,
        'already recording',
      );
    }
    final bool granted;
    try {
      granted = await _rec.hasPermission(request: false);
    } catch (e) {
      throw VoiceRecorderException(VoiceRecorderErrorKind.unsupported, '$e');
    }
    if (!granted) {
      throw const VoiceRecorderException(VoiceRecorderErrorKind.permission);
    }
    final path = p.join((await _directory()).path, '${newId()}.m4a');
    _path = path;
    try {
      await _rec.start(config, path: path);
    } catch (e) {
      _path = null;
      await _deleteQuietly(path);
      final msg = '$e';
      final busy = RegExp(
        'busy|in use|already|AudioRecord|startRecording',
        caseSensitive: false,
      ).hasMatch(msg);
      throw VoiceRecorderException(
        busy ? VoiceRecorderErrorKind.busy : VoiceRecorderErrorKind.failed,
        msg,
      );
    }
    _stopwatch
      ..reset()
      ..start();
    _ampSub = _rec
        .onAmplitudeChanged(amplitudeInterval)
        .listen(
          (a) => _levels.add(normalizeDbfs(a.current)),
          onError: (Object _) {},
        );
    // Phone calls etc. pause the recorder (AudioInterruptionMode.pause): keep
    // the measured duration honest.
    _stateSub = _rec.onStateChanged().listen((s) {
      if (s == RecordState.pause) _stopwatch.stop();
      if (s == RecordState.record && _path != null) _stopwatch.start();
    }, onError: (Object _) {});
  }

  @override
  Future<VoiceRecording?> stop() async {
    final path = _path;
    if (path == null) return null;
    _path = null;
    await _ampSub?.cancel();
    _ampSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    String? out;
    try {
      out = await _rec.stop();
    } catch (_) {
      out = null;
    }
    _stopwatch.stop();
    final file = File(out ?? path);
    final size = await file.exists() ? await file.length() : 0;
    // An AAC/MP4 file with only headers is < 1 KB — treat as no recording.
    if (size < 1024 || _stopwatch.elapsed < const Duration(milliseconds: 300)) {
      await _deleteQuietly(file.path);
      return null;
    }
    return VoiceRecording(
      path: file.path,
      duration: _stopwatch.elapsed,
      sizeBytes: size,
    );
  }

  @override
  Future<void> cancel() async {
    final path = _path;
    if (path == null) return;
    _path = null;
    await _ampSub?.cancel();
    _ampSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    _stopwatch.stop();
    try {
      await _rec.cancel();
    } catch (_) {}
    await _deleteQuietly(path);
  }

  @override
  Future<void> deleteFile(String path) => _deleteQuietly(path);

  @override
  Future<void> dispose() async {
    await cancel();
    await _recorder?.dispose();
    _recorder = null;
    await _levels.close();
  }
}

Future<void> _deleteQuietly(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {
    // best effort
  }
}
