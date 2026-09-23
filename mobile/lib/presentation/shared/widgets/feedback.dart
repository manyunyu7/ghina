import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/result.dart';
import '../../../di/di.dart';
import '../../design_system/design_system.dart';

/// Red toast for a failed action (the message is already Indonesian).
void showErrorToast(BuildContext context, String message) => showToastBadge(
  context,
  message: message,
  icon: Icons.error_rounded,
  color: GhinaColors.red,
  duration: const Duration(milliseconds: 3000),
);

/// [showErrorToast] for a [Failure].
void showFailureToast(BuildContext context, Failure failure) =>
    showErrorToast(context, failure.message);

/// Green "done" toast.
void showOkToast(BuildContext context, String message, {IconData? icon}) =>
    showToastBadge(
      context,
      message: message,
      icon: icon ?? Icons.check_circle_rounded,
      color: GhinaColors.green,
    );

/// Pull-to-refresh: asks the sync engine to sync now. Offline is fine — data
/// lives on the phone — so only a gentle hint is shown.
Future<void> pullToSync(BuildContext context, WidgetRef ref) async {
  final r = await ref.read(syncNowProvider)();
  if (r case Err(:final failure) when context.mounted) {
    showToastBadge(
      context,
      message: failure is NetworkFailure
          ? 'Lagi offline. Data kamu aman di HP 👍'
          : 'Belum bisa sinkron. Nanti dicoba lagi ya',
      icon: Icons.cloud_off_rounded,
      color: GhinaColors.blue,
    );
  }
}

/// Pops the current page, or goes to [fallback] when it's the root.
void popOr(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}
