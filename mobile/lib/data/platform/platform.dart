/// Device services for notes: voice recording/playback, dictation, share
/// target, microphone permission. See `README.md` in this folder.
///
/// The `create*` factories return the production implementation on Android/iOS
/// and a no-op elsewhere (including under `flutter test`).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/services/audio_playback.dart';
import '../../domain/services/microphone_permission.dart';
import '../../domain/services/share_intake.dart';
import '../../domain/services/speech_transcriber.dart';
import '../../domain/services/voice_recorder.dart';
import 'channel_share_intake.dart';
import 'device_microphone_permission.dart';
import 'fakes.dart';
import 'just_audio_playback.dart';
import 'record_voice_recorder.dart';
import 'stt_speech_transcriber.dart';

export 'fakes.dart';

bool get _isTest => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

/// Android or iOS device (not web, not `flutter test`).
bool get isMobileDevice =>
    !kIsWeb &&
    !_isTest &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

bool get _isAndroid =>
    isMobileDevice && defaultTargetPlatform == TargetPlatform.android;

VoiceRecorder createVoiceRecorder() =>
    isMobileDevice ? RecordVoiceRecorder() : const NoopVoiceRecorder();

AudioPlayback createAudioPlayback() =>
    isMobileDevice ? JustAudioPlayback() : const NoopAudioPlayback();

SpeechTranscriber createSpeechTranscriber() =>
    isMobileDevice ? SttSpeechTranscriber() : const NoopSpeechTranscriber();

MicrophonePermission createMicrophonePermission() => isMobileDevice
    ? DeviceMicrophonePermission()
    : const NoopMicrophonePermission();

/// Android only (iOS share extension is out of scope for v1).
ShareIntake createShareIntake() =>
    _isAndroid ? ChannelShareIntake() : const NoopShareIntake();
