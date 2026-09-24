import 'package:flutter/material.dart';

import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';

/// Colors of a note card / editor background for a palette id (null = the
/// default neutral card). Light mode uses the palette's pale shade, dark mode
/// its deep shade (same ids as the web).
@immutable
final class NoteTone {
  const NoteTone({
    required this.face,
    required this.edge,
    required this.border,
    required this.text,
    required this.subtle,
    required this.isDefault,
  });

  factory NoteTone.of(BuildContext context, String? colorId) {
    final g = context.ghina;
    final p = noteColorById(colorId);
    if (p == null) {
      return NoteTone(
        face: g.surface,
        edge: g.borderEdge,
        border: g.border,
        text: g.textPrimary,
        subtle: g.textSecondary,
        isDefault: true,
      );
    }
    final face = CategoryColors.parse(g.isDark ? p.dark : p.light);
    final hsl = HSLColor.fromColor(face);
    final edge = hsl
        .withLightness((hsl.lightness - (g.isDark ? 0.08 : 0.16)).clamp(0, 1))
        .toColor();
    final border = g.isDark
        ? hsl.withLightness((hsl.lightness + 0.08).clamp(0, 1)).toColor()
        : hsl.withLightness((hsl.lightness - 0.08).clamp(0, 1)).toColor();
    return NoteTone(
      face: face,
      edge: edge,
      border: border,
      text: g.textPrimary,
      subtle: g.isDark
          ? g.textPrimary.withValues(alpha: 0.72)
          : GhinaColors.eel.withValues(alpha: 0.8),
      isDefault: false,
    );
  }

  final Color face;
  final Color edge;
  final Color border;
  final Color text;
  final Color subtle;
  final bool isDefault;
}

/// Swatch of a label color (`#rrggbb`).
ChunkySwatch labelSwatch(NoteLabel l) => CategoryColors.swatch(l.color);

/// Small label chip (`# Ide Konten`).
class NoteLabelChip extends StatelessWidget {
  const NoteLabelChip({super.key, required this.label, this.onCard = false});

  final NoteLabel label;

  /// On a colored note card: a neutral translucent background.
  final bool onCard;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final s = labelSwatch(label);
    final fg = g.isDark ? Color.lerp(s.base, Colors.white, 0.35)! : s.edge;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onCard
            ? (g.isDark
                  ? Colors.black.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.7))
            : s.tint(g.brightness),
        borderRadius: GhinaRadii.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: s.base, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GhinaType.caption.w(800).copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// `m:ss` (or `h:mm:ss`) for clip durations and the recorder timer.
String formatClock(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// Host of a URL without `www.` (link rows without a title).
String linkHost(String url) {
  final u = Uri.tryParse(url);
  final h = u?.host ?? url;
  return h.startsWith('www.') ? h.substring(4) : h;
}

/// Note photo → generic viewer photo (pending = local file).
ViewerPhoto noteViewerPhoto(TransactionPhoto p) =>
    p.isPending ? ViewerPhoto.file(p.localPath!) : ViewerPhoto.network(p.url!);

List<ViewerPhoto> noteViewerPhotos(List<TransactionPhoto> ps) => [
  for (final p in ps) noteViewerPhoto(p),
];
