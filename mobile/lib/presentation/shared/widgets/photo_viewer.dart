import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/config.dart';
import '../../design_system/design_system.dart';

/// One photo to show: a device file (taken offline, not uploaded yet) or a
/// server image (`/uploads/x.jpg` or an absolute URL, resolved with
/// [AppConfig.resolveUrl]). Feature-agnostic: transactions, food logs, …
@immutable
final class ViewerPhoto {
  const ViewerPhoto.file(String this.filePath) : url = null;
  const ViewerPhoto.network(String this.url) : filePath = null;

  final String? filePath;

  /// Raw server path/URL as stored (resolved only when displayed).
  final String? url;

  /// Local file = still waiting for upload.
  bool get isLocal => filePath != null;

  ImageProvider? get provider {
    if (filePath case final p?) return FileImage(File(p));
    final u = AppConfig.resolveUrl(url);
    return u == null ? null : NetworkImage(u);
  }

  String get _id => filePath ?? url ?? '';

  /// Hero tag shared by a thumbnail and the viewer page ([scope] keeps two
  /// strips of the same photos on one screen apart).
  String heroTag(String scope) => 'photo:$scope:$_id';

  @override
  bool operator ==(Object other) =>
      other is ViewerPhoto && other.filePath == filePath && other.url == url;

  @override
  int get hashCode => Object.hash(filePath, url);

  @override
  String toString() => 'ViewerPhoto(${filePath ?? url})';
}

/// The image of a [ViewerPhoto] with a soft loading state and a friendly
/// "broken photo" placeholder when it can't be read/downloaded.
class PhotoImage extends StatelessWidget {
  const PhotoImage({
    super.key,
    required this.photo,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.large = false,
  });

  final ViewerPhoto photo;
  final BoxFit fit;

  /// Decode size for thumbnails (physical pixels).
  final int? cacheWidth;

  /// Viewer mode: bigger placeholder with a caption, light-on-dark.
  final bool large;

  @override
  Widget build(BuildContext context) {
    var provider = photo.provider;
    if (provider == null) return _PhotoError(large: large);
    if (cacheWidth != null) {
      provider = ResizeImage(
        provider,
        width: cacheWidth,
        policy: ResizeImagePolicy.fit,
      );
    }
    return Image(
      image: provider,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => _PhotoError(large: large),
      frameBuilder: (context, child, frame, sync) {
        if (sync || frame != null) return child;
        return large
            ? const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white70,
                  ),
                ),
              )
            : ColoredBox(color: context.ghina.surfaceAlt);
      },
    );
  }
}

class _PhotoError extends StatelessWidget {
  const _PhotoError({required this.large});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    if (!large) {
      return ColoredBox(
        color: g.surfaceAlt,
        child: Center(
          child: Icon(Icons.broken_image_rounded, color: g.textMuted, size: 22),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_rounded,
            color: Colors.white54,
            size: 64,
          ),
          const SizedBox(height: GhinaSpace.md),
          Text(
            'Fotonya nggak bisa dibuka',
            textAlign: TextAlign.center,
            style: GhinaType.h3.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Cek koneksi internetmu, lalu coba lagi.',
            textAlign: TextAlign.center,
            style: GhinaType.bodyS.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

/// Opens [photos] full screen at [initialIndex]: swipe between photos, pinch
/// (or double-tap) to zoom, "2/4" counter, close button. Thumbnails wrapped in
/// a `Hero(tag: photo.heroTag(heroScope))` fly into place.
Future<void> showPhotoViewer(
  BuildContext context,
  List<ViewerPhoto> photos, {
  int initialIndex = 0,
  String heroScope = 'default',
}) {
  if (photos.isEmpty) return Future.value();
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => PhotoViewer(
        photos: photos,
        initialIndex: initialIndex.clamp(0, photos.length - 1),
        heroScope: heroScope,
      ),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

/// Full-screen photo pager. Usually opened with [showPhotoViewer].
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({
    super.key,
    required this.photos,
    this.initialIndex = 0,
    this.heroScope = 'default',
  });

  final List<ViewerPhoto> photos;
  final int initialIndex;
  final String heroScope;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    final current = photos[_index];
    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              key: const ValueKey('photo-viewer-pages'),
              controller: _pages,
              physics: _zoomed
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: photos.length,
              onPageChanged: (i) => setState(() {
                _index = i;
                _zoomed = false;
              }),
              itemBuilder: (_, i) => _ZoomablePhoto(
                key: ValueKey('photo-page-$i'),
                photo: photos[i],
                heroTag: photos[i].heroTag(widget.heroScope),
                onZoomChanged: (z) {
                  if (z != _zoomed) setState(() => _zoomed = z);
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: GhinaSpace.sm,
                  vertical: GhinaSpace.xs,
                ),
                child: Row(
                  children: [
                    _RoundButton(
                      key: const ValueKey('photo-viewer-close'),
                      icon: Icons.close_rounded,
                      tooltip: 'Tutup',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    if (photos.length > 1)
                      _Pill(
                        key: const ValueKey('photo-viewer-counter'),
                        text: '${_index + 1}/${photos.length}',
                      ),
                    const Spacer(),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
            ),
            if (current.isLocal)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: GhinaSpace.lg),
                    child: Center(
                      child: _Pill(
                        icon: Icons.cloud_upload_rounded,
                        text: 'Belum diunggah · nanti disinkron otomatis',
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    super.key,
    required this.photo,
    required this.heroTag,
    required this.onZoomChanged,
  });

  final ViewerPhoto photo;
  final String heroTag;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  final _ctrl = TransformationController();
  late final AnimationController _anim;
  Matrix4Tween? _tween;
  TapDownDetails? _doubleTap;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() => _ctrl.value = _tween!.evaluate(_anim));
  }

  @override
  void dispose() {
    _anim.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isZoomed => _ctrl.value.getMaxScaleOnAxis() > 1.01;

  void _toggleZoom() {
    final Matrix4 end;
    if (_isZoomed) {
      end = Matrix4.identity();
    } else {
      final p = _doubleTap?.localPosition ?? Offset.zero;
      const s = 2.5;
      end = Matrix4.identity()
        ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
    _tween = Matrix4Tween(begin: _ctrl.value, end: end);
    _anim.forward(from: 0);
    widget.onZoomChanged(end.getMaxScaleOnAxis() > 1.01);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTap = d,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _ctrl,
        minScale: 1,
        maxScale: 5,
        onInteractionEnd: (_) => widget.onZoomChanged(_isZoomed),
        child: SizedBox.expand(
          child: Hero(
            tag: widget.heroTag,
            child: PhotoImage(
              photo: widget.photo,
              fit: BoxFit.contain,
              large: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    child: Material(
      color: Colors.white.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: GhinaRadii.rPill,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.body.w(800).copyWith(color: Colors.white),
          ),
        ),
      ],
    ),
  );
}
