import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result.dart';
import '../../../design_system/design_system.dart';
import '../../../state/session_controller.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/google_auth.dart';

/// Email + password sign-in (plus Google when configured, see `google_auth.dart`).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await ref
        .read(sessionControllerProvider.notifier)
        .signIn(_email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r case Err(:final failure)) _error = failure.message;
    });
  }

  Future<void> _google() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    String? error;
    try {
      final token = await obtainGoogleIdToken();
      if (token != null) {
        final r = await ref
            .read(sessionControllerProvider.notifier)
            .signInWithGoogle(token);
        if (r case Err(:final failure)) error = failure.message;
      }
    } catch (_) {
      error = 'Masuk pakai Google lagi bermasalah. Coba pakai email dulu, ya.';
    }
    if (!mounted) return;
    setState(() {
      _googleLoading = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final expired = session is SignedOut && session.expired;
    final busy = _loading || _googleLoading;
    final g = context.ghina;

    return AuthScaffold(
      mood: expired ? MascotMood.sad : MascotMood.waving,
      title: expired ? 'Sesi kamu berakhir' : 'Halo lagi!',
      subtitle: expired
          ? 'Demi keamanan, kamu perlu masuk lagi. Tenang, datamu aman kok 🙏'
          : 'Masuk dulu, yuk. Dompetmu udah nungguin.',
      children: [
        if (_error != null) ...[AuthNotice(message: _error!), GhinaSpace.gapLg],
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChunkyTextField(
                  key: const ValueKey('login-email'),
                  label: 'Email',
                  hint: 'kamu@contoh.com',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.none,
                  prefixIcon: Icons.mail_rounded,
                  autofillHints: const [AutofillHints.email],
                  validator: validateEmail,
                ),
                GhinaSpace.gapLg,
                ChunkyTextField(
                  key: const ValueKey('login-password'),
                  label: 'Kata sandi',
                  hint: 'Kata sandimu',
                  controller: _password,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  prefixIcon: Icons.lock_rounded,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                  validator: (v) => (v == null || v.isEmpty)
                      ? 'Kata sandinya diisi dulu, ya'
                      : null,
                ),
              ],
            ),
          ),
        ),
        GhinaSpace.gapXl,
        ChunkyButton(
          label: 'Masuk',
          loading: _loading,
          onPressed: busy ? null : _submit,
        ),
        if (googleSignInEnabled) ...[
          GhinaSpace.gapLg,
          Row(
            children: [
              Expanded(child: Divider(color: g.border, thickness: 2)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'ATAU',
                  style: GhinaType.caption.w(900).copyWith(color: g.textMuted),
                ),
              ),
              Expanded(child: Divider(color: g.border, thickness: 2)),
            ],
          ),
          GhinaSpace.gapLg,
          ChunkyButton(
            label: 'Masuk dengan Google',
            variant: ChunkyButtonVariant.outline,
            icon: Icons.g_mobiledata_rounded,
            loading: _googleLoading,
            onPressed: busy ? null : _google,
          ),
        ],
        GhinaSpace.gapLg,
        AuthSwitchLink(
          question: 'Belum punya akun?',
          action: 'Daftar',
          onTap: () => context.push('/register'),
        ),
      ],
    );
  }
}
