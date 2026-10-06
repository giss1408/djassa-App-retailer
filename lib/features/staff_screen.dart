import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../core/staff_api.dart';
import '../l10n/strings.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// The owner's team: cashiers who work the till from their own phone.
///
/// A cashier records sales, collects payments and serves points, so nobody
/// has to lend the owner's phone, or the owner's Wave and deals with it.
/// Owner only; the account menu shows it to owners alone.
class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  List<StaffMember>? _team;
  String? _error;
  int? _removing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final team = await ref.read(staffApiProvider).list();
      if (mounted) setState(() => _team = team);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = staffErrorMessage(e));
    }
  }

  Future<void> _add() async {
    final added = await showDialog<StaffMember>(context: context, builder: (_) => const _AddCashierDialog());
    if (added == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(Strings.cashierAdded)));
    await _load();
  }

  Future<void> _remove(StaffMember member) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Strings.removeCashierConfirm),
        content: Text('${member.name ?? member.phoneMasked}\n\n${Strings.removeCashierHint}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(Strings.cancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(Strings.removeCashier)),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _removing = member.id);
    try {
      await ref.read(staffApiProvider).remove(member.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(Strings.cashierRemoved)));
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(staffErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _removing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final team = _team;

    return Scaffold(
      appBar: AppBar(title: const Text(Strings.team)),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 17, color: HossoukoColors.muted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(Strings.teamIntro, style: text.bodySmall)),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(onPressed: _add, icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text(Strings.addCashier)),
              const SizedBox(height: 24),
              if (_error != null)
                LoadError(onRetry: _load, message: _error!, retryLabel: Strings.retry)
              else if (team == null)
                const LoadingCards(count: 2)
              else if (team.isEmpty)
                const EmptyState(icon: Icons.group_outlined, title: Strings.noCashiers, message: Strings.noCashiersHint)
              else
                for (final m in team)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CashierTile(member: m, removing: _removing == m.id, onRemove: _removing == null ? () => _remove(m) : null),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CashierTile extends StatelessWidget {
  const _CashierTile({required this.member, required this.removing, required this.onRemove});

  final StaffMember member;
  final bool removing;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final state = member.hasSignedIn ? Strings.cashierActive : Strings.cashierInvited;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          const Icon(Icons.badge_outlined, color: HossoukoColors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name ?? member.phoneMasked, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(member.name == null ? state : '${member.phoneMasked} - $state', style: text.bodySmall),
              ],
            ),
          ),
          TextButton(onPressed: onRemove, child: Text(removing ? '...' : Strings.removeCashier)),
        ],
      ),
    );
  }
}

class _AddCashierDialog extends ConsumerStatefulWidget {
  const _AddCashierDialog();

  @override
  ConsumerState<_AddCashierDialog> createState() => _AddCashierDialogState();
}

class _AddCashierDialogState extends ConsumerState<_AddCashierDialog> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_phone.text.trim().length < 8) {
      setState(() => _error = Strings.cashierPhoneNeeded);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final member = await ref.read(staffApiProvider).add(phone: _phone.text.trim(), name: _name.text);
      if (mounted) Navigator.of(context).pop(member);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = staffErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text(Strings.addCashier),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofocus: true,
            decoration: const InputDecoration(labelText: Strings.cashierPhone, hintText: Strings.signInPhoneHint),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: Strings.cashierName),
          ),
          const SizedBox(height: 8),
          Text(Strings.addCashierHint, style: text.bodySmall),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: text.bodySmall?.copyWith(color: HossoukoColors.danger)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text(Strings.cancel)),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? '...' : Strings.add)),
      ],
    );
  }
}

/// The server's own French sentence when it refused (number already on a
/// team, owns a shop, ten cashiers), otherwise a plain "needs a connection".
String staffErrorMessage(ApiException e) {
  if (e is ClientErrorException && e.detail is String) return e.detail! as String;
  return Strings.teamNeedsConnection;
}
