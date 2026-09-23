import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';

/// Error state with the sad mascot and a retry button (never blames the user).
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({
    super.key,
    required this.onRetry,
    this.title = 'Ups, gagal memuat',
    this.message = 'Datanya belum bisa dimuat. Coba lagi, yuk.',
    this.compact = false,
  });

  final VoidCallback onRetry;
  final String title;
  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) => EmptyState(
    mood: MascotMood.sad,
    compact: compact,
    title: title,
    message: message,
    actionLabel: 'Coba lagi',
    onAction: onRetry,
  );
}

/// Skeleton placeholder for a page: an optional hero card and a few tiles.
class LoadingListView extends StatelessWidget {
  const LoadingListView({super.key, this.tiles = 4, this.hero = true});

  final int tiles;
  final bool hero;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
    physics: const NeverScrollableScrollPhysics(),
    children: [
      if (hero) ...[
        const Skeleton(height: 132, radius: GhinaRadii.xl),
        const SizedBox(height: 20),
        const Skeleton(width: 160, height: 22),
        const SizedBox(height: 14),
      ],
      SkeletonList(count: tiles),
    ],
  );
}

/// A scrollable wrapper so empty/error states still support pull-to-refresh.
class ScrollableFill extends StatelessWidget {
  const ScrollableFill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: c.maxHeight),
        child: Center(child: child),
      ),
    ),
  );
}
