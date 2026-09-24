import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../domain/services/microphone_permission.dart';
import 'platform_bridge.dart';

/// Uses `record`'s permission request (Android `RECORD_AUDIO`, iOS microphone
/// prompt) and the native bridge to tell "denied" from "don't ask again".
final class DeviceMicrophonePermission implements MicrophonePermission {
  DeviceMicrophonePermission({AudioRecorder? recorder, PlatformBridge? bridge})
    : _injected = recorder,
      _bridge = bridge ?? PlatformBridge();

  final AudioRecorder? _injected;
  AudioRecorder? _recorder;
  final PlatformBridge _bridge;
  bool _permanentlyDenied = false;

  AudioRecorder get _rec => _recorder ??= _injected ?? AudioRecorder();

  @override
  Future<MicPermissionStatus> status() async {
    try {
      if (await _rec.hasPermission(request: false)) {
        _permanentlyDenied = false;
        return MicPermissionStatus.granted;
      }
    } catch (_) {
      return MicPermissionStatus.unsupported;
    }
    return _permanentlyDenied
        ? MicPermissionStatus.permanentlyDenied
        : MicPermissionStatus.denied;
  }

  @override
  Future<MicPermissionStatus> request() async {
    try {
      if (await _rec.hasPermission()) {
        _permanentlyDenied = false;
        return MicPermissionStatus.granted;
      }
    } catch (_) {
      return MicPermissionStatus.unsupported;
    }
    // Android: right after a denial, "no rationale" means "don't ask again"
    // (the prompt is not shown any more). iOS only ever asks once.
    _permanentlyDenied = defaultTargetPlatform == TargetPlatform.iOS
        ? true
        : !await _bridge.shouldShowMicRationale();
    return _permanentlyDenied
        ? MicPermissionStatus.permanentlyDenied
        : MicPermissionStatus.denied;
  }

  @override
  Future<bool> openAppSettings() => _bridge.openAppSettings();
}
