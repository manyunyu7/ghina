import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../domain/services/speech_transcriber.dart';
import 'platform_bridge.dart';

/// [SpeechTranscriber] with `speech_to_text` (Android `SpeechRecognizer`, iOS
/// `SFSpeechRecognizer`). The offline readiness check uses the native bridge
/// (`SpeechRecognizer.checkRecognitionSupport`, Android 13+) because the plugin
/// can't report it without prompting for permission.
final class SttSpeechTranscriber implements SpeechTranscriber {
  SttSpeechTranscriber({SpeechToText? speech, PlatformBridge? bridge})
    : _stt = speech ?? SpeechToText(),
      _bridge = bridge ?? PlatformBridge();

  final SpeechToText _stt;
  final PlatformBridge _bridge;
  bool _initialized = false;
  SpeechSupportInfo? _support;
  String? _supportLocale;

  final _results = StreamController<TranscriptUpdate>.broadcast();
  final _status = StreamController<SpeechSessionStatus>.broadcast();
  final _errors = StreamController<SpeechError>.broadcast();
  final _levels = StreamController<double>.broadcast();

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  @override
  Stream<TranscriptUpdate> get results => _results.stream;
  @override
  Stream<SpeechSessionStatus> get status => _status.stream;
  @override
  Stream<SpeechError> get errors => _errors.stream;
  @override
  Stream<double> get levels => _levels.stream;

  @override
  bool get isListening => _stt.isListening;

  Future<SpeechSupportInfo?> _supportFor(String locale) async {
    if (!_isAndroid) return null;
    if (_support == null || _supportLocale != locale) {
      _support = await _bridge.speechSupport(locale);
      _supportLocale = locale;
    }
    return _support;
  }

  @override
  Future<SpeechAvailability> availability({
    String locale = kDefaultSpeechLocale,
  }) async {
    if (!_isAndroid) {
      // iOS: SFSpeechRecognizer exists on every supported iOS version; whether
      // id-ID runs on-device can only be known after authorisation.
      return const SpeechAvailability(
        recognizerAvailable: true,
        offline: OfflineSpeechSupport.unknown,
      );
    }
    _support = null; // re-query: the user may have installed a pack meanwhile
    return availabilityFromSupport(await _supportFor(locale), locale);
  }

  @override
  Future<bool> requestOfflineModel({
    String locale = kDefaultSpeechLocale,
  }) async {
    if (!_isAndroid) return false;
    _support = null;
    return _bridge.downloadSpeechModel(locale);
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    final ok = await _stt.initialize(
      onStatus: (s) {
        final mapped = switch (s) {
          SpeechToText.listeningStatus => SpeechSessionStatus.listening,
          SpeechToText.notListeningStatus => SpeechSessionStatus.notListening,
          SpeechToText.doneStatus || 'doneNoResult' => SpeechSessionStatus.done,
          _ => null,
        };
        if (mapped != null && !_status.isClosed) _status.add(mapped);
      },
      onError: (SpeechRecognitionError e) {
        if (!_errors.isClosed) {
          _errors.add(
            SpeechError(
              mapSpeechErrorCode(e.errorMsg),
              permanent: e.permanent,
              raw: e.errorMsg,
            ),
          );
        }
      },
    );
    if (!ok) {
      final perm = await _stt.hasPermission;
      throw SpeechError(
        perm ? SpeechErrorKind.other : SpeechErrorKind.permission,
        permanent: true,
        raw: perm ? 'recognizer_unavailable' : 'permission_denied',
      );
    }
    _initialized = true;
  }

  @override
  Future<void> start({
    String locale = kDefaultSpeechLocale,
    bool preferOffline = true,
  }) async {
    await _ensureInitialized();
    final support = preferOffline ? await _supportFor(locale) : null;
    // Only force the dedicated on-device service when it really has the
    // language — otherwise it fails with "language unavailable" while the
    // default recognizer (Google app, may have an offline pack) would work.
    final onDevice =
        preferOffline &&
        support != null &&
        support.onDeviceAvailable &&
        (support.onDeviceService?.installed.any(
              (t) => localeMatches(t, locale),
            ) ??
            false);
    try {
      await _stt.listen(
        onResult: (SpeechRecognitionResult r) {
          if (_results.isClosed) return;
          _results.add(
            TranscriptUpdate(
              r.recognizedWords,
              isFinal: r.finalResult,
              confidence: r.hasConfidenceRating ? r.confidence : null,
            ),
          );
        },
        onSoundLevelChange: (level) {
          if (!_levels.isClosed) _levels.add(normalizeSoundLevel(level));
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          onDevice: onDevice,
          listenMode: ListenMode.dictation,
          cancelOnError: false,
          localeId: locale,
          // Android caps silence at a few seconds anyway; the dictation
          // controller restarts sessions for continuous dictation.
          pauseFor: const Duration(seconds: 5),
          listenFor: const Duration(minutes: 1),
        ),
      );
    } on ListenFailedException catch (e) {
      throw SpeechError(mapSpeechErrorCode(e.message ?? ''), raw: e.message);
    }
  }

  @override
  Future<void> stop() => _stt.stop();

  @override
  Future<void> cancel() => _stt.cancel();

  @override
  Future<void> dispose() async {
    try {
      await _stt.cancel();
    } catch (_) {}
    await _results.close();
    await _status.close();
    await _errors.close();
    await _levels.close();
  }
}

/// Android reports RMS dB roughly in -2..10; iOS a dB-ish level. → 0..1.
double normalizeSoundLevel(double level) =>
    ((level + 2) / 12).clamp(0.0, 1.0).toDouble();

/// Maps `speech_to_text` / Android `SpeechRecognizer` error codes.
SpeechErrorKind mapSpeechErrorCode(String code) {
  final c = code.toLowerCase();
  if (c.contains('no_match')) return SpeechErrorKind.noMatch;
  if (c.contains('speech_timeout')) return SpeechErrorKind.speechTimeout;
  if (c.contains('busy') || c.contains('too_many')) return SpeechErrorKind.busy;
  if (c.contains('network') || c.contains('server')) {
    return SpeechErrorKind.network;
  }
  if (c.contains('language')) return SpeechErrorKind.languageUnavailable;
  if (c.contains('permission')) return SpeechErrorKind.permission;
  if (c.contains('audio')) return SpeechErrorKind.audio;
  return SpeechErrorKind.other;
}

/// Loose BCP-47 match: `id-ID` ≈ `id_ID` ≈ `in-ID` (Android's legacy code for
/// Indonesian) ≈ `id` (language-only entries).
bool localeMatches(String tag, String wanted) {
  List<String> parts(String s) {
    final p = s.replaceAll('_', '-').toLowerCase().split('-');
    if (p.first == 'in') p[0] = 'id';
    return p;
  }

  final a = parts(tag), b = parts(wanted);
  if (a.first != b.first) return false;
  if (a.length < 2 || b.length < 2) return true;
  return a[1] == b[1];
}

/// Pure mapping of the native support report to [SpeechAvailability].
SpeechAvailability availabilityFromSupport(
  SpeechSupportInfo? info,
  String locale,
) {
  if (info == null) {
    return const SpeechAvailability(
      recognizerAvailable: true,
      offline: OfflineSpeechSupport.unknown,
    );
  }
  if (!info.recognitionAvailable && !info.onDeviceAvailable) {
    return SpeechAvailability(
      recognizerAvailable: false,
      offline: OfflineSpeechSupport.unsupported,
      sdkInt: info.sdkInt,
    );
  }
  bool has(List<String> l) => l.any((t) => localeMatches(t, locale));
  final services = [info.onDeviceService, info.defaultService]
      .whereType<RecognizerLanguages>()
      .where(
        (s) =>
            s.installed.isNotEmpty ||
            s.pending.isNotEmpty ||
            s.supported.isNotEmpty ||
            s.online.isNotEmpty,
      );
  OfflineSpeechSupport offline;
  bool? listed;
  if (services.isEmpty) {
    offline = OfflineSpeechSupport.unknown;
  } else if (services.any((s) => has(s.installed))) {
    offline = OfflineSpeechSupport.installed;
    listed = true;
  } else if (services.any((s) => has(s.pending) || has(s.supported))) {
    offline = OfflineSpeechSupport.downloadable;
    listed = true;
  } else {
    offline = OfflineSpeechSupport.unsupported;
    listed = services.any((s) => has(s.online));
  }
  return SpeechAvailability(
    recognizerAvailable: true,
    offline: offline,
    localeListed: listed,
    onDeviceService: info.onDeviceAvailable,
    sdkInt: info.sdkInt,
  );
}
