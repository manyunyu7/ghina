import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/config.dart';
import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';

/// Swatch per meal type (chips, avatars).
ChunkySwatch mealSwatch(MealType? m) => switch (m) {
  MealType.breakfast => GhinaColors.orange,
  MealType.lunch => GhinaColors.green,
  MealType.dinner => GhinaColors.purple,
  MealType.snack => GhinaColors.pink,
  null => GhinaColors.gray,
};

/// Photo of a food log: the local (not yet uploaded) file first, else the
/// server URL; falls back to a colourful meal-emoji tile.
class FoodPhoto extends StatelessWidget {
  const FoodPhoto({
    super.key,
    required this.log,
    this.size = 64,
    this.width,
    this.height,
    this.radius = GhinaRadii.rLg,
  });

  final FoodLog log;
  final double size;
  final double? width;
  final double? height;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final w = width ?? size;
    final h = height ?? size;
    final fallback = MealEmojiTile(
      meal: log.meal,
      width: w,
      height: h,
      radius: radius,
    );
    Widget? img;
    final local = log.localPhotoPath;
    if (local != null && local.isNotEmpty) {
      img = Image.file(
        File(local),
        width: w,
        height: h,
        fit: BoxFit.cover,
        cacheWidth: w.isFinite ? (w * 3).round() : null,
        errorBuilder: (_, _, _) => fallback,
      );
    } else if (AppConfig.resolveUrl(log.photoUrl) case final url?) {
      img = Image.network(
        url,
        width: w,
        height: h,
        fit: BoxFit.cover,
        cacheWidth: w.isFinite ? (w * 3).round() : null,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : Skeleton(width: w, height: h, radius: 16),
      );
    }
    if (img == null) return fallback;
    return ClipRRect(borderRadius: radius, child: img);
  }
}

/// Coloured square with the meal's emoji (no photo).
class MealEmojiTile extends StatelessWidget {
  const MealEmojiTile({
    super.key,
    required this.meal,
    required this.width,
    required this.height,
    this.radius = GhinaRadii.rLg,
  });

  final MealType? meal;
  final double width;
  final double height;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = mealSwatch(meal);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: sw.tint(g.brightness),
        borderRadius: radius,
      ),
      alignment: Alignment.center,
      child: meal == null
          ? Icon(Icons.restaurant_rounded, color: sw.base, size: width * 0.45)
          : Text(meal!.emoji, style: TextStyle(fontSize: width * 0.42)),
    );
  }
}
