import 'dart:async';

import 'package:flutter/services.dart';

/// Dart side of the small native bridge in
/// `android/app/src/main/kotlin/com/henryaugusta/ghina/MainActivity.kt`
/// (Android only; every call degrades to a safe default elsewhere).
///
/// Methods on [methodChannelName]:
/// * `share.initial` → always null (reserved; see below)
/// * `app.openSettings` → `bool`
/// * `mic.shouldShowRationale` → `bool`
/// * `speech.support` `{locale}` → `Map` (see [SpeechSupportInfo])
/// * `speech.downloadModel` `{locale}` → `bool`
///
/// Events on [shareEventChannelName]: every share map — the one that
/// cold-started the app and those received while running. The activity queues
/// them until Dart listens, so nothing is lost before the UI is ready.
///
/// Share map: `{subject: String?, texts: List<String>, images: List<String>}`
/// where images are absolute paths of copies in the app cache dir.
class PlatformBridge {
  PlatformBridge({MethodChannel? methods, EventChannel? shareEvents})
    : _methods = methods ?? const MethodChannel(methodChannelName),
      _shareEvents = shareEvents ?? const EventChannel(shareEventChannelName);

  static const methodChannelName = 'com.henryaugusta.ghina/platform';
  static const shareEventChannelName = 'com.henryaugusta.ghina/share';

  final MethodChannel _methods;
  final EventChannel _shareEvents;

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _methods.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<Map<Object?, Object?>?> initialShare() =>
      _call<Map<Object?, Object?>>('share.initial');

  Stream<Map<Object?, Object?>> shareEvents() => _shareEvents
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .cast<Map<Object?, Object?>>()
      .handleError((Object _) {}, test: (e) => e is MissingPluginException);

  Future<bool> openAppSettings() async =>
      await _call<bool>('app.openSettings') ?? false;

  Future<bool> shouldShowMicRationale() async =>
      await _call<bool>('mic.shouldShowRationale') ?? false;

  Future<SpeechSupportInfo?> speechSupport(String locale) async {
    final m = await _call<Map<Object?, Object?>>('speech.support', {
      'locale': locale,
    }).timeout(const Duration(seconds: 4), onTimeout: () => null);
    return m == null ? null : SpeechSupportInfo.fromMap(m);
  }

  Future<bool> downloadSpeechModel(String locale) async =>
      await _call<bool>('speech.downloadModel', {'locale': locale}) ?? false;
}

/// Raw result of `speech.support`. Language lists are BCP-47 tags as reported
/// by the recognizer; `null` = the recognizer could not answer.
final class SpeechSupportInfo {
  const SpeechSupportInfo({
    required this.sdkInt,
    required this.recognitionAvailable,
    required this.onDeviceAvailable,
    this.defaultService,
    this.onDeviceService,
  });

  factory SpeechSupportInfo.fromMap(Map<Object?, Object?> m) =>
      SpeechSupportInfo(
        sdkInt: (m['sdkInt'] as num?)?.toInt() ?? 0,
        recognitionAvailable: m['recognitionAvailable'] == true,
        onDeviceAvailable: m['onDeviceAvailable'] == true,
        defaultService: RecognizerLanguages.maybe(m['defaultService']),
        onDeviceService: RecognizerLanguages.maybe(m['onDeviceService']),
      );

  final int sdkInt;

  /// `SpeechRecognizer.isRecognitionAvailable`.
  final bool recognitionAvailable;

  /// `SpeechRecognizer.isOnDeviceRecognitionAvailable` (API 31+).
  final bool onDeviceAvailable;

  /// `checkRecognitionSupport` of the default recognizer (API 33+).
  final RecognizerLanguages? defaultService;

  /// `checkRecognitionSupport` of the on-device recognizer (API 33+).
  final RecognizerLanguages? onDeviceService;
}

final class RecognizerLanguages {
  const RecognizerLanguages({
    this.installed = const [],
    this.pending = const [],
    this.supported = const [],
    this.online = const [],
  });

  static RecognizerLanguages? maybe(Object? o) {
    if (o is! Map) return null;
    List<String> l(String k) =>
        (o[k] as List?)?.whereType<String>().toList() ?? const [];
    return RecognizerLanguages(
      installed: l('installed'),
      pending: l('pending'),
      supported: l('supported'),
      online: l('online'),
    );
  }

  /// On-device installed.
  final List<String> installed;

  /// On-device download scheduled/in progress.
  final List<String> pending;

  /// On-device supported (downloadable).
  final List<String> supported;

  /// Network recognition.
  final List<String> online;
}
