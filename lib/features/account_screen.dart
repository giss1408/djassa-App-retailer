import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/config/env.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';

/// The account is a phone number: show it, move it, and cut off other phones.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _busy = false;

  Future<void> _signOutOthers() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Strings.signOutOthersConfirm),
        content: const Text(Strings.signOutOthersHint),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(Strings.cancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(Strings.signOutOthers)),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    String message;
    try {
      await ref.read(authRepositoryProvider).revokeOtherSessions();
      message = Strings.signOutOthersDone;
    } on AccountActionException catch (error) {
      message = error.message;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final username = ref.watch(sessionProvider).username ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.account)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.phone_iphone_rounded),
            title: const Text(Strings.accountNumber),
            subtitle: Text(username),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.swap_horiz_rounded),
            title: const Text(Strings.changeNumber),
            subtitle: const Text(Strings.changeNumberHint),
            enabled: !_busy,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: 'change_number'), builder: (_) => const ChangeNumberScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.phonelink_erase_rounded),
            title: const Text(Strings.signOutOthers),
            subtitle: const Text(Strings.signOutOthersHint),
            enabled: !_busy,
            onTap: _signOutOthers,
          ),
        ],
      ),
    );
  }
}

/// New number, then a code from each SIM.
class ChangeNumberScreen extends ConsumerStatefulWidget {
  const ChangeNumberScreen({super.key});

  @override
  ConsumerState<ChangeNumberScreen> createState() => _ChangeNumberScreenState();
}

class _ChangeNumberScreenState extends ConsumerState<ChangeNumberScreen> {
  final _newPhone = TextEditingController();
  final _oldCode = TextEditingController();
  final _newCode = TextEditingController();
  NumberChangeCodes? _sent;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _newPhone.dispose();
    _oldCode.dispose();
    _newCode.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AccountActionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _requestCodes() => _run(() async {
        final sent = await ref.read(authRepositoryProvider).requestNumberChange(_newPhone.text.trim());
        if (!mounted) return;
        setState(() {
          _sent = sent;
          if (!Env.isRelease) {
            _oldCode.text = sent.devOldCode ?? '';
            _newCode.text = sent.devNewCode ?? '';
          }
        });
      });

  Future<void> _confirm() => _run(() async {
        final username = await ref.read(authRepositoryProvider).confirmNumberChange(
              newPhone: _newPhone.text.trim(),
              oldCode: _oldCode.text,
              newCode: _newCode.text,
            );
        ref.read(sessionProvider.notifier).onNumberChanged(username);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${Strings.numberChanged} $username')));
        Navigator.of(context).pop();
      });

  @override
  Widget build(BuildContext context) {
    final sent = _sent;
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.changeNumber)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(Strings.changeNumberIntro),
          const SizedBox(height: 20),
          TextField(
            controller: _newPhone,
            enabled: !_busy && sent == null,
            keyboardType: TextInputType.phone,
            enableSuggestions: false,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(20)],
            decoration: const InputDecoration(
              labelText: Strings.newPhone,
              hintText: Strings.signInPhoneHint,
              prefixIcon: Icon(Icons.phone_iphone_rounded),
            ),
          ),
          if (sent != null) ...[
            const SizedBox(height: 16),
            _CodeField(controller: _oldCode, label: '${Strings.oldNumberCode} (${sent.oldPhoneMasked})', enabled: !_busy),
            const SizedBox(height: 12),
            _CodeField(controller: _newCode, label: '${Strings.newNumberCode} (${sent.newPhoneMasked})', enabled: !_busy),
          ],
          ErrorLine(_error),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : (sent == null ? _requestCodes : _confirm),
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text(sent == null ? Strings.sendCodes : Strings.confirmChange),
          ),
        ],
      ),
    );
  }
}

/// Old number gone: prove the new one, say who you are, wait for Hossouko.
class LostNumberScreen extends ConsumerStatefulWidget {
  const LostNumberScreen({super.key});

  @override
  ConsumerState<LostNumberScreen> createState() => _LostNumberScreenState();
}

class _LostNumberScreenState extends ConsumerState<LostNumberScreen> {
  final _newPhone = TextEditingController();
  final _code = TextEditingController();
  final _oldPhone = TextEditingController();
  final _details = TextEditingController();
  String? _sentTo;
  String? _done;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _newPhone.dispose();
    _code.dispose();
    _oldPhone.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(authRepositoryProvider).requestRecoveryCode(_newPhone.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case CodeSent(:final phoneMasked, :final devCode):
          _sentTo = phoneMasked;
          if (devCode != null && !Env.isRelease) _code.text = devCode;
        case CodeRequestRefused(:final message) || CodeRequestUnavailable(:final message):
          _error = message;
      }
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await ref.read(authRepositoryProvider).fileRecovery(
            newPhone: _newPhone.text.trim(),
            code: _code.text,
            oldPhone: _oldPhone.text.trim(),
            details: _details.text.trim(),
          );
      if (mounted) setState(() => _done = message);
    } on AccountActionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = _done;
    if (done != null) {
      return Scaffold(
        appBar: AppBar(title: const Text(Strings.lostNumberTitle)),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(Icons.mark_email_read_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(Strings.requestSent, style: text.titleLarge),
            const SizedBox(height: 8),
            Text(done),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text(Strings.backToSignIn)),
          ],
        ),
      );
    }

    final codeStep = _sentTo != null;
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.lostNumberTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(Strings.lostNumberIntro),
          const SizedBox(height: 20),
          TextField(
            controller: _newPhone,
            enabled: !_busy && !codeStep,
            keyboardType: TextInputType.phone,
            enableSuggestions: false,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(20)],
            decoration: const InputDecoration(
              labelText: Strings.newPhone,
              hintText: Strings.signInPhoneHint,
              prefixIcon: Icon(Icons.phone_iphone_rounded),
            ),
          ),
          if (codeStep) ...[
            const SizedBox(height: 12),
            _CodeField(controller: _code, label: '${Strings.signInCodeSentTo} $_sentTo', enabled: !_busy),
            const SizedBox(height: 12),
            TextField(
              controller: _oldPhone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              enableSuggestions: false,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(20)],
              decoration: const InputDecoration(labelText: Strings.oldPhone, prefixIcon: Icon(Icons.phone_disabled_outlined)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _details,
              enabled: !_busy,
              minLines: 3,
              maxLines: 5,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: Strings.recoveryDetails,
                hintText: Strings.recoveryDetailsHint,
                alignLabelWithHint: true,
              ),
            ),
          ],
          ErrorLine(_error),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : (codeStep ? _submit : _requestCode),
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text(codeStep ? Strings.sendRequest : Strings.continueLabel),
          ),
        ],
      ),
    );
  }
}

class _CodeField extends StatelessWidget {
  const _CodeField({required this.controller, required this.label, required this.enabled});

  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
      style: const TextStyle(fontSize: 20, letterSpacing: 6, fontWeight: FontWeight.w700),
      decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.sms_outlined)),
    );
  }
}

/// A refusal in the server's own words, or nothing.
class ErrorLine extends StatelessWidget {
  const ErrorLine(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline_rounded, size: 18, color: colors.error),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.error))),
      ]),
    );
  }
}
