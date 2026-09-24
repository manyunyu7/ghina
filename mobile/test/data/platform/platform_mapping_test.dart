import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/data/platform/just_audio_playback.dart';
import 'package:ghina/data/platform/platform_bridge.dart';
import 'package:ghina/data/platform/record_voice_recorder.dart';
import 'package:ghina/data/platform/stt_speech_transcriber.dart';
import 'package:ghina/domain/services/services.dart';
import 'package:just_audio/just_audio.dart';

SpeechSupportInfo info({
  bool available = true,
  bool onDevice = false,
  RecognizerLanguages? def,
  RecognizerLanguages? dev,
}) => SpeechSupportInfo(
  sdkInt: 34,
  recognitionAvailable: available,
  onDeviceAvailable: onDevice,
  defaultService: def,
  onDeviceService: dev,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('localeMatches handles id/in, _ and language-only tags', () {
    expect(localeMatches('id-ID', 'id-ID'), isTrue);
    expect(localeMatches('id_ID', 'id-ID'), isTrue);
    expect(localeMatches('in-ID', 'id-ID'), isTrue);
    expect(localeMatches('id', 'id-ID'), isTrue);
    expect(localeMatches('en-US', 'id-ID'), isFalse);
    expect(localeMatches('id-SG', 'id-ID'), isFalse);
  });

  group('availabilityFromSupport', () {
    test('no bridge answer → unknown (best effort)', () {
      final a = availabilityFromSupport(null, 'id-ID');
      expect(a.recognizerAvailable, isTrue);
      expect(a.offline, OfflineSpeechSupport.unknown);
      expect(a.canDictate(allowNetwork: false), isTrue);
      expect(a.hint, isNotNull);
    });

    test('no recognizer at all', () {
      final a = availabilityFromSupport(info(available: false), 'id-ID');
      expect(a.recognizerAvailable, isFalse);
      expect(a.canDictate(allowNetwork: true), isFalse);
      expect(a.hint, contains('tidak punya'));
    });

    test('Android < 13 / recognizer without support query → unknown', () {
      final a = availabilityFromSupport(
        info(def: const RecognizerLanguages()),
        'id-ID',
      );
      expect(a.offline, OfflineSpeechSupport.unknown);
    });

    test('installed in the default (Google) recognizer', () {
      final a = availabilityFromSupport(
        info(def: const RecognizerLanguages(installed: ['in-ID', 'en-US'])),
        'id-ID',
      );
      expect(a.offline, OfflineSpeechSupport.installed);
      expect(a.offlineReady, isTrue);
      expect(a.hint, isNull);
    });

    test('downloadable / pending', () {
      final a = availabilityFromSupport(
        info(
          onDevice: true,
          dev: const RecognizerLanguages(
            installed: ['en-US'],
            supported: ['id-ID'],
          ),
        ),
        'id-ID',
      );
      expect(a.offline, OfflineSpeechSupport.downloadable);
      expect(a.onDeviceService, isTrue);
      expect(a.canDictate(allowNetwork: false), isFalse);
      expect(a.canDictate(allowNetwork: true), isTrue);
      final b = availabilityFromSupport(
        info(def: const RecognizerLanguages(pending: ['id-ID'])),
        'id-ID',
      );
      expect(b.offline, OfflineSpeechSupport.downloadable);
    });

    test('online only', () {
      final a = availabilityFromSupport(
        info(
          def: const RecognizerLanguages(
            installed: ['en-US'],
            online: ['id-ID'],
          ),
        ),
        'id-ID',
      );
      expect(a.offline, OfflineSpeechSupport.unsupported);
      expect(a.localeListed, isTrue);
      expect(a.canDictate(allowNetwork: false), isFalse);
      expect(a.canDictate(allowNetwork: true), isTrue);
    });
  });

  test('mapSpeechErrorCode', () {
    expect(mapSpeechErrorCode('error_no_match'), SpeechErrorKind.noMatch);
    expect(
      mapSpeechErrorCode('error_speech_timeout'),
      SpeechErrorKind.speechTimeout,
    );
    expect(mapSpeechErrorCode('error_busy'), SpeechErrorKind.busy);
    expect(mapSpeechErrorCode('error_network'), SpeechErrorKind.network);
    expect(
      mapSpeechErrorCode('error_server_disconnected'),
      SpeechErrorKind.network,
    );
    expect(
      mapSpeechErrorCode('error_language_unavailable'),
      SpeechErrorKind.languageUnavailable,
    );
    expect(
      mapSpeechErrorCode('error_insufficient_permissions'),
      SpeechErrorKind.permission,
    );
    expect(mapSpeechErrorCode('error_audio_error'), SpeechErrorKind.audio);
    expect(mapSpeechErrorCode('weird'), SpeechErrorKind.other);
    expect(SpeechErrorKind.noMatch.isTransient, isTrue);
    expect(SpeechErrorKind.network.isTransient, isFalse);
  });

  test('level normalisation', () {
    expect(normalizeDbfs(-160), 0);
    expect(normalizeDbfs(-50), 0);
    expect(normalizeDbfs(-25), 0.5);
    expect(normalizeDbfs(0), 1);
    expect(normalizeDbfs(double.nan), 0);
    expect(normalizeSoundLevel(-10), 0);
    expect(normalizeSoundLevel(4), 0.5);
    expect(normalizeSoundLevel(20), 1);
  });

  test('voice note encoder config matches the spec', () {
    expect(voiceNoteRecordConfig.numChannels, 1);
    expect(voiceNoteRecordConfig.bitRate, 64000);
    expect(voiceNoteRecordConfig.sampleRate, 44100);
  });

  test('mapPlayerState', () {
    expect(mapPlayerState(false, ProcessingState.idle), PlaybackStatus.idle);
    expect(
      mapPlayerState(false, ProcessingState.loading),
      PlaybackStatus.loading,
    );
    expect(
      mapPlayerState(true, ProcessingState.buffering),
      PlaybackStatus.playing,
    );
    expect(mapPlayerState(false, ProcessingState.ready), PlaybackStatus.ready);
    expect(mapPlayerState(true, ProcessingState.ready), PlaybackStatus.playing);
    expect(
      mapPlayerState(true, ProcessingState.completed),
      PlaybackStatus.completed,
    );
  });

  group('PlatformBridge', () {
    const channel = MethodChannel(PlatformBridge.methodChannelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('parses speech.support', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'speech.support');
        expect(call.arguments, {'locale': 'id-ID'});
        return {
          'sdkInt': 34,
          'recognitionAvailable': true,
          'onDeviceAvailable': false,
          'defaultService': {
            'installed': ['id-ID'],
            'pending': <String>[],
            'supported': ['id-ID', 'en-US'],
            'online': ['id-ID'],
          },
        };
      });
      final s = await PlatformBridge().speechSupport('id-ID');
      expect(s!.sdkInt, 34);
      expect(s.defaultService!.installed, ['id-ID']);
      expect(s.onDeviceService, isNull);
      expect(
        availabilityFromSupport(s, 'id-ID').offline,
        OfflineSpeechSupport.installed,
      );
    });

    test('missing plugin / platform errors degrade to defaults', () async {
      final b = PlatformBridge();
      expect(await b.speechSupport('id-ID'), isNull);
      expect(await b.openAppSettings(), isFalse);
      expect(await b.shouldShowMicRationale(), isFalse);
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'x');
      });
      expect(await b.downloadSpeechModel('id-ID'), isFalse);
    });
  });

  test('SpeechAvailability hints are Indonesian and mode-specific', () {
    for (final o in OfflineSpeechSupport.values) {
      final a = SpeechAvailability(recognizerAvailable: true, offline: o);
      if (o == OfflineSpeechSupport.installed) {
        expect(a.hint, isNull);
      } else {
        expect(a.hint, isNotEmpty);
      }
    }
  });
}
