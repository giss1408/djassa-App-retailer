import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/model/deal.dart';
import '../core/model/money.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import '../ui/money_text.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'new_deal_screen.dart';

/// The merchant's live offers, and the way to publish a new one.
///
/// Logic is unchanged from the app's original screen: same load, same confirm
/// dialog before ending a deal, same error message that quotes the server's
/// own words rather than a generic failure.
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
      MaterialPageRoute(settings: const RouteSettings(name: 'new_deal'), builder: (_) => const NewDealScreen()),
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
    final atLimit = deals != null && deals.length >= 5;

    return Scaffold(
      appBar: AppBar(title: const Text(Strings.myDeals)),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 17, color: DjassaColors.muted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(Strings.myDealsIntro, style: text.bodySmall)),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: atLimit ? null : _new,
                icon: const Icon(Icons.add_rounded),
                label: const Text(Strings.newDeal),
              ),
              const SizedBox(height: 8),
              Text(
                atLimit ? Strings.maxDealsReached : Strings.maxDealsHint,
                style: text.bodySmall?.copyWith(color: atLimit ? DjassaColors.orangeDeep : null),
              ),
              const SizedBox(height: 24),
              if (_error != null)
                LoadError(onRetry: _load, message: _error!, retryLabel: Strings.retry)
              else if (deals == null)
                const LoadingCards(count: 3)
              else if (deals.isEmpty)
                const EmptyState(icon: Icons.local_offer_outlined, title: Strings.noDeals, message: Strings.noDealsHint)
              else
                for (final d in deals)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DealTile(deal: d, ending: _ending == d.id, onEnd: _ending == null ? () => _end(d) : null),
                  ),
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
    return SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (deal.isFeatured) ...[
                  const Tag(Strings.sponsored, icon: Icons.bolt_rounded, color: DjassaColors.orangeDeep, background: DjassaColors.orangeTint),
                  const SizedBox(height: 8),
                ],
                Text(deal.title, style: text.titleMedium),
                const SizedBox(height: 4),
                Text(dealOffer(deal.discountPercent, deal.price, deal.originalPrice),
                    style: text.bodyMedium?.copyWith(color: DjassaColors.orangeDeep, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    // Flexible: this Row sits in an Expanded column next to a
                    // TextButton whose own width is fixed, so the text here
                    // must be able to shrink rather than push past the card's
                    // edge — the bug a first pass at this row shipped with.
                    Flexible(
                      child: Text(
                        '${Strings.endsOn} ${Strings.shortDate(deal.endsAt)}',
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onEnd,
            child: ending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text(Strings.endDeal),
          ),
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
