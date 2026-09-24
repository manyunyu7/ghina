import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../design_system/design_system.dart';
import 'feedback.dart';
import 'photo_viewer.dart';

// ---------------------------------------------------------------- picking

enum PhotoSource { camera, gallery }

/// Why picking failed.
final class PhotoPickerException implements Exception {
  const PhotoPickerException(this.source, {required this.denied});
  final PhotoSource source;

  /// The user refused the camera/photos permission.
  final bool denied;
}

/// Picks compressed photos (≤ 1600 px wide, JPEG ~80, the server takes ≤ 5 MB)
/// and returns their file paths. Override [photoPickerProvider] in tests.
abstract interface class PhotoPicker {
  /// Empty when cancelled. Throws [PhotoPickerException].
  Future<List<String>> pick(PhotoSource source, {required int limit});
}

final class ImagePickerPhotoPicker implements PhotoPicker {
  const ImagePickerPhotoPicker();

  @override
  Future<List<String>> pick(PhotoSource source, {required int limit}) async {
    if (limit < 1) return const [];
    final picker = ImagePicker();
    try {
      if (source == PhotoSource.camera) {
        final x = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          imageQuality: 80,
        );
        return x == null ? const [] : [x.path];
      }
      if (limit == 1) {
        final x = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          imageQuality: 80,
        );
        return x == null ? const [] : [x.path];
      }
      final xs = await picker.pickMultiImage(
        maxWidth: 1600,
        imageQuality: 80,
        limit: limit,
      );
      return [for (final x in xs) x.path];
    } on PlatformException catch (e) {
      throw PhotoPickerException(
        source,
        denied: e.code.contains('denied') || e.code.contains('permission'),
      );
    }
  }
}

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => const ImagePickerPhotoPicker(),
);

/// Friendly message for a picker failure (with how to enable the permission).
String photoPickerErrorMessage(PhotoPickerException e) {
  final cam = e.source == PhotoSource.camera;
  if (e.denied) {
    return cam
        ? 'Izin kamera ditolak. Aktifkan di Pengaturan HP → Ghina → Kamera, ya.'
        : 'Izin foto ditolak. Aktifkan di Pengaturan HP → Ghina → Foto, ya.';
  }
  return cam
      ? 'Nggak bisa buka kamera. Cek izin kamera di pengaturan HP, ya.'
      : 'Nggak bisa buka galeri. Cek izin foto di pengaturan HP, ya.';
}

String maxPhotosMessage(int max) =>
    'Maksimal $max foto, ya. Hapus satu dulu kalau mau ganti.';

/// Runs the picker for [source] with at most [remaining] photos. Shows a toast
/// on failure/limit and returns the picked paths (maybe empty).
Future<List<String>> pickPhotosFrom(
  BuildContext context,
  WidgetRef ref,
  PhotoSource source, {
  required int remaining,
  int max = 5,
}) async {
  if (remaining < 1) {
    showErrorToast(context, maxPhotosMessage(max));
    return const [];
  }
  try {
    final paths = await ref
        .read(photoPickerProvider)
        .pick(source, limit: remaining);
    if (paths.length > remaining) {
      if (context.mounted) {
        showErrorToast(
          context,
          'Cuma $remaining foto yang masuk. Maksimal $max foto, ya.',
        );
      }
      return paths.sublist(0, remaining);
    }
    return paths;
  } on PhotoPickerException catch (e) {
    if (context.mounted) showErrorToast(context, photoPickerErrorMessage(e));
    return const [];
  }
}

/// "Kamera / Galeri" chooser, then [pickPhotosFrom].
Future<List<String>> pickPhotos(
  BuildContext context,
  WidgetRef ref, {
  required int remaining,
  int max = 5,
}) async {
  if (remaining < 1) {
    showErrorToast(context, maxPhotosMessage(max));
    return const [];
  }
  final source = await showChunkyBottomSheet<PhotoSource>(
    context,
    title: 'Tambah foto',
    builder: (c) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [PhotoSourceTiles(onPick: (s) => Navigator.of(c).pop(s))],
    ),
  );
  if (source == null || !context.mounted) return const [];
  return pickPhotosFrom(context, ref, source, remaining: remaining, max: max);
}

/// The two "Kamera" / "Galeri" tiles.
class PhotoSourceTiles extends StatelessWidget {
  const PhotoSourceTiles({
    super.key,
    required this.onPick,
    this.enabled = true,
  });

  final ValueChanged<PhotoSource>? onPick;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget tile(PhotoSource s) {
      final cam = s == PhotoSource.camera;
      return Expanded(
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: ChunkyCard(
            key: ValueKey('photo-source-${s.name}'),
            onTap: enabled && onPick != null ? () => onPick!(s) : null,
            padding: const EdgeInsets.symmetric(
              horizontal: GhinaSpace.sm,
              vertical: GhinaSpace.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CategoryAvatar(
                  icon: cam
                      ? Icons.photo_camera_rounded
                      : Icons.photo_library_rounded,
                  color: cam ? GhinaColors.orange.base : GhinaColors.blue.base,
                  size: 44,
                ),
                const SizedBox(height: 6),
                Text(
                  cam ? 'Kamera' : 'Galeri',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.body
                      .w(800)
                      .copyWith(color: context.ghina.textPrimary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile(PhotoSource.camera),
        const SizedBox(width: GhinaSpace.md),
        tile(PhotoSource.gallery),
      ],
    );
  }
}

// ---------------------------------------------------------------- thumbnails

/// A rounded square thumbnail: tap to open, optional remove "×", and a small
/// cloud badge while the photo waits for upload.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({
    super.key,
    required this.photo,
    this.size = 64,
    this.onTap,
    this.onRemove,
    this.heroTag,
  });

  final ViewerPhoto photo;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget image = PhotoImage(photo: photo, cacheWidth: (size * dpr).round());
    if (heroTag != null) image = Hero(tag: heroTag!, child: image);
    return SizedBox(
      width: size + 6,
      height: size + 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            width: size,
            height: size,
            child: Semantics(
              button: onTap != null,
              image: true,
              label: 'Foto',
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: GhinaRadii.rMd,
                    border: Border.all(
                      color: g.border,
                      width: GhinaDepth.border,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: image,
                  ),
                ),
              ),
            ),
          ),
          if (photo.isLocal)
            Positioned(
              left: 4,
              bottom: 4,
              child: Semantics(
                label: 'Belum diunggah',
                child: Container(
                  key: const ValueKey('photo-pending'),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: GhinaColors.blue.base,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.cloud_upload_rounded,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (onRemove != null)
            Positioned(
              right: -4,
              top: -4,
              child: Semantics(
                button: true,
                label: 'Hapus foto',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRemove,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: GhinaColors.red.base,
                        shape: BoxShape.circle,
                        border: Border.all(color: g.surface, width: 2),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Horizontal row of [PhotoThumb]s (tap → [showPhotoViewer]) with an optional
/// dashed "+" tile while below [max].
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({
    super.key,
    required this.photos,
    this.onRemove,
    this.onAdd,
    this.max = 5,
    this.size = 64,
    this.heroScope = 'strip',
  });

  final List<ViewerPhoto> photos;
  final ValueChanged<int>? onRemove;
  final VoidCallback? onAdd;
  final int max;
  final double size;
  final String heroScope;

  @override
  Widget build(BuildContext context) {
    final canAdd = onAdd != null && photos.length < max;
    return SizedBox(
      height: size + 6,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.zero,
        children: [
          for (var i = 0; i < photos.length; i++) ...[
            if (i > 0) const SizedBox(width: GhinaSpace.sm),
            PhotoThumb(
              key: ValueKey('photo-thumb-$i'),
              photo: photos[i],
              size: size,
              heroTag: photos[i].heroTag(heroScope),
              onTap: () => showPhotoViewer(
                context,
                photos,
                initialIndex: i,
                heroScope: heroScope,
              ),
              onRemove: onRemove == null ? null : () => onRemove!(i),
            ),
          ],
          if (canAdd) ...[
            if (photos.isNotEmpty) const SizedBox(width: GhinaSpace.sm),
            Align(
              alignment: Alignment.bottomLeft,
              child: _AddTile(size: size, onTap: onAdd!),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Semantics(
      button: true,
      label: 'Tambah foto',
      child: GestureDetector(
        key: const ValueKey('photo-add'),
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: g.surfaceAlt,
            borderRadius: GhinaRadii.rMd,
            border: Border.all(color: g.border, width: GhinaDepth.border),
          ),
          child: Icon(
            Icons.add_a_photo_rounded,
            color: g.textSecondary,
            size: size * 0.4,
          ),
        ),
      ),
    );
  }
}

/// Small "📷 3" pill for list rows; tap opens the photos.
class PhotoCountBadge extends StatelessWidget {
  const PhotoCountBadge({super.key, required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sw = GhinaColors.blue;
    final g = context.ghina;
    return Semantics(
      button: onTap != null,
      label: '$count foto',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: sw.tint(g.brightness),
              borderRadius: GhinaRadii.rPill,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_camera_rounded, size: 13, color: sw.base),
                const SizedBox(width: 3),
                Text(
                  '$count',
                  style: GhinaType.caption
                      .w(900)
                      .copyWith(color: sw.base, height: 1.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- attach sheet

/// Sheet to manage a photo list: current thumbnails (remove / open), Kamera and
/// Galeri (multi-select) while below [max]. [onChanged] fires after every change
/// so the caller stays in sync even if the sheet is swiped away.
Future<void> showPhotoAttachSheet(
  BuildContext context, {
  required List<ViewerPhoto> photos,
  required ValueChanged<List<ViewerPhoto>> onChanged,
  int max = 5,
  String title = 'Foto',
  String hint = 'Struk, nota, atau bukti transfer.',
}) => showChunkyBottomSheet<void>(
  context,
  title: title,
  showClose: true,
  builder: (_) => PhotoAttachSheet(
    photos: photos,
    onChanged: onChanged,
    max: max,
    hint: hint,
  ),
);

class PhotoAttachSheet extends ConsumerStatefulWidget {
  const PhotoAttachSheet({
    super.key,
    required this.photos,
    required this.onChanged,
    this.max = 5,
    this.hint = '',
  });

  final List<ViewerPhoto> photos;
  final ValueChanged<List<ViewerPhoto>> onChanged;
  final int max;
  final String hint;

  @override
  ConsumerState<PhotoAttachSheet> createState() => _PhotoAttachSheetState();
}

class _PhotoAttachSheetState extends ConsumerState<PhotoAttachSheet> {
  late List<ViewerPhoto> _photos = [...widget.photos];
  bool _busy = false;

  bool get _full => _photos.length >= widget.max;

  void _set(List<ViewerPhoto> next) {
    setState(() => _photos = next);
    widget.onChanged(List.unmodifiable(next));
  }

  Future<void> _pick(PhotoSource s) async {
    if (_busy) return;
    _busy = true;
    try {
      final paths = await pickPhotosFrom(
        context,
        ref,
        s,
        remaining: widget.max - _photos.length,
        max: widget.max,
      );
      if (!mounted || paths.isEmpty) return;
      final next = [..._photos];
      for (final p in paths) {
        final ph = ViewerPhoto.file(p);
        if (!next.contains(ph)) next.add(ph);
      }
      _set(next);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.hint,
                style: GhinaType.bodyS.copyWith(color: g.textSecondary),
              ),
            ),
            const SizedBox(width: GhinaSpace.sm),
            Text(
              '${_photos.length}/${widget.max}',
              key: const ValueKey('photo-count'),
              style: GhinaType.body
                  .w(900)
                  .copyWith(
                    color: _full ? GhinaColors.orange.base : g.textSecondary,
                  ),
            ),
          ],
        ),
        const SizedBox(height: GhinaSpace.md),
        if (_photos.isNotEmpty) ...[
          PhotoStrip(
            photos: _photos,
            size: 72,
            heroScope: 'attach',
            onRemove: (i) => _set([..._photos]..removeAt(i)),
          ),
          const SizedBox(height: GhinaSpace.md),
        ],
        if (_full)
          ChunkyCard(
            key: const ValueKey('photo-full'),
            tinted: GhinaColors.orange,
            padding: const EdgeInsets.all(GhinaSpace.md),
            child: Row(
              children: [
                Icon(Icons.info_rounded, color: GhinaColors.orange.base),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Udah ${widget.max} foto, itu maksimalnya. '
                    'Hapus satu kalau mau ganti.',
                    style: GhinaType.bodyS.copyWith(color: g.textPrimary),
                  ),
                ),
              ],
            ),
          )
        else
          PhotoSourceTiles(onPick: _pick),
        const SizedBox(height: GhinaSpace.lg),
        ChunkyButton(
          key: const ValueKey('photo-done'),
          label: 'Selesai',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
