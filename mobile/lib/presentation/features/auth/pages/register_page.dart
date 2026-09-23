import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/result.dart';
import '../../../design_system/design_system.dart';
import '../../../state/session_controller.dart';
import '../widgets/auth_widgets.dart';

/// New account: name, email, password (min 6, as on the web). New server accounts
/// come with a starter wallet and the default categories.
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
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
        .register(_name.text.trim(), _email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r case Err(:final failure)) _error = failure.message;
    });
  }

  void _toLogin() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      mood: MascotMood.excited,
      title: 'Bikin akun, yuk!',
      subtitle:
          'Gratis, cuma butuh semenit. Habis itu kita rapiin keuanganmu bareng.',
      showBack: context.canPop(),
      children: [
        if (_error != null) ...[AuthNotice(message: _error!), GhinaSpace.gapLg],
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChunkyTextField(
                  key: const ValueKey('register-name'),
                  label: 'Nama',
                  hint: 'Nama panggilanmu',
                  controller: _name,
                  maxLength: 60,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  prefixIcon: Icons.person_rounded,
                  autofillHints: const [AutofillHints.name],
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Namanya siapa, nih?'
                      : null,
                ),
                GhinaSpace.gapMd,
                ChunkyTextField(
                  key: const ValueKey('register-email'),
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
                  key: const ValueKey('register-password'),
                  label: 'Kata sandi',
                  hint: 'Minimal 6 karakter',
                  controller: _password,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  prefixIcon: Icons.lock_rounded,
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => _submit(),
                  validator: (v) => (v == null || v.length < 6)
                      ? 'Minimal 6 karakter biar aman'
                      : null,
                ),
              ],
            ),
          ),
        ),
        GhinaSpace.gapXl,
        ChunkyButton(
          label: 'Daftar',
          loading: _loading,
          onPressed: _loading ? null : _submit,
        ),
        GhinaSpace.gapLg,
        AuthSwitchLink(
          question: 'Sudah punya akun?',
          action: 'Masuk',
          onTap: _toLogin,
        ),
      ],
    );
  }
}
