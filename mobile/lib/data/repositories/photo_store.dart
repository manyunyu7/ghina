import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps food photos taken offline until they are uploaded.
abstract interface class PhotoStore {
  /// Copies [sourcePath] into app storage; returns the stored file path.
  Future<String> importPhoto(String sourcePath, String id);

  /// Deletes a stored file (no-op when missing / null).
  Future<void> delete(String? path);
}

/// Stores photos under `<app documents>/food_photos/`.
final class FilePhotoStore implements PhotoStore {
  @override
  Future<String> importPhoto(String sourcePath, String id) async {
    final dir = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'food_photos'),
    );
    await dir.create(recursive: true);
    final ext = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    final target = p.join(
      dir.path,
      '${id}_${DateTime.now().millisecondsSinceEpoch}$ext',
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
  Future<void> delete(String? path) async {
    if (path != null) deleted.add(path);
  }
}
