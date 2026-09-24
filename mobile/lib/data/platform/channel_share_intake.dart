import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/ids.dart';
import '../../domain/services/share_intake.dart';
import 'platform_bridge.dart';

/// Directory for shared images: `<app documents>/shared_images/`.
Future<Directory> sharedImagesDirectory() async {
  final dir = Directory(
    p.join((await getApplicationDocumentsDirectory()).path, 'shared_images'),
  );
  await dir.create(recursive: true);
  return dir;
}

/// [ShareIntake] over the native bridge in `MainActivity.kt` (Android
/// `ACTION_SEND` / `ACTION_SEND_MULTIPLE` for `text/*` and `image/*`).
///
/// The activity copies shared `content://` images into its cache dir (the
/// grant expires with the intent); this class moves them into app documents
/// and normalises the payload.
final class ChannelShareIntake implements ShareIntake {
  ChannelShareIntake({
    PlatformBridge? bridge,
    Future<Directory> Function()? imagesDirectory,
  }) : _bridge = bridge ?? PlatformBridge(),
       _imagesDirectory = imagesDirectory ?? sharedImagesDirectory {
    _controller = StreamController<SharedPayload>.broadcast(
      onListen: _onFirstListen,
    );
  }

  final PlatformBridge _bridge;
  final Future<Directory> Function() _imagesDirectory;
  late final StreamController<SharedPayload> _controller;
  StreamSubscription<Map<Object?, Object?>>? _eventsSub;
  bool _started = false;

  @override
  Stream<SharedPayload> get payloads => _controller.stream;

  void _onFirstListen() {
    if (_started) return;
    _started = true;
    // The activity queues every share (incl. the one that cold-started the
    // app) until this stream is listened to.
    _eventsSub = _bridge.shareEvents().listen(_handle, onError: (Object _) {});
  }

  Future<void> _handle(Map<Object?, Object?> raw) async {
    final payload = await payloadFromRaw(raw, _imagesDirectory);
    if (!payload.isEmpty && !_controller.isClosed) _controller.add(payload);
  }

  @override
  Future<void> dispose() async {
    await _eventsSub?.cancel();
    await _controller.close();
  }
}

/// Parses the bridge's share map, moves images into [imagesDirectory] and
/// normalises the result.
Future<SharedPayload> payloadFromRaw(
  Map<Object?, Object?> raw,
  Future<Directory> Function() imagesDirectory,
) async {
  final subject = raw['subject'] as String?;
  final texts = (raw['texts'] as List?)?.whereType<String>().toList() ?? [];
  final sources = (raw['images'] as List?)?.whereType<String>().toList() ?? [];
  final stored = <String>[];
  if (sources.isNotEmpty) {
    final dir = await imagesDirectory();
    for (final src in sources.take(kMaxSharedImages)) {
      final f = File(src);
      if (!await f.exists()) continue;
      final ext = p.extension(src).isEmpty ? '.jpg' : p.extension(src);
      final target = p.join(dir.path, '${newId()}$ext');
      try {
        await f.rename(target);
      } on FileSystemException {
        await f.copy(target);
        try {
          await f.delete();
        } catch (_) {}
      }
      stored.add(target);
    }
  }
  return SharedPayload.normalize(
    subject: subject,
    texts: texts,
    imagePaths: stored,
  );
}
