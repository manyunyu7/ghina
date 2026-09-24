/// Shared flows of the Konten screens: stage moves (with XP toasts), "Sudah
/// tayang", post changes that auto-advance the item, and opening URLs.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/result.dart';
import '../../../di/di.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/usecases/usecases.dart';
import '../../design_system/design_system.dart';
import '../../shared/rewards/rewards.dart';
import '../../shared/widgets/widgets.dart';
import 'content_format.dart';

/// Opens an external URL (app deep link or web). Returns false when nothing
/// could handle it. Override in tests.
typedef UrlOpener = Future<bool> Function(String url);

final contentUrlOpenerProvider = Provider<UrlOpener>(
  (ref) => (url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  },
);

/// Tries [urls] in order (deep link first, then the web page).
Future<bool> openFirstUrl(WidgetRef ref, List<String> urls) async {
  final open = ref.read(contentUrlOpenerProvider);
  for (final u in urls) {
    if (await open(u)) return true;
  }
  return false;
}

/// Opens [url] (http/https only — stored links may come from sync or a
/// shared note, never launch `intent:`, `file:`, `javascript:`…); toasts when
/// it can't.
Future<void> openUrlOrToast(
  BuildContext context,
  WidgetRef ref,
  String url,
) async {
  final u = url.trim();
  final ok = isHttpUrl(u) && await openFirstUrl(ref, [u]);
  if (!ok && context.mounted) {
    showErrorToast(context, 'Link-nya belum bisa dibuka');
  }
}

/// Links inside the idea/script Markdown: shows the real URL first (the link
/// text can say anything), then "Salin" or "Buka".
Future<void> confirmOpenContentLink(
  BuildContext context,
  WidgetRef ref,
  String url,
) async {
  final safe = isHttpUrl(url.trim());
  final action = await showChunkyBottomSheet<String>(
    context,
    title: 'Buka tautan?',
    showClose: true,
    builder: (c) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          url,
          key: const ValueKey('link-confirm-url'),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: GhinaType.body.w(700).copyWith(color: c.ghina.textSecondary),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ChunkyButton(
                key: const ValueKey('link-confirm-copy'),
                label: 'Salin',
                variant: ChunkyButtonVariant.outline,
                icon: Icons.copy_rounded,
                onPressed: () => Navigator.of(c).pop('copy'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ChunkyButton(
                key: const ValueKey('link-confirm-open'),
                label: 'Buka',
                icon: Icons.open_in_new_rounded,
                onPressed: safe ? () => Navigator.of(c).pop('open') : null,
              ),
            ),
          ],
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  if (action == 'open') {
    await openUrlOrToast(context, ref, url);
  } else if (action == 'copy') {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) showOkToast(context, 'Tautan disalin');
  }
}

/// "Buka Instagram": app, else the profile page.
Future<void> openPlatform(
  BuildContext context,
  WidgetRef ref,
  SocialAccount account,
) async {
  final ok = await openFirstUrl(ref, platformOpenUrls(account));
  if (!ok && context.mounted) {
    showErrorToast(
      context,
      'Belum bisa membuka ${account.platformLabel}. Buka manual, ya',
    );
  }
}

/// "Salin caption + hashtag".
Future<void> copyCaption(BuildContext context, String text) async {
  if (text.trim().isEmpty) {
    showErrorToast(context, 'Caption masih kosong');
    return;
  }
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    showToastBadge(
      context,
      message: 'Caption + hashtag disalin 📋',
      icon: Icons.content_copy_rounded,
      color: GhinaColors.blue,
    );
  }
}

/// Moves [item] to [to] (board drag / "Pindah tahap"); forward moves show the
/// XP toast (and any celebration).
Future<bool> moveStageFlow(
  BuildContext context,
  WidgetRef ref,
  ContentItem item,
  ContentStage to,
) async {
  if (item.stage == to) return true;
  final forward = to.isAfter(item.stage);
  final rewards = forward ? await RewardTracker.startLoaded(ref) : null;
  final r = await ref.read(moveContentStageProvider)(item.id, to);
  if (!context.mounted) {
    rewards?.cancel();
    return r is Ok;
  }
  switch (r) {
    case Ok():
      if (rewards != null) {
        await rewards.finish(
          context,
          xpToast: (xp) => 'Naik ke ${to.emoji} ${to.label}! +$xp XP',
          doneToast: 'Pindah ke ${to.emoji} ${to.label}',
          goalHint: true,
        );
      } else {
        showOkToast(context, 'Balik ke ${to.emoji} ${to.label}');
      }
      return true;
    case Err(:final failure):
      showFailureToast(context, failure);
      return false;
  }
}

/// Runs a post write; when it moves the item forward (`autoStage`), shows
/// the XP toast "Naik ke Terjadwal". [posts] = the item's posts before the
/// write; [apply] returns the changed post.
Future<ContentPost?> postChangeFlow(
  BuildContext context,
  WidgetRef ref, {
  required ContentItem? item,
  required List<ContentPost> posts,
  required Future<Result<ContentPost>> Function() write,
  String? doneToast,
  String Function(int xp)? xpToast,
}) async {
  final rewards = await RewardTracker.startLoaded(ref);
  final r = await write();
  if (!context.mounted) {
    rewards.cancel();
    return r is Ok<ContentPost> ? r.value : null;
  }
  switch (r) {
    case Ok(:final value):
      final after = [
        for (final p in posts)
          if (p.id != value.id) p,
        value,
      ];
      final from = item?.stage;
      final to = from == null ? null : autoStage(from, after);
      final advanced = from != null && to != null && to != from;
      if (advanced || value.isPosted) {
        await rewards.finish(
          context,
          xpToast:
              xpToast ??
              (xp) => advanced
                  ? 'Konten naik ke ${to.emoji} ${to.label}! +$xp XP'
                  : '+$xp XP',
          doneToast: advanced
              ? 'Konten naik ke ${to.emoji} ${to.label}'
              : doneToast,
          goalHint: true,
        );
      } else {
        rewards.cancel();
        if (doneToast != null) showOkToast(context, doneToast);
      }
      return value;
    case Err(:final failure):
      rewards.cancel();
      showFailureToast(context, failure);
      return null;
  }
}

/// "Sudah tayang" (+ optional URL).
Future<bool> markPostedFlow(
  BuildContext context,
  WidgetRef ref, {
  required ContentPostView view,
  required List<ContentPost> siblings,
  String? url,
}) async {
  final p = await postChangeFlow(
    context,
    ref,
    item: view.item,
    posts: siblings,
    write: () => ref.read(markPostPostedProvider)(
      view.id,
      url: (url ?? '').trim().isEmpty ? null : url!.trim(),
    ),
    doneToast: 'Mantap, sudah tayang! 🚀',
    xpToast: (xp) => 'Tayang! 🚀 +$xp XP',
  );
  return p != null;
}
