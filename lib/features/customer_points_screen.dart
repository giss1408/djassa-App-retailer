import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/loyalty_api.dart';
import '../core/model/phone.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// A customer's points at this venue, and the reward handed over the counter.
///
/// This closes the loyalty loop for a cash customer who gave their number: they
/// earned points on each sale, and here the merchant tells them where they
/// stand and gives them their reward — no customer app needed.
///
/// Needs a connection, unlike recording a sale: the balance lives on the
/// server, and handing over a reward must be checked there so the same points
/// cannot be spent twice from two phones.
class CustomerPointsScreen extends ConsumerStatefulWidget {
  const CustomerPointsScreen({super.key});

  @override
  ConsumerState<CustomerPointsScreen> createState() => _CustomerPointsScreenState();
}

class _CustomerPointsScreenState extends ConsumerState<CustomerPointsScreen> {
  final _phone = TextEditingController();
  CounterLoyalty? _loyalty;

  /// The normalised number the shown balance belongs to. Redeeming uses this,
  /// not the text field, so editing the field after a lookup cannot spend a
  /// different customer's points.
  String? _lookedUpPhone;
  bool _busy = false;
  int? _givingRewardId;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  String _message(ApiException e) {
    if (e is ClientErrorException && e.statusCode == 409) return Strings.notEnoughPoints;
    if (e is ClientErrorException && e.detail is String) return e.detail! as String;
    return Strings.pointsNeedConnection;
  }

  Future<void> _lookUp() async {
    if (_busy) return;
    final phone = normalizeIvorianPhone(_phone.text);
    if (phone == null) {
      setState(() => _error = Strings.customerPhoneInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final loyalty = await ref.read(loyaltyApiProvider).lookUp(phone);
      if (!mounted) return;
      setState(() {
        _loyalty = loyalty;
        _lookedUpPhone = phone;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _give(CounterReward reward) async {
    final phone = _lookedUpPhone;
    if (phone == null || _givingRewardId != null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Strings.giveConfirm),
        content: Text('${reward.title}\n\n${Strings.giveConfirmHint}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(Strings.cancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(Strings.give)),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _givingRewardId = reward.id;
      _error = null;
    });
    try {
      final voucher = await ref.read(loyaltyApiProvider).redeem(phone: phone, rewardId: reward.id);
      if (!mounted) return;
      final loyalty = _loyalty!;
      setState(() {
        _loyalty = CounterLoyalty(customer: loyalty.customer, points: voucher.remainingPoints, rewards: loyalty.rewards);
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(Strings.voucherTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(voucher.rewardTitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Text(Strings.voucherCode, style: Theme.of(context).textTheme.labelMedium),
              Text(voucher.code, style: serifStyle(34, color: HossoukoColors.orangeDeep)),
              const SizedBox(height: 8),
              Text('${Strings.remainingPoints} : ${voucher.remainingPoints} ${Strings.pointsShort}'),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text(Strings.ok))],
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _givingRewardId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final loyalty = _loyalty;

    return Scaffold(
      appBar: AppBar(title: const Text(Strings.customerPoints)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(Strings.customerPointsIntro, style: text.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _phone,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.phone,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [LengthLimitingTextInputFormatter(20)],
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _lookUp(),
              onChanged: (_) => setState(() => _error = null),
              decoration: const InputDecoration(
                labelText: Strings.phoneLabel,
                hintText: Strings.customerHint,
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _lookUp,
              child: Text(_busy ? Strings.lookingUp : Strings.lookUp),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, size: 18, color: colors.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: text.bodySmall?.copyWith(color: colors.error))),
                ],
              ),
            ],
            if (loyalty != null) ...[
              const SizedBox(height: 24),
              PatternedSurface(
                gradient: HossoukoColors.loyaltyGradient,
                borderRadius: BorderRadius.circular(HossoukoRadius.lg),
                patternOpacity: 0.07,
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loyalty.customer,
                        style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('${loyalty.points}', style: serifStyle(40, color: Colors.white, height: 1)),
                    Text(Strings.pointsHere,
                        style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (loyalty.rewards.isEmpty)
                const EmptyState(icon: Icons.card_giftcard_outlined, title: Strings.noRewards)
              else
                SoftCard(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      for (final reward in loyalty.rewards)
                        _RewardRow(
                          reward: reward,
                          points: loyalty.points,
                          giving: _givingRewardId == reward.id,
                          onGive: _givingRewardId == null ? () => _give(reward) : null,
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({required this.reward, required this.points, required this.giving, required this.onGive});

  final CounterReward reward;
  final int points;
  final bool giving;
  final VoidCallback? onGive;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final affordable = points >= reward.costPoints;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reward.title, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                // What is missing, in points, rather than a greyed-out button
                // with no reason: the merchant can tell the customer.
                Text(
                  affordable
                      ? '${reward.costPoints} ${Strings.pointsShort}'
                      : '${reward.costPoints} ${Strings.pointsShort} - ${Strings.pointsMissing} ${reward.costPoints - points}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          if (affordable)
            TextButton(onPressed: onGive, child: Text(giving ? Strings.giving : Strings.give)),
        ],
      ),
    );
  }
}
