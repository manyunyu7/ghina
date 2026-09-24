/// Live speech-to-text ("Dikte") — on-device recognizer, `id-ID` by default.
///
/// IMPORTANT UX contract (see `lib/data/platform/README.md`): a transcriber
/// session owns the microphone. It cannot run at the same time as
/// [VoiceRecorder] on Android, and neither plugin can transcribe an existing
/// audio file. So "Rekam suara" (audio clip) and "Dikte" (text) are two separate
/// modes. The continuous-dictation logic (auto-restart after Android's silence
/// timeout, partial → final accumulation) lives in
/// `presentation/state/platform/dictation_controller.dart`.
library;

const kDefaultSpeechLocale = 'id-ID';

/// Offline readiness of the requested locale.
enum OfflineSpeechSupport {
  /// The locale's offline model is installed → recognition works without
  /// internet and audio never leaves the device.
  installed,

  /// Supported offline but not downloaded yet (or downloading) — see
  /// [SpeechTranscriber.requestOfflineModel].
  downloadable,

  /// The device has no offline model for this locale → needs internet
  /// (Google's network recognizer) or is not possible.
  unsupported,

  /// The OS can't tell (Android < 13, or the recognizer doesn't implement the
  /// support query — common on non-Pixel devices). Recognition may still work
  /// offline if the user installed the language pack in the Google app.
  unknown,
}

final class SpeechAvailability {
  const SpeechAvailability({
    required this.recognizerAvailable,
    required this.offline,
    this.localeListed,
    this.onDeviceService = false,
    this.sdkInt,
  });

  static const unavailable = SpeechAvailability(
    recognizerAvailable: false,
    offline: OfflineSpeechSupport.unsupported,
  );

  /// Some speech recognition service exists on the device.
  final bool recognizerAvailable;

  final OfflineSpeechSupport offline;

  /// Whether the locale is in the recognizer's language list (null = unknown).
  final bool? localeListed;

  /// Android 12+ dedicated on-device recognizer service present (Pixel-style).
  final bool onDeviceService;

  /// Android API level (null elsewhere).
  final int? sdkInt;

  bool get offlineReady => offline == OfflineSpeechSupport.installed;

  /// Whether dictation may start. With `allowNetwork == false` only
  /// [OfflineSpeechSupport.installed] and [OfflineSpeechSupport.unknown]
  /// (best effort) qualify.
  bool canDictate({required bool allowNetwork}) {
    if (!recognizerAvailable) return false;
    if (localeListed == false && offline != OfflineSpeechSupport.installed) {
      return allowNetwork;
    }
    return switch (offline) {
      OfflineSpeechSupport.installed || OfflineSpeechSupport.unknown => true,
      OfflineSpeechSupport.downloadable ||
      OfflineSpeechSupport.unsupported => allowNetwork,
    };
  }

  /// Short Indonesian hint for the UI (null when all good).
  String? get hint {
    if (!recognizerAvailable) {
      return 'Perangkat ini tidak punya layanan pengenalan suara. '
          'Rekaman suara tetap bisa dipakai.';
    }
    return switch (offline) {
      OfflineSpeechSupport.installed => null,
      OfflineSpeechSupport.downloadable =>
        'Paket suara Bahasa Indonesia offline belum terpasang. '
            'Unduh dulu agar dikte bisa tanpa internet.',
      OfflineSpeechSupport.unsupported =>
        'Dikte offline Bahasa Indonesia tidak tersedia di perangkat ini. '
            'Rekaman suara tetap disimpan tanpa transkrip.',
      OfflineSpeechSupport.unknown =>
        'Dikte memakai layanan suara perangkat. Agar bisa offline, pasang '
            'paket "Bahasa Indonesia" di Google › Pengenalan ucapan offline.',
    };
  }

  @override
  String toString() =>
      'SpeechAvailability(recognizer: $recognizerAvailable, offline: $offline, '
      'listed: $localeListed, onDeviceService: $onDeviceService, sdk: $sdkInt)';
}

/// One recognition result. Within one listen session partial results are
/// cumulative (each replaces the previous one); a final result closes the
/// session's utterance.
final class TranscriptUpdate {
  const TranscriptUpdate(this.text, {required this.isFinal, this.confidence});

  final String text;
  final bool isFinal;

  /// 0..1 when the engine reports it.
  final double? confidence;

  @override
  String toString() =>
      'TranscriptUpdate(${isFinal ? 'final' : 'partial'}: "$text")';
}

enum SpeechSessionStatus {
  listening,

  /// Mic released (silence timeout, stop, cancel, error).
  notListening,

  /// All results of the session delivered.
  done,
}

enum SpeechErrorKind {
  /// Nothing recognised / silence — harmless, just restart.
  noMatch,
  speechTimeout,
  busy,
  network,
  languageUnavailable,
  permission,
  audio,
  other;

  /// Continuous dictation simply starts a new session on these.
  bool get isTransient => this == noMatch || this == speechTimeout;
}

final class SpeechError {
  const SpeechError(this.kind, {this.permanent = false, this.raw});

  final SpeechErrorKind kind;
  final bool permanent;

  /// Platform error code (e.g. `error_no_match`).
  final String? raw;

  @override
  String toString() => 'SpeechError($kind, permanent: $permanent, raw: $raw)';
}

abstract interface class SpeechTranscriber {
  /// Readiness for [locale]. Never prompts; never throws.
  Future<SpeechAvailability> availability({
    String locale = kDefaultSpeechLocale,
  });

  /// Asks the OS to download the offline model for [locale] (Android 13+).
  /// Returns false when not possible here (then point the user to the Google
  /// app's offline speech settings).
  Future<bool> requestOfflineModel({String locale = kDefaultSpeechLocale});

  /// Starts one listen session (may prompt for mic/speech permission on first
  /// use). Android ends a session by itself after a few seconds of silence —
  /// watch [status]. Throws [SpeechError] when it can't start.
  Future<void> start({
    String locale = kDefaultSpeechLocale,
    bool preferOffline = true,
  });

  /// Ends the session and delivers the final result.
  Future<void> stop();

  /// Ends the session and drops pending results.
  Future<void> cancel();

  bool get isListening;

  /// Partial and final results, in order. Broadcast.
  Stream<TranscriptUpdate> get results;

  Stream<SpeechSessionStatus> get status;
  Stream<SpeechError> get errors;

  /// Input level 0..1 while listening (for a small mic animation). Broadcast.
  Stream<double> get levels;

  Future<void> dispose();
}

extension SpeechTranscriberStreams on SpeechTranscriber {
  Stream<String> get partialResults =>
      results.where((r) => !r.isFinal).map((r) => r.text);

  Stream<String> get finalResults =>
      results.where((r) => r.isFinal).map((r) => r.text);
}
