import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../core/wallet_change_api.dart';
import '../l10n/strings.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

const _providers = {'wave': 'Wave', 'orange': 'Orange Money', 'mtn': 'MTN MoMo', 'moov': 'Moov Money'};

/// Where customers' payments are paid out, and the safe way to change it.
///
/// The server decides everything that protects the shop's money (password re-entry, the code an admin sends on WhatsApp, the 24 h
/// delay, the first-week cap, "this wasn't me"); this screen only shows the state and asks for each step. Owner only.
class WalletChangeScreen extends ConsumerStatefulWidget {
  const WalletChangeScreen({super.key});

  @override
  ConsumerState<WalletChangeScreen> createState() => _WalletChangeScreenState();
}

class _WalletChangeScreenState extends ConsumerState<WalletChangeScreen> {
  final _account = TextEditingController();
  final _code = TextEditingController();
  WalletState? _state;
  String _provider = 'wave';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _account.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(walletChangeApiProvider).mine();
      if (mounted) setState(() => _state = s);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = walletErrorMessage(e));
    }
  }

  /// Runs one server action, then reloads the state; shows what went wrong in words.
  Future<void> _run(Future<void> Function() action, {String? done}) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
      if (mounted && done != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } on StepUpUnavailable {
      if (mounted) setState(() => _error = Strings.walletPasswordNeeded);
    } on AccountActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = walletErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askPassword() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Strings.walletPasswordTitle),
        content: TextField(controller: c, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: Strings.walletPasswordLabel)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text(Strings.notNow)),
          FilledButton(onPressed: () => Navigator.of(context).pop(c.text), child: const Text(Strings.walletRequest)),
        ],
      ),
    );
  }

  Future<void> _request() async {
    final account = _account.text.trim();
    if (account.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _error = Strings.walletAccount);
      return;
    }
    final password = await _askPassword();
    if (password == null || password.isEmpty || !mounted) return;
    await _run(() async {
      await ref.read(stepUpProvider)(password); // a fresh proof, or StepUpUnavailable
      await ref.read(walletChangeApiProvider).request(provider: _provider, account: account);
      _account.clear();
    }, done: Strings.walletSent);
  }

  Future<void> _confirm() => _run(() async {
        await ref.read(walletChangeApiProvider).confirm(_code.text.trim());
        _code.clear();
      });

  Future<void> _notMe() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Strings.walletNotMeQuestion),
        content: const Text(Strings.walletNotMeHint),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(Strings.notNow)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FideliaColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(Strings.walletNotMe),
          ),
        ],
      ),
    );
    if (sure == true) await _run(() async => ref.read(walletChangeApiProvider).notMe(), done: Strings.walletFrozenDone);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = _state;
    final change = s?.change;
    final open = change != null && change.isOpen;
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.walletTitle)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline_rounded, size: 17, color: FideliaColors.muted),
              const SizedBox(width: 8),
              Expanded(child: Text(Strings.walletIntro, style: text.bodySmall)),
            ]),
            const SizedBox(height: 20),
            if (s == null && _error == null) const LoadingCards(count: 2),
            if (s != null) _CurrentWallet(state: s),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, key: const Key('wallet-error'), style: const TextStyle(color: FideliaColors.danger)),
            ],
            if (s != null && open) ...[const SizedBox(height: 16), _status(change, text)],
            if (s != null && !open) ...[const SizedBox(height: 24), _requestForm(s, text)],
          ],
        ),
      ),
    );
  }

  Widget _status(WalletChange c, TextTheme text) {
    final where = '${_providers[c.provider] ?? c.provider} ${c.accountMasked}';
    switch (c.status) {
      case 'frozen':
        return SoftCard(
          color: FideliaColors.danger.withOpacity(0.08),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(Strings.walletFrozen, style: text.titleSmall?.copyWith(color: FideliaColors.danger)),
            const SizedBox(height: 6),
            const Text(Strings.walletFrozenHint),
          ]),
        );
      case 'confirmed_waiting':
        return SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${Strings.walletWaiting}: $where', style: text.titleSmall),
            const SizedBox(height: 6),
            if (c.activatesAt != null) Text('${Strings.walletWaitingHint} ${_when(c.activatesAt!)}.'),
            const Text(Strings.walletStillOld),
            const SizedBox(height: 12),
            _notMeButton(),
          ]),
        );
      default:
        return SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${Strings.walletPending}: $where', style: text.titleSmall),
            const SizedBox(height: 6),
            const Text(Strings.walletPendingHint),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: Strings.walletCodeLabel, counterText: ''),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy ? null : _confirm, child: const Text(Strings.walletConfirm)),
            const SizedBox(height: 8),
            TextButton(onPressed: _busy ? null : () => _run(() async => ref.read(walletChangeApiProvider).cancel()), child: const Text(Strings.walletCancel)),
            const SizedBox(height: 4),
            _notMeButton(),
          ]),
        );
    }
  }

  Widget _notMeButton() => OutlinedButton(
        onPressed: _busy ? null : _notMe,
        style: OutlinedButton.styleFrom(foregroundColor: FideliaColors.danger),
        child: const Text(Strings.walletNotMe),
      );

  Widget _requestForm(WalletState s, TextTheme text) => SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.hasWallet ? Strings.walletRequestTitle : Strings.walletFirstTitle, style: text.titleSmall),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('wallet-provider'),
            value: _provider,
            decoration: const InputDecoration(labelText: Strings.walletProvider),
            items: [for (final e in _providers.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _provider = v ?? 'wave'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('wallet-account'),
            controller: _account,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: Strings.walletAccount, hintText: '07 01 02 03 04'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _request, child: const Text(Strings.walletRequest)),
        ]),
      );
}

class _CurrentWallet extends StatelessWidget {
  const _CurrentWallet({required this.state});

  final WalletState state;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SoftCard(
      child: Row(children: [
        const Icon(Icons.account_balance_wallet_outlined, color: FideliaColors.green),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(Strings.walletCurrent, style: text.bodySmall),
            if (state.hasWallet)
              Text('${_providers[state.provider] ?? state.provider} ${state.accountMasked}', style: text.titleMedium)
            else ...[
              const Text(Strings.walletNone),
              Text(Strings.walletNoneHint, style: text.bodySmall),
            ],
            if (state.capXof != null) Text('${Strings.walletCapNotice} ${state.capXof} FCFA.', style: text.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

String _when(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} a ${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';

/// What the server's answer means for the merchant, in words.
String walletErrorMessage(ApiException e) {
  if (e is ClientErrorException) {
    final d = e.detail;
    if (d is String) {
      return switch (d) {
        'auth_login_required' || 'step_up_required' => Strings.walletPasswordNeeded,
        'wrong_code' => Strings.walletWrongCode,
        'code_locked' => Strings.walletCodeLocked,
        'no_code' => Strings.walletNoCode,
        'change_in_progress' => Strings.walletInProgress,
        'frozen_review' => Strings.walletFrozenReview,
        'same_wallet' => Strings.walletSame,
        'too_many_requests' => Strings.walletTooMany,
        'sso_session_ended' => Strings.walletSessionEnded,
        'sso_unavailable' => Strings.walletUnavailable,
        _ => d,
      };
    }
  }
  return Strings.teamNeedsConnection;
}
