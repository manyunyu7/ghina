import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';

/// Only http(s) links are opened (never `javascript:`, `file:`, intents…).
Uri? safeLinkUri(String url) {
  var u = url.trim();
  if (u.toLowerCase().startsWith('www.')) u = 'https://$u';
  final uri = Uri.tryParse(u);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

/// Opens [url] in the browser/app. Returns false (with a toast) when it can't.
Future<bool> openLink(BuildContext context, String url) async {
  final uri = safeLinkUri(url);
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context.mounted) {
    showErrorToast(context, 'Tautan ini nggak bisa dibuka');
  }
  return ok;
}

/// Copies [url] and confirms with a toast.
Future<void> copyLink(BuildContext context, String url) async {
  await Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) showOkToast(context, 'Tautan disalin', icon: Icons.copy);
}

/// Shows the full URL before opening it (links inside the note text).
Future<void> confirmOpenLink(BuildContext context, String url) async {
  final safe = safeLinkUri(url) != null;
  final action = await showChunkyBottomSheet<String>(
    context,
    title: 'Buka tautan?',
    showClose: true,
    builder: (c) {
      final g = c.ghina;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            url,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: GhinaType.body.w(700).copyWith(color: g.textSecondary),
          ),
          if (!safe) ...[
            const SizedBox(height: 8),
            Text(
              'Hanya tautan http/https yang bisa dibuka.',
              style: GhinaType.bodyS.copyWith(color: GhinaColors.red.base),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ChunkyButton(
                  label: 'Salin',
                  variant: ChunkyButtonVariant.outline,
                  icon: Icons.copy_rounded,
                  onPressed: () => Navigator.of(c).pop('copy'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChunkyButton(
                  label: 'Buka',
                  icon: Icons.open_in_new_rounded,
                  onPressed: safe ? () => Navigator.of(c).pop('open') : null,
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
  if (!context.mounted) return;
  if (action == 'open') {
    await openLink(context, url);
  } else if (action == 'copy') {
    await copyLink(context, url);
  }
}
