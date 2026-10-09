import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/env.dart';
import '../core/data/sync_service.dart';
import '../core/layaway_api.dart';
import '../core/model/money.dart';
import '../core/model/sale.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import '../ui/money_text.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'about_name_screen.dart';
import 'account_screen.dart';
import 'collect_payment_screen.dart';
import 'customer_points_screen.dart';
import 'deals_screen.dart';
import 'layaway_screen.dart';
import 'media_screen.dart';
import 'record_sale_screen.dart';
import 'shop_location_screen.dart';
import 'staff_screen.dart';
import 'wave_connect_screen.dart';

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
///
/// The logic below is unchanged from the app's original screen: same load
/// order, same delayed re-read after recording a sale (to catch up with the
/// background sync it deliberately does not await), same honest "offline is
/// not an error" framing. Only the presentation changed.
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

  /// Null until known, and when the shop does not offer layaway: the button
  /// only appears where an admin switched it on.
  LayawaySettings? _layaway;

  @override
  void initState() {
    super.initState();
    _load();
    _loadLayaway();
  }

  Future<void> _loadLayaway() async {
    try {
      final settings = await ref.read(layawayApiProvider).settings();
      if (mounted && settings.enabled) setState(() => _layaway = settings);
    } catch (_) {
      // Offline or an older server: no button, nothing else changes.
    }
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
  /// Pilot: after 4 pm, once a day, until answered.
  bool get _askDailyReport {
    final usage = ref.read(usageTrackerProvider);
    return Env.pilotDailyReport && usage.enabled && DateTime.now().hour >= 16 && !usage.trackedToday('daily_report');
  }

  void _answerDailyReport(int estimate) {
    ref.read(usageTrackerProvider)
      ..track('daily_report', {'sales_estimate': estimate})
      ..markToday('daily_report');
    setState(() => _notice = Strings.dailyReportThanks);
  }

  String? _noticeFor(SyncOutcome outcome) {
    if (!outcome.didReachServer) return Strings.noConnection;
    final total = outcome.sent + outcome.alreadyOnServer;
    if (total > 0) return '${Strings.sentOk} ($total)';
    return null;
  }

  Future<void> _openRecordSale() async {
    final recorded = await Navigator.of(context).push<bool>(
      MaterialPageRoute(settings: const RouteSettings(name: 'record_sale'), builder: (_) => const RecordSaleScreen()),
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

  Future<void> _confirmSignOut() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Strings.signOutConfirm),
        content: const Text(Strings.signOutConfirmHint),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(Strings.cancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(Strings.signOut)),
        ],
      ),
    );
    if (sure == true) ref.read(sessionProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    final username = session.username;
    final name = username == null || username.isEmpty ? null : '${username[0].toUpperCase()}${username.substring(1)}';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Same brand header as the customer app's home tab: greeting,
            // wordmark-style initial, and the day's total riding over the
            // gradient's bottom edge.
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 54),
                  child: PatternedSurface(
                    gradient: FideliaColors.headerGradient,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(FideliaRadius.xl + 4)),
                    padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 14, 12, 84),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(Strings.greeting.toUpperCase(),
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                              const SizedBox(height: 2),
                              Text(name ?? 'Fidelia', style: serifStyle(36, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text(session.isOwner ? Strings.homeTagline : Strings.cashierBadge,
                                  style: TextStyle(color: Colors.white.withOpacity(0.88), fontSize: 13.5)),
                            ],
                          ),
                        ),
                        _AccountMenu(initial: name?[0] ?? 'D', isOwner: session.isOwner, onSignOut: _confirmSignOut),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 0,
                  child: _TodayCard(total: _total, count: _todayCount, loading: _loading),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Sync state stays in plain words, not a spinner — the one
                  // rule this app cannot trade away for a nicer visual, since
                  // it is what makes a merchant trust the app with their books.
                  _QueueBanner(pending: _pending, rejected: _rejected, syncing: _syncing, onSync: _sync),
                  if (_askDailyReport) ...[
                    const SizedBox(height: 12),
                    _DailyReportCard(onAnswer: _answerDailyReport),
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, size: 16, color: FideliaColors.success),
                        const SizedBox(width: 6),
                        Expanded(child: Text(_notice!, style: text.bodySmall)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.point_of_sale_rounded,
                          label: Strings.recordSale,
                          color: Colors.white,
                          background: FideliaColors.orangeDeep,
                          onTap: _openRecordSale,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Getting paid by QR: the other way a sale reaches the
                      // books, confirmed by the wallet rather than typed.
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.qr_code_2_rounded,
                          label: Strings.collect,
                          color: Colors.white,
                          background: FideliaColors.green,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: 'collect_payment'), builder: (_) => const CollectPaymentScreen())),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.local_offer_rounded,
                          label: Strings.myDeals,
                          color: FideliaColors.orangeDeep,
                          background: FideliaColors.orangeTint,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: 'deals'), builder: (_) => DealsScreen(readOnly: !session.isOwner))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.stars_rounded,
                          label: Strings.customerPoints,
                          color: FideliaColors.green,
                          background: FideliaColors.greenTint,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: 'customer_points'), builder: (_) => const CustomerPointsScreen())),
                        ),
                      ),
                    ],
                  ),
                  if (_layaway != null) ...[
                    const SizedBox(height: 12),
                    _QuickAction(
                      icon: Icons.inventory_2_rounded,
                      label: Strings.layawayTitle,
                      color: FideliaColors.orangeDeep,
                      background: FideliaColors.orangeTint,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          settings: const RouteSettings(name: 'layaway'), builder: (_) => LayawayScreen(settings: _layaway!))),
                    ),
                  ],
                  const SizedBox(height: 28),
                  const SectionHeader(Strings.recentSales),
                  if (_recent.isEmpty && !_loading)
                    const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: Strings.noSalesYet,
                      message: Strings.noSalesYetHint,
                    )
                  else if (_loading)
                    const LoadingCards(count: 3)
                  else
                    SoftCard(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          for (final sale in _recent)
                            _SaleRow(
                              sale: sale,
                              onRetry: sale.syncState == SaleSyncState.rejected
                                  ? () async {
                                      await ref.read(saleRepositoryProvider).retryRejected(sale.localId!);
                                      await _sync();
                                    }
                                  : null,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int get _todayCount {
    final today = DateTime.now();
    return _recent.where((s) => s.recordedAt.year == today.year && s.recordedAt.month == today.month && s.recordedAt.day == today.day).length;
  }
}

/// Initial in a translucent disc; opens sign-out and the name explainer.
/// Same shape as the customer app's account menu. A cashier sees only their
/// account, the explainer and sign-out: the shop's settings are the owner's.
class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({required this.initial, required this.isOwner, required this.onSignOut});

  final String initial;
  final bool isOwner;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(suggestionsLinkProvider).valueOrNull;
    return PopupMenuButton<String>(
      tooltip: Strings.menu,
      offset: const Offset(0, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FideliaRadius.md)),
      onSelected: (v) {
        if (v == 'media') {
          Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: 'media'), builder: (_) => const MediaScreen()));
        } else if (v == 'account') {
          Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: 'account'), builder: (_) => const AccountScreen()));
        } else if (v == 'about') {
          Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: 'about_name'), builder: (_) => const AboutNameScreen()));
        } else if (v == 'wave') {
          Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: 'wave_connect'), builder: (_) => const WaveConnectScreen()));
        } else if (v == 'team') {
          Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: 'team'), builder: (_) => const StaffScreen()));
        } else if (v == 'location') {
          Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: 'shop_location'), builder: (_) => const ShopLocationScreen()));
        } else if (v == 'suggest' && suggestions != null) {
          launchUrl(Uri.parse(suggestions), mode: LaunchMode.externalApplication).then((ok) {
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(Strings.suggestionsFailed)));
            }
          });
        } else if (v == 'logout') {
          onSignOut();
        }
      },
      itemBuilder: (_) => [
        // The shop's settings: owner only.
        if (isOwner) ...const [
        PopupMenuItem(
          value: 'team',
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.group_outlined), title: Text(Strings.team)),
        ),
        PopupMenuItem(
          value: 'media',
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.photo_library_outlined), title: Text(Strings.mediaMenu)),
        ),
        PopupMenuItem(
          value: 'wave',
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.account_balance_wallet_outlined), title: Text(Strings.waveMenu)),
        ),
        PopupMenuItem(
          value: 'location',
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.storefront_outlined), title: Text(Strings.shopLocation)),
        ),
        ],
        const PopupMenuItem(
          value: 'account',
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.manage_accounts_outlined), title: Text(Strings.account)),
        ),
        const PopupMenuItem(
          value: 'about',
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.auto_stories_outlined), title: Text(Strings.aboutNameLink)),
        ),
        if (suggestions != null)
          const PopupMenuItem(
            value: 'suggest',
            child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.help_outline_rounded), title: Text(Strings.suggestions)),
          ),
        const PopupMenuItem(
          value: 'logout',
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.logout_rounded), title: Text(Strings.signOut)),
        ),
      ],
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.only(top: 4, right: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.5),
        ),
        child: Text(initial.toUpperCase(), style: serifStyle(22, color: Colors.white, height: 1)),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.total, required this.count, required this.loading});

  final Money? total;
  final int count;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return PatternedSurface(
      gradient: FideliaColors.loyaltyGradient,
      borderRadius: BorderRadius.circular(FideliaRadius.lg),
      boxShadow: fideliaShadowStrong,
      patternOpacity: 0.07,
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Strings.today.toUpperCase(),
                    style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                const SizedBox(height: 4),
                // Deliberately the largest thing on the screen: it is the
                // number the merchant opens the app to see.
                Text(
                  loading ? '...' : formatMoney(total ?? Money.fromMinor(0, 'XOF')),
                  style: serifStyle(38, color: Colors.white, height: 1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text('$count ${Strings.salesToday}',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tells the merchant, in words, what is still on the phone. Unchanged rule
/// from the app's original banner: state is a word, not a colour, because a
/// cheap screen in sunlight washes hues out and a merchant may be colour-blind.
class _QueueBanner extends StatelessWidget {
  const _QueueBanner({required this.pending, required this.rejected, required this.syncing, required this.onSync});

  final int pending;
  final int rejected;
  final bool syncing;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    if (pending == 0 && rejected == 0) {
      return Row(
        children: [
          const Icon(Icons.check_circle_rounded, size: 18, color: FideliaColors.success),
          const SizedBox(width: 8),
          Text(Strings.allSent, style: text.bodyMedium),
        ],
      );
    }

    return SoftCard(
      color: rejected > 0 ? const Color(0xFFFDE4E4) : FideliaColors.sand,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Icon(
            rejected > 0 ? Icons.error_outline_rounded : Icons.cloud_upload_outlined,
            color: rejected > 0 ? FideliaColors.danger : FideliaColors.orangeDeep,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (pending > 0) Text(pending == 1 ? Strings.waitingToSendOne : '$pending ${Strings.waitingToSend}', style: text.bodyMedium),
                if (rejected > 0)
                  Text(rejected == 1 ? Strings.needsAttentionOne : '$rejected ${Strings.needsAttention}',
                      style: text.bodySmall?.copyWith(color: FideliaColors.danger)),
              ],
            ),
          ),
          if (pending > 0)
            TextButton(
              onPressed: syncing ? null : onSync,
              child: Text(syncing ? Strings.sending : Strings.sendNow),
            ),
        ],
      ),
    );
  }
}

/// Icon tile for the two things a merchant does most: record a sale, manage
/// deals. Same shape as the customer app's home-tab quick actions.
class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap, required this.color, required this.background});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(FideliaRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FideliaRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: color),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
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

    // State is carried by a word and an icon, never by colour alone: a
    // merchant may be colour-blind, and a cheap screen in sunlight washes
    // hues out anyway.
    final (label, color, icon) = switch (sale.syncState) {
      SaleSyncState.synced => (Strings.stateSynced, FideliaColors.muted, Icons.check_rounded),
      SaleSyncState.pending => (Strings.statePending, FideliaColors.ink, Icons.schedule_rounded),
      SaleSyncState.rejected => (Strings.stateRejected, FideliaColors.danger, Icons.error_outline_rounded),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatMoney(sale.amount), style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${Strings.shortTime(sale.recordedAt)} - $label', style: text.bodySmall?.copyWith(color: color)),
                // Shown so the merchant can tell the customer what they earned.
                if ((sale.pointsAwarded ?? 0) > 0)
                  Text('+${sale.pointsAwarded} ${Strings.pointsShort}',
                      style: text.bodySmall?.copyWith(color: FideliaColors.green, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text(Strings.retry)),
        ],
      ),
    );
  }
}

/// Pilot: "how many sales today, roughly?", one tap, once a day. Ranges
/// rather than a number to type: quicker at closing time, and close enough
/// for a share. Each range is sent as its middle value.
class _DailyReportCard extends StatelessWidget {
  const _DailyReportCard({required this.onAnswer});

  final void Function(int estimate) onAnswer;

  static const _ranges = [('0-5', 3), ('6-10', 8), ('11-20', 15), ('21-50', 35), ('50+', 60)];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SoftCard(
      color: FideliaColors.sand,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(Strings.dailyReportQuestion, style: text.titleSmall),
          const SizedBox(height: 2),
          Text(Strings.dailyReportHint, style: text.bodySmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, estimate) in _ranges)
                ActionChip(label: Text(label), onPressed: () => onAnswer(estimate)),
            ],
          ),
        ],
      ),
    );
  }
}
