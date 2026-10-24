import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/providers.dart';
import '../core/net/api_exception.dart';
import '../l10n/strings.dart';
import 'password_screens.dart';

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

  /// A shop's account is not deleted on the spot: its sales are the shop's
  /// records, so the team settles the shop first (fidelia-BE app/api/account.py).
  Future<void> _requestDeletion() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Strings.deleteAccountConfirm),
        content: const Text(Strings.deleteAccountWarning),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(Strings.cancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(Strings.deleteAccountAction)),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    String message;
    try {
      final body = await ref.read(apiClientProvider).postJson('/api/account/deletion-request', body: const {});
      message = body['message'] as String? ?? Strings.deleteAccountSent;
    } on ApiException catch (error) {
      message = error.message;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Strings.deleteAccountSent),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
      ),
    );
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
            leading: const Icon(Icons.password_rounded),
            title: const Text(Strings.changePassword),
            subtitle: const Text(Strings.changePasswordHint),
            enabled: !_busy,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: 'change_password'), builder: (_) => const ChangePasswordScreen(forced: false))),
          ),
          ListTile(
            leading: const Icon(Icons.phonelink_erase_rounded),
            title: const Text(Strings.signOutOthers),
            subtitle: const Text(Strings.signOutOthersHint),
            enabled: !_busy,
            onTap: _signOutOthers,
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: Text(Strings.deleteAccount, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            subtitle: const Text(Strings.deleteAccountHint),
            enabled: !_busy,
            onTap: _requestDeletion,
          ),
        ],
      ),
    );
  }
}

/// Password and new number, then the code the Fidelia team sends on WhatsApp
/// to the new number.
class ChangeNumberScreen extends ConsumerStatefulWidget {
  const ChangeNumberScreen({super.key});

  @override
  ConsumerState<ChangeNumberScreen> createState() => _ChangeNumberScreenState();
}

class _ChangeNumberScreenState extends ConsumerState<ChangeNumberScreen> {
  final _newPhone = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  String? _sentTo;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _newPhone.dispose();
    _password.dispose();
    _code.dispose();
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

  Future<void> _request() => _run(() async {
        final sentTo = await ref.read(authRepositoryProvider).requestNumberChange(
              newPhone: _newPhone.text.trim(),
              password: _password.text,
            );
        if (mounted) setState(() => _sentTo = sentTo);
      });

  Future<void> _confirm() => _run(() async {
        final username = await ref.read(authRepositoryProvider).confirmNumberChange(_code.text);
        await ref.read(sessionProvider.notifier).onNumberChanged();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${Strings.numberChanged} $username')));
        Navigator.of(context).pop();
      });

  @override
  Widget build(BuildContext context) {
    final sentTo = _sentTo;
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.changeNumber)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(Strings.changeNumberIntro),
          const SizedBox(height: 20),
          TextField(
            controller: _newPhone,
            enabled: !_busy && sentTo == null,
            keyboardType: TextInputType.phone,
            enableSuggestions: false,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(20)],
            decoration: const InputDecoration(
              labelText: Strings.newPhone,
              hintText: Strings.signInPhoneHint,
              prefixIcon: Icon(Icons.phone_iphone_rounded),
            ),
          ),
          if (sentTo == null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: Strings.currentPassword, prefixIcon: Icon(Icons.lock_outline)),
            ),
          ] else ...[
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              style: const TextStyle(fontSize: 20, letterSpacing: 6, fontWeight: FontWeight.w700),
              decoration: InputDecoration(labelText: '${Strings.newNumberCode} $sentTo', prefixIcon: const Icon(Icons.chat_outlined)),
            ),
          ],
          ErrorLine(_error),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : (sentTo == null ? _request : _confirm),
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text(sentTo == null ? Strings.sendCodes : Strings.confirmChange),
          ),
        ],
      ),
    );
  }
}

/// Old number gone: a person at Fidelia checks who the merchant is and moves
/// the shop (fidelia-BE app/api/account.py, recovery requests).
class LostNumberScreen extends StatelessWidget {
  const LostNumberScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.lostNumberTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.support_agent_rounded, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text(Strings.lostNumberIntro),
          const SizedBox(height: 24),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text(Strings.backToSignIn)),
        ],
      ),
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
