import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps photos taken offline (food logs, transactions) until they are uploaded.
abstract interface class PhotoStore {
  /// Copies [sourcePath] into app storage; returns the stored file path.
  Future<String> importPhoto(String sourcePath, String id);

  /// Transaction photos: returns [path] when it is already in app storage, else
  /// copies it there (picked files may live in a temp dir) and returns the copy.
  Future<String> ensureStored(String path, String id);

  /// Deletes a stored file (no-op when missing / null).
  Future<void> delete(String? path);
}

/// Stores photos under `<app documents>/food_photos/` and `…/tx_photos/`.
final class FilePhotoStore implements PhotoStore {
  static var _seq = 0;

  @override
  Future<String> importPhoto(String sourcePath, String id) =>
      _copy(sourcePath, id, 'food_photos');

  @override
  Future<String> ensureStored(String path, String id) async {
    final dir = p.join(
      (await getApplicationDocumentsDirectory()).path,
      'tx_photos',
    );
    if (p.isWithin(dir, path)) return path;
    return _copy(path, id, 'tx_photos');
  }

  Future<String> _copy(String sourcePath, String id, String folder) async {
    final dir = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, folder),
    );
    await dir.create(recursive: true);
    final ext = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    final target = p.join(
      dir.path,
      '${id}_${DateTime.now().millisecondsSinceEpoch}_${_seq++}$ext',
    );
    await File(sourcePath).copy(target);
    return target;
  }

  @override
  Future<void> delete(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // best effort
    }
  }
}

/// Test double: keeps the source path, deletes nothing.
final class InMemoryPhotoStore implements PhotoStore {
  final deleted = <String>[];

  @override
  Future<String> importPhoto(String sourcePath, String id) async => sourcePath;

  @override
  Future<String> ensureStored(String path, String id) async => path;

  @override
  Future<void> delete(String? path) async {
    if (path != null) deleted.add(path);
  }
}
