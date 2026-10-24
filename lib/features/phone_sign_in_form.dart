import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/config/env.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import 'account_screen.dart';

/// Phone number and password.
///
/// Nothing is remembered between launches: the number is the account, and a
/// shared phone should not offer the last person's.
class PhoneSignInForm extends ConsumerStatefulWidget {
  const PhoneSignInForm({super.key});

  @override
  ConsumerState<PhoneSignInForm> createState() => _PhoneSignInFormState();
}

class _PhoneSignInFormState extends ConsumerState<PhoneSignInForm> {
  // Prefilled only in debug builds given FIDELIA_DEV_PHONE. See Env.
  final _phone = TextEditingController(text: Env.devPhone);
  final _password = TextEditingController();
  bool _hidden = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    if (_phone.text.trim().isEmpty) {
      setState(() => _error = Strings.signInPhoneMissing);
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = Strings.signInPasswordMissing);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(sessionProvider.notifier).signIn(phone: _phone.text.trim(), password: _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = switch (result) {
        // The session gate swaps this screen out.
        SignInSuccess() => null,
        SignInRejected(:final message) || SignInUnavailable(:final message) => message,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _phone,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            autocorrect: false,
            // Never suggest a number: a market phone is often shared.
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(20)],
            decoration: const InputDecoration(
              labelText: Strings.signInPhoneLabel,
              hintText: Strings.signInPhoneHint,
              helperText: Strings.signInPhoneHelper,
              prefixIcon: Icon(Icons.phone_iphone_rounded),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: _hidden,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _signIn(),
            decoration: InputDecoration(
              labelText: Strings.signInPasswordLabel,
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _hidden ? Strings.showPassword : Strings.hidePassword,
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
          ErrorLine(_error),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _signIn,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : const Text(Strings.signIn),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                      settings: const RouteSettings(name: 'ask_password'),
                      builder: (_) => AskPasswordScreen(phone: _phone.text.trim()),
                    )),
            child: const Text(Strings.askPassword, textAlign: TextAlign.center),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: 'lost_number'), builder: (_) => const LostNumberScreen())),
            child: const Text(Strings.lostNumber),
          ),
        ],
      ),
    );
  }
}

/// A first password for a login the team created, or a forgotten one: the
/// team sends a temporary password on WhatsApp.
class AskPasswordScreen extends ConsumerStatefulWidget {
  const AskPasswordScreen({super.key, this.phone = ''});

  final String phone;

  @override
  ConsumerState<AskPasswordScreen> createState() => _AskPasswordScreenState();
}

class _AskPasswordScreenState extends ConsumerState<AskPasswordScreen> {
  late final _phone = TextEditingController(text: widget.phone);
  bool _busy = false;
  String? _error;
  String? _done;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_phone.text.trim().isEmpty) {
      setState(() => _error = Strings.signInPhoneMissing);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await ref.read(authRepositoryProvider).requestPassword(_phone.text.trim());
      if (mounted) setState(() => _done = message);
    } on AccountActionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final done = _done;
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.askPasswordTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: done != null
            ? [
                Icon(Icons.mark_chat_read_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(Strings.requestSent, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(done),
                const SizedBox(height: 24),
                FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text(Strings.backToSignIn)),
              ]
            : [
                const Text(Strings.askPasswordIntro),
                const SizedBox(height: 20),
                TextField(
                  controller: _phone,
                  enabled: !_busy,
                  keyboardType: TextInputType.phone,
                  enableSuggestions: false,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(20)],
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: Strings.signInPhoneLabel,
                    hintText: Strings.signInPhoneHint,
                    prefixIcon: Icon(Icons.phone_iphone_rounded),
                  ),
                ),
                ErrorLine(_error),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : const Text(Strings.askPasswordAction),
                ),
              ],
      ),
    );
  }
}
