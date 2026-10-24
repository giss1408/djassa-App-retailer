import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import 'account_screen.dart';

/// At least 8 characters and not only digits. The server stays the authority.
bool isAcceptablePassword(String value) => value.length >= 8 && !RegExp(r'^\d+$').hasMatch(value);

/// Choosing a password. [forced] is the case right after signing in with the
/// temporary password the team sent: no back, no current password, a
/// sign-out escape. Otherwise it is the normal change from Mon compte, which
/// asks for the current password.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key, required this.forced});

  final bool forced;

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _hidden = true;
  bool _busy = false;
  String? _ruleError;
  String? _matchError;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final ruleError = isAcceptablePassword(_new.text) ? null : Strings.passwordRule;
    final matchError = _new.text == _confirm.text ? null : Strings.passwordMismatch;
    final currentMissing = !widget.forced && _current.text.isEmpty;
    setState(() {
      _ruleError = ruleError;
      _matchError = ruleError == null ? matchError : null;
      _error = currentMissing ? Strings.passwordCurrentMissing : null;
    });
    if (ruleError != null || matchError != null || currentMissing) return;

    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).changePassword(
            current: widget.forced ? null : _current.text,
            newPassword: _new.text,
          );
      if (!mounted) return;
      // Forced: the gate swaps this screen for home. Otherwise go back.
      if (!widget.forced) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(Strings.passwordChanged)));
        Navigator.of(context).pop();
      }
    } on AccountActionException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  Widget _field(TextEditingController controller, String label, {String? error, TextInputAction? action, bool toggle = false}) {
    return TextField(
      controller: controller,
      enabled: !_busy,
      obscureText: _hidden,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: action ?? TextInputAction.next,
      onSubmitted: action == TextInputAction.done ? (_) => _submit() : null,
      decoration: InputDecoration(
        labelText: label,
        errorText: error,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: toggle
            ? IconButton(
                tooltip: _hidden ? Strings.showPassword : Strings.hidePassword,
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.forced,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.forced,
          title: Text(widget.forced ? Strings.choosePasswordTitle : Strings.changePassword),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            if (widget.forced) const Padding(padding: EdgeInsets.only(bottom: 16), child: Text(Strings.choosePasswordIntro)),
            if (!widget.forced) ...[
              _field(_current, Strings.currentPassword),
              const SizedBox(height: 14),
            ],
            _field(_new, Strings.newPassword, error: _ruleError, toggle: true),
            const SizedBox(height: 6),
            Text(Strings.passwordRule, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            _field(_confirm, Strings.confirmPassword, error: _matchError, action: TextInputAction.done),
            ErrorLine(_error),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text(Strings.save),
            ),
            if (widget.forced)
              TextButton(
                onPressed: _busy ? null : () => ref.read(sessionProvider.notifier).signOut(),
                child: const Text(Strings.signOut),
              ),
          ],
        ),
      ),
    );
  }
}

/// A number not yet proven: the code a Fidelia admin sends on WhatsApp. The
/// server refuses everything else until then, so this replaces home.
class VerifyNumberScreen extends ConsumerStatefulWidget {
  const VerifyNumberScreen({super.key});

  @override
  ConsumerState<VerifyNumberScreen> createState() => _VerifyNumberScreenState();
}

class _VerifyNumberScreenState extends ConsumerState<VerifyNumberScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  // The team marked the number « pas sur WhatsApp ».
  bool _refused = false;

  @override
  void initState() {
    super.initState();
    ref.read(authRepositoryProvider).numberRefused().then((refused) {
      if (mounted) setState(() => _refused = refused);
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_code.text.length != 6) {
      setState(() => _error = Strings.verifyCodeMissing);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // On success the gate swaps this screen for home.
      await ref.read(sessionProvider.notifier).verifyNumber(_code.text);
    } on AccountActionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final username = ref.watch(sessionProvider).username ?? '';
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text(Strings.verifyTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_refused)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(Strings.numberNotOnWhatsApp, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
            ),
          const Text(Strings.verifyIntro),
          if (username.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(username, style: Theme.of(context).textTheme.titleMedium),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _code,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            onChanged: (value) {
              if (value.length == 6) _submit();
            },
            onSubmitted: (_) => _submit(),
            style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(labelText: Strings.verifyCodeLabel, prefixIcon: Icon(Icons.chat_outlined)),
          ),
          ErrorLine(_error),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : const Text(Strings.verifyAction),
          ),
          TextButton(
            onPressed: _busy ? null : () => ref.read(sessionProvider.notifier).signOut(),
            child: const Text(Strings.signOut),
          ),
        ],
      ),
    );
  }
}
