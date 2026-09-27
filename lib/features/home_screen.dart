import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/sync_service.dart';
import '../core/model/money.dart';
import '../core/model/sale.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import '../ui/money_text.dart';
import 'about_name_screen.dart';
import 'deals_screen.dart';
import 'record_sale_screen.dart';

/// What the merchant sees on opening the app.
///
/// Answers three questions, in this order of importance:
///
/// 1. How much have I taken today?
/// 2. Is anything still stuck on this phone?
/// 3. Where do I record the next sale?
///
/// Question 2 is why the queue is shown in plain words rather than hidden behind
/// a spinner. A merchant who cannot tell what reached the server will not trust
/// the app with their books.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Money? _total;
  List<Sale> _recent = const [];
  int _pending = 0;
  int _rejected = 0;
  bool _loading = true;
  bool _syncing = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(saleRepositoryProvider);
    final total = await repo.totalToday();
    final recent = await repo.recentSales(limit: 20);
    final pending = await repo.pendingCount();
    final rejected = await repo.rejectedCount();
    if (!mounted) return;
    setState(() {
      _total = total;
      _recent = recent;
      _pending = pending;
      _rejected = rejected;
      _loading = false;
    });
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _notice = null;
    });
    final outcome = await ref.read(saleRepositoryProvider).syncNow();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _notice = _noticeFor(outcome);
    });
    await _load();
  }

  /// Turns a sync outcome into something honest and plain.
  ///
  /// An offline attempt is explicitly *not* an error: the sales are safe on the
  /// phone, and saying so is the difference between trust and panic.
  String? _noticeFor(SyncOutcome outcome) {
    if (!outcome.didReachServer) return Strings.noConnection;
    final total = outcome.sent + outcome.alreadyOnServer;
    if (total > 0) return '${Strings.sentOk} ($total)';
    return null;
  }

  Future<void> _openRecordSale() async {
    final recorded = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const RecordSaleScreen()),
    );
    if (recorded != true) return;

    // Show the sale immediately, from the local database.
    await _load();

    // Recording a sale fires a background sync attempt that is deliberately
    // not awaited, so it usually lands a moment after this screen has drawn.
    // Without a second read the merchant sees "1 waiting to send" for a sale
    // that already reached the server, which is exactly the kind of doubt this
    // screen exists to remove.
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Djassa'),
        actions: [
          TextButton(
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
            child: const Text(Strings.signOut),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _TodayCard(total: _total, count: _todayCount, loading: _loading),
              const SizedBox(height: 16),
              _QueueBanner(
                pending: _pending,
                rejected: _rejected,
                syncing: _syncing,
                onSync: _sync,
              ),
              if (_notice != null) ...[
                const SizedBox(height: 12),
                Text(_notice!, style: text.bodySmall),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _openRecordSale,
                child: const Text(Strings.recordSale),
              ),
              const SizedBox(height: 12),
              // Second to recording a sale: deals bring customers in, but the
              // sale at the counter always comes first.
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DealsScreen()),
                ),
                child: const Text(Strings.myDeals),
              ),
              const SizedBox(height: 28),
              Text(Strings.recentSales, style: text.titleMedium),
              const SizedBox(height: 8),
              if (_recent.isEmpty && !_loading)
                Text(Strings.noSalesYet, style: text.bodySmall)
              else
                ..._recent.map((sale) => _SaleRow(
                      sale: sale,
                      onRetry: sale.syncState == SaleSyncState.rejected
                          ? () async {
                              await ref
                                  .read(saleRepositoryProvider)
                                  .retryRejected(sale.localId!);
                              await _sync();
                            }
                          : null,
                    )),
              const SizedBox(height: 32),
              const _AboutNameLink(),
            ],
          ),
        ),
      ),
    );
  }

  int get _todayCount {
    final today = DateTime.now();
    return _recent
        .where((s) =>
            s.recordedAt.year == today.year &&
            s.recordedAt.month == today.month &&
            s.recordedAt.day == today.day)
        .length;
  }
}

class _AboutNameLink extends StatelessWidget {
  const _AboutNameLink();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AboutNameScreen()),
        ),
        child: const Text(Strings.aboutNameLink),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.total,
    required this.count,
    required this.loading,
  });

  final Money? total;
  final int count;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(Strings.today, style: text.labelMedium),
          const SizedBox(height: 6),
          Text(
            loading
                ? '...'
                : total == null
                    ? formatMoney(Money.fromMinor(0, 'XOF'))
                    : formatMoney(total!),
            // Deliberately the largest thing on the screen: it is the number
            // the merchant opens the app to see.
            style: text.headlineMedium,
          ),
          const SizedBox(height: 2),
          Text('$count ${Strings.salesToday}', style: text.bodySmall),
        ],
      ),
    );
  }
}

/// Tells the merchant, in words, what is still on the phone.
class _QueueBanner extends StatelessWidget {
  const _QueueBanner({
    required this.pending,
    required this.rejected,
    required this.syncing,
    required this.onSync,
  });

  final int pending;
  final int rejected;
  final bool syncing;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    if (pending == 0 && rejected == 0) {
      return Text(Strings.allSent, style: text.bodySmall);
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pending > 0)
                Text('$pending ${Strings.waitingToSend}',
                    style: text.bodyMedium),
              if (rejected > 0)
                Text('$rejected ${Strings.needsAttention}',
                    style: text.bodySmall),
            ],
          ),
        ),
        if (pending > 0)
          TextButton(
            onPressed: syncing ? null : onSync,
            child: Text(syncing ? Strings.sending : Strings.sendNow),
          ),
      ],
    );
  }
}

class _SaleRow extends StatelessWidget {
  const _SaleRow({required this.sale, this.onRetry});

  final Sale sale;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    // State is carried by a word, never by colour alone: a merchant may be
    // colour-blind, and a cheap screen in sunlight washes hues out anyway.
    final (label, color) = switch (sale.syncState) {
      SaleSyncState.synced => (Strings.stateSynced, colors.onSurfaceVariant),
      SaleSyncState.pending => (Strings.statePending, colors.onSurface),
      SaleSyncState.rejected => (Strings.stateRejected, colors.error),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatMoney(sale.amount), style: text.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  '${_time(sale.recordedAt)} - $label',
                  style: text.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text(Strings.retry)),
        ],
      ),
    );
  }

  String _time(DateTime at) {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
