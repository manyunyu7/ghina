import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import 'content_visuals.dart';

/// Home card "Tayang hari ini" (`docs/content.md` → Navigation): today's
/// posts in time order; tap a row → the post (copy caption, open the app,
/// "Sudah tayang"). Renders nothing when there are no posts today.
class TodayPostsCard extends ConsumerWidget {
  const TodayPostsCard({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(watchTodayPostsProvider).value;
    if (today == null || today.isEmpty) return const SizedBox.shrink();
    final g = context.ghina;
    final pending = today.pending;
    return Padding(
      padding: padding,
      child: ChunkyCard(
        key: const ValueKey('today-posts'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        onTap: () => context.push('/content'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.rocket_launch_rounded,
                  color: GhinaColors.green.base,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tayang hari ini',
                    style: GhinaType.h3.copyWith(color: g.textPrimary),
                  ),
                ),
                ChunkyPill(
                  label: pending == 0 ? 'Beres' : '$pending lagi',
                  color: pending == 0 ? GhinaColors.green : GhinaColors.orange,
                  soft: pending != 0,
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final p in today.posts.take(4))
              InkWell(
                key: ValueKey('today-post-${p.id}'),
                borderRadius: GhinaRadii.rMd,
                onTap: () => context.push(contentPostRoute(p.id)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(
                          p.post.calendarAt == null
                              ? '--'
                              : Fmt.time(p.post.calendarAt!),
                          style: GhinaType.bodyS
                              .w(800)
                              .copyWith(color: g.textSecondary),
                        ),
                      ),
                      if (p.account != null) ...[
                        AccountAvatar(
                          account: p.account!,
                          size: 26,
                          status: p.post.status,
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          p.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GhinaType.body
                              .w(700)
                              .copyWith(
                                color: p.post.isPosted
                                    ? g.textMuted
                                    : g.textPrimary,
                                decoration: p.post.isPosted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: g.textMuted),
                    ],
                  ),
                ),
              ),
            if (today.posts.length > 4)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '+${today.posts.length - 4} lagi',
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
