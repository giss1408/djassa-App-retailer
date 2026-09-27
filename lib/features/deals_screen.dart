import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/model/deal.dart';
import '../core/model/money.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import '../ui/back_button.dart';
import '../ui/money_text.dart';
import 'new_deal_screen.dart';

/// The merchant's live offers, and the way to publish a new one.
class DealsScreen extends ConsumerStatefulWidget {
  const DealsScreen({super.key});

  @override
  ConsumerState<DealsScreen> createState() => _DealsScreenState();
}

class _DealsScreenState extends ConsumerState<DealsScreen> {
  List<Deal>? _deals;
  String? _error;
  int? _ending;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final deals = await ref.read(dealsApiProvider).mine();
      if (mounted) setState(() => _deals = deals);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = dealErrorMessage(e));
    }
  }

  Future<void> _new() async {
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NewDealScreen()),
    );
    if (published != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(Strings.dealPublished)));
    await _load();
  }

  Future<void> _end(Deal deal) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Strings.endDealConfirm),
        content: Text('${deal.title}\n\n${Strings.endDealConfirmHint}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(Strings.cancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(Strings.endDeal)),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _ending = deal.id);
    try {
      await ref.read(dealsApiProvider).end(deal.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(Strings.dealEnded)));
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dealErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _ending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final deals = _deals;

    return Scaffold(
      appBar: AppBar(leading: const DjassaBackButton(), title: const Text(Strings.myDeals)),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(Strings.myDealsIntro, style: text.bodySmall),
              const SizedBox(height: 20),
              FilledButton(onPressed: _new, child: const Text(Strings.newDeal)),
              const SizedBox(height: 8),
              Text(Strings.maxDealsHint, style: text.bodySmall),
              const SizedBox(height: 24),
              if (_error != null) ...[
                Text(_error!, style: text.bodyMedium),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: _load, child: const Text(Strings.retry)),
                ),
              ] else if (deals == null)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else if (deals.isEmpty) ...[
                Text(Strings.noDeals, style: text.titleMedium),
                const SizedBox(height: 6),
                Text(Strings.noDealsHint, style: text.bodySmall),
              ] else
                for (final d in deals)
                  DealTile(deal: d, ending: _ending == d.id, onEnd: _ending == null ? () => _end(d) : null),
            ],
          ),
        ),
      ),
    );
  }
}

/// One live deal: what it offers, until when, and a way to end it.
class DealTile extends StatelessWidget {
  const DealTile({super.key, required this.deal, required this.onEnd, this.ending = false});

  final Deal deal;
  final VoidCallback? onEnd;
  final bool ending;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (deal.isFeatured) ...[
                  Text(Strings.sponsored, style: text.labelMedium?.copyWith(color: colors.primary)),
                  const SizedBox(height: 4),
                ],
                Text(deal.title, style: text.titleMedium),
                const SizedBox(height: 4),
                Text(dealOffer(deal.discountPercent, deal.price, deal.originalPrice), style: text.bodyMedium),
                Text('${Strings.endsOn} ${Strings.shortDate(deal.endsAt)}', style: text.bodySmall),
              ],
            ),
          ),
          TextButton(onPressed: onEnd, child: Text(ending ? '...' : Strings.endDeal)),
        ],
      ),
    );
  }
}

/// "-20 %", "3 500 F au lieu de 5 000 F" or "3 500 F": the offer in words.
String dealOffer(int? percent, int? price, int? original) {
  if (price != null) {
    return original != null ? '${francs(price)} au lieu de ${francs(original)}' : francs(price);
  }
  if (percent != null) return '-$percent %';
  return '';
}

/// Whole francs CFA, formatted the way the rest of the app shows money.
String francs(int amount) => formatMoney(Money.fromMinor(amount, 'XOF'));

/// The server's own words when it refused (they are French and plain), the
/// connection notice otherwise. Never blames the merchant for the network.
String dealErrorMessage(ApiException e) {
  if (e is ClientErrorException && e.detail is String) return e.detail! as String;
  return Strings.dealsNeedConnection;
}
