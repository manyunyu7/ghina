import 'package:flutter/material.dart';

import '../../../../domain/entities/entities.dart';
import '../../../design_system/design_system.dart';

/// Spec colors: FIRE `#FF4B4B`, WANT `#CE82FF`, SHOULD `#1CB0F6`.
ChunkySwatch bucketSwatch(TaskBucket b) => switch (b) {
  TaskBucket.fire => GhinaColors.red,
  TaskBucket.want => GhinaColors.purple,
  TaskBucket.should => GhinaColors.blue,
};

ChunkySwatch areaSwatch(TaskArea? a) =>
    a == null ? GhinaColors.gray : CategoryColors.swatch(a.color);

/// Small colored area dot (used on tiles when several areas are listed).
class AreaDot extends StatelessWidget {
  const AreaDot({super.key, required this.area, this.size = 10});

  final TaskArea? area;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: areaSwatch(area).base,
      shape: BoxShape.circle,
    ),
  );
}

/// `🔥 FIRE` pill in the bucket color.
class BucketPill extends StatelessWidget {
  const BucketPill({super.key, required this.bucket, this.soft = true});

  final TaskBucket bucket;
  final bool soft;

  @override
  Widget build(BuildContext context) => ChunkyPill(
    label: bucket.display,
    color: bucketSwatch(bucket),
    soft: soft,
  );
}

/// Segments for choosing a bucket (FIRE / WANT / SHOULD).
List<ChunkySegment<TaskBucket>> bucketSegments() => [
  for (final b in TaskBucket.values)
    ChunkySegment(value: b, label: b.display, color: bucketSwatch(b)),
];
