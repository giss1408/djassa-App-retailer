import 'dart:math';

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
  const DealsScreen({super.key, this.readOnly = false, this.random});

  /// A cashier sees the shop's deals, to answer customers, but publishing and
  /// ending them stays with the owner. Both record a customer who came with a
  /// deal: whoever is at the counter does.
  final bool readOnly;

  /// Source of the keys that make "Client venu" safe to retry. Tests pass a
  /// seeded one.
  final Random? random;

  @override
  ConsumerState<DealsScreen> createState() => _DealsScreenState();
}

class _DealsScreenState extends ConsumerState<DealsScreen> {
  List<Deal>? _deals;
  DealUseSummary? _summary;
  String? _error;
  int? _ending;
  int? _recording;

  /// The key of a "Client venu" tap whose answer never arrived, per deal. The
  /// next try reuses it, so a visit recorded before the connection dropped is
  /// not recorded twice.
  final _pendingKeys = <int, String>{};
  late final Random _random = widget.random ?? Random.secure();

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
    await _loadSummary();
  }

  /// The week's count. A failure leaves the deals usable: it only hides the card.
  Future<void> _loadSummary() async {
    try {
      final summary = await ref.read(dealsApiProvider).useSummary();
      if (mounted) setState(() => _summary = summary);
    } on ApiException {
      // Shown again on the next refresh.
    }
  }

  String _newKey() => List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  Future<void> _customerCame(Deal deal) async {
    final isNew = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => _FirstVisitSheet(dealTitle: deal.title),
    );
    if (isNew == null || !mounted) return;
    final key = _pendingKeys.putIfAbsent(deal.id, _newKey);
    setState(() => _recording = deal.id);
    try {
      await ref.read(dealsApiProvider).recordUse(deal.id, newCustomer: isNew, key: key);
      _pendingKeys.remove(deal.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isNew ? Strings.newCustomerRecorded : Strings.customerCameRecorded)),
      );
      await _loadSummary();
    } on ClientErrorException catch (e) {
      // The server answered "no" (deal ended, ...): a fresh tap gets a fresh key.
      _pendingKeys.remove(deal.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dealErrorMessage(e))));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dealErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _recording = null);
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
                  const Icon(Icons.info_outline_rounded, size: 17, color: FideliaColors.muted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(Strings.myDealsIntro, style: text.bodySmall)),
                ],
              ),
              const SizedBox(height: 20),
              if (_summary != null) ...[
                _UseSummaryCard(summary: _summary!),
                const SizedBox(height: 20),
              ],
              if (!widget.readOnly) ...[
                FilledButton.icon(
                  onPressed: atLimit ? null : _new,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(Strings.newDeal),
                ),
                const SizedBox(height: 8),
                Text(
                  atLimit ? Strings.maxDealsReached : Strings.maxDealsHint,
                  style: text.bodySmall?.copyWith(color: atLimit ? FideliaColors.orangeDeep : null),
                ),
                const SizedBox(height: 24),
              ],
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
                    child: DealTile(
                      deal: d,
                      ending: _ending == d.id,
                      canEnd: !widget.readOnly,
                      onEnd: _ending == null ? () => _end(d) : null,
                      recording: _recording == d.id,
                      onCustomerCame: _recording == null ? () => _customerCame(d) : null,
                    ),
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
  const DealTile({
    super.key,
    required this.deal,
    required this.onEnd,
    this.ending = false,
    this.canEnd = true,
    this.onCustomerCame,
    this.recording = false,
  });

  final Deal deal;
  final VoidCallback? onEnd;

  /// "Client venu": a customer came to the counter with this deal.
  final VoidCallback? onCustomerCame;
  final bool recording;

  /// False for a cashier: no "end" button at all, rather than a dead one.
  final bool canEnd;
  final bool ending;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DealRibbonBanner(
      ribbon: deal.ribbon,
      // Bottom corner: the top-right holds "Terminer".
      location: BannerLocation.bottomEnd,
      child: SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (deal.isFeatured) ...[
                        const Tag(Strings.sponsored,
                            icon: Icons.bolt_rounded,
                            color: FideliaColors.orangeDeep,
                            background: FideliaColors.orangeTint),
                        const SizedBox(height: 8),
                      ],
                      Text(deal.title, style: text.titleMedium),
                      const SizedBox(height: 4),
                      Text(dealOffer(deal.discountPercent, deal.price, deal.originalPrice),
                          style:
                              text.bodyMedium?.copyWith(color: FideliaColors.orangeDeep, fontWeight: FontWeight.w700)),
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
                if (canEnd)
                  TextButton(
                    onPressed: onEnd,
                    child: ending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text(Strings.endDeal),
                  ),
              ],
            ),
            if (_alertLine(deal.alertStatus) case final line?) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    deal.alertStatus == 'sent' ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(child: Text(line, style: text.bodySmall, maxLines: 2)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            // Left-aligned: the ribbon banner holds the bottom-right corner.
            OutlinedButton.icon(
              onPressed: onCustomerCame,
              icon: recording
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text(Strings.customerCame),
            ),
          ],
        ),
      ),
    );
  }

  /// What the merchant needs to know about the alert; nothing while it is
  /// being sent, or for a demo shop.
  static String? _alertLine(String? status) => switch (status) {
        'sent' => Strings.alertSent,
        'skipped_recent' => Strings.alertSkippedRecent,
        'failed' => Strings.alertFailed,
        _ => null,
      };
}

/// The week's count at the top of the deals: what the customer app brought.
class _UseSummaryCard extends StatelessWidget {
  const _UseSummaryCard({required this.summary});

  final DealUseSummary summary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(Strings.dealUsesTitle, style: text.labelLarge?.copyWith(color: FideliaColors.muted)),
          const SizedBox(height: 6),
          if (summary.uses == 0)
            Text(Strings.dealUsesNone, style: text.bodyMedium)
          else ...[
            Text(Strings.dealUses(summary.uses), style: text.titleMedium),
            const SizedBox(height: 2),
            Text(Strings.dealUsesNew(summary.newCustomers),
                style: text.bodyMedium?.copyWith(color: FideliaColors.orangeDeep, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}

/// One question, two big answers: is this customer new to the shop?
class _FirstVisitSheet extends StatelessWidget {
  const _FirstVisitSheet({required this.dealTitle});

  final String dealTitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(Strings.customerCameTitle(dealTitle), style: text.titleMedium),
            const SizedBox(height: 8),
            Text(Strings.firstVisitQuestion, style: text.bodyMedium),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(Strings.firstVisitYes)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(Strings.firstVisitNo)),
          ],
        ),
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
