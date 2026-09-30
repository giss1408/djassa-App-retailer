import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/config/env.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import 'about_name_screen.dart';

/// Sign-in.
///
/// The backend authenticates a single hardcoded demo user and offers no
/// registration or OTP (`app/api/auth.py`), so this asks for a username and
/// password — the only thing that exists. `djassa-BE/docs/business/CONCEPT.md` calls for Tier 0
/// identity anchored to a mobile-money number instead; when that lands
/// server-side this screen changes and nothing behind it does.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  // Prefilled only in debug builds given DJASSA_DEV_* defines. See Env.
  final _username = TextEditingController(text: Env.devUsername);
  final _password = TextEditingController(text: Env.devPassword);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref.read(sessionProvider.notifier).signIn(
          username: _username.text.trim(),
          password: _password.text,
        );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = switch (result) {
        SignInSuccess() => null,
        SignInRejected() => Strings.signInRejected,
        SignInUnavailable(message: final m) => m,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Djassa', style: text.headlineMedium),
                  const SizedBox(height: 4),
                  Text(Strings.signInSubtitle, style: text.bodyMedium),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _username,
                    enabled: !_busy,
                    autocorrect: false,
                    // Never offer to autofill or suggest: a market phone is
                    // often shared or handed around.
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: Strings.username),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(labelText: Strings.password),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: text.bodySmall?.copyWith(color: colors.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy ? Strings.signingIn : Strings.signIn),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AboutNameScreen(),
                      ),
                    ),
                    child: const Text(Strings.aboutNameLink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
