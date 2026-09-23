import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';

/// Email check shared by login and register (same rule as the web's zod email).
String? validateEmail(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Email-nya diisi dulu, ya';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
    return 'Format email-nya kurang pas';
  }
  return null;
}

/// Scrollable, centered auth layout: mascot on top, then [children].
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.mood,
    required this.title,
    required this.subtitle,
    required this.children,
    this.showBack = false,
  });

  final MascotMood mood;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Scaffold(
      appBar: showBack ? AppBar() : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              GhinaSpace.page,
              GhinaSpace.xl,
              GhinaSpace.page,
              GhinaSpace.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: MascotView(mood: mood, size: 120)),
                  GhinaSpace.gapLg,
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: GhinaType.h1.copyWith(color: g.textPrimary),
                  ),
                  GhinaSpace.gapSm,
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: GhinaType.body.copyWith(color: g.textSecondary),
                  ),
                  GhinaSpace.gapXl,
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft colored notice card (errors, "sesi berakhir").
class AuthNotice extends StatelessWidget {
  const AuthNotice({
    super.key,
    required this.message,
    this.color = GhinaColors.red,
    this.icon = Icons.error_outline_rounded,
  });

  final String message;
  final ChunkySwatch color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Shake(
      trigger: message,
      child: Container(
        padding: const EdgeInsets.all(GhinaSpace.md),
        decoration: BoxDecoration(
          color: color.tint(g.brightness),
          borderRadius: GhinaRadii.rLg,
          border: Border.all(color: color.tintBorder(g.brightness), width: 2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: g.isDark ? color.base : color.edge, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GhinaType.body
                    .w(700)
                    .copyWith(color: g.isDark ? color.base : color.edge),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Belum punya akun? Daftar" style footer link.
class AuthSwitchLink extends StatelessWidget {
  const AuthSwitchLink({
    super.key,
    required this.question,
    required this.action,
    required this.onTap,
  });

  final String question;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(question, style: GhinaType.body.copyWith(color: g.textSecondary)),
        TextButton(
          onPressed: onTap,
          child: Text(
            action,
            style: GhinaType.body.w(900).copyWith(color: GhinaColors.blue.base),
          ),
        ),
      ],
    );
  }
}
