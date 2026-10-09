import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/sale_repository.dart' show newIdempotencyKey;
import '../core/layaway_api.dart';
import '../core/model/money.dart';
import '../core/model/phone.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import '../ui/money_text.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

String _f(int amount) => formatMoney(Money.fromMajor(amount, 'XOF'));

int? _amount(String text) {
  final digits = text.replaceAll(RegExp(r'\D'), '');
  final value = int.tryParse(digits);
  return value == null || value <= 0 ? null : value;
}

String _message(ApiException e) =>
    e is ClientErrorException && e.detail is String ? e.detail! as String : Strings.layawayNeedsConnection;

String _statusLabel(LayawayPlan p) => switch (p.status) {
      'completed' => Strings.layawayReady,
      'delivered' => Strings.layawayDelivered,
      'cancelled' => Strings.layawayCancelled,
      _ => p.isOverdue ? Strings.layawayOverdue : '${Strings.layawayRemaining} ${_f(p.remaining)}',
    };

/// "Payer en plusieurs fois": the shop's plans, the ones to act on first.
///
/// Shown only where an admin switched it on for the shop. Needs a connection,
/// unlike recording a sale: the balance lives on the server.
class LayawayScreen extends ConsumerStatefulWidget {
  const LayawayScreen({super.key, required this.settings});

  final LayawaySettings settings;

  @override
  ConsumerState<LayawayScreen> createState() => _LayawayScreenState();
}

class _LayawayScreenState extends ConsumerState<LayawayScreen> {
  List<LayawayPlan>? _plans;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final plans = await ref.read(layawayApiProvider).list();
      // Paid and waiting first, then open ones by date, closed ones last.
      int rank(LayawayPlan p) => p.readyToHandOver ? 0 : (p.isOpen ? 1 : 2);
      plans.sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : a.dueBy.compareTo(b.dueBy));
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  Future<void> _push(Widget screen, String name) async {
    await Navigator.of(context).push(MaterialPageRoute(settings: RouteSettings(name: name), builder: (_) => screen));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final plans = _plans;
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.layawayTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _push(NewLayawayScreen(settings: widget.settings), 'layaway_new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text(Strings.layawayNew),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
            children: [
              Text(Strings.layawayIntro, style: text.bodySmall),
              const SizedBox(height: 16),
              if (_error != null)
                Text(_error!, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error))
              else if (plans == null)
                const LoadingCards(count: 3)
              else if (plans.isEmpty)
                const EmptyState(
                    icon: Icons.inventory_2_outlined, title: Strings.layawayNone, message: Strings.layawayNoneHint)
              else
                SoftCard(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      for (final p in plans)
                        ListTile(
                          title: Text(p.item, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              LinearProgressIndicator(value: p.progress, minHeight: 6),
                              const SizedBox(height: 4),
                              Text('${p.customer ?? ''} - ${_statusLabel(p)}', style: text.bodySmall),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _push(LayawayPlanScreen(plan: p), 'layaway_plan'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One plan: what is paid, what is left, and the next step.
class LayawayPlanScreen extends ConsumerStatefulWidget {
  const LayawayPlanScreen({super.key, required this.plan, this.random});

  final LayawayPlan plan;
  final Random? random;

  @override
  ConsumerState<LayawayPlanScreen> createState() => _LayawayPlanScreenState();
}

class _LayawayPlanScreenState extends ConsumerState<LayawayPlanScreen> {
  late LayawayPlan _plan = widget.plan;
  late final Random _random = widget.random ?? Random.secure();
  bool _busy = false;
  String? _error;

  /// Kept across retries of one payment, so a dropped response followed by a
  /// second tap is counted once; a new key only once it went through.
  String? _paymentKey;

  // Owned by the screen, not the dialog: disposing them as the dialog closes
  // would pull them out from under its exit animation.
  final _amountField = TextEditingController();
  final _reasonField = TextEditingController();
  final _refundField = TextEditingController();

  @override
  void dispose() {
    for (final c in [_amountField, _reasonField, _refundField]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<LayawayPlan> Function(LayawayApi api) call) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plan = await call(ref.read(layawayApiProvider));
      if (mounted) setState(() => _plan = plan);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _message(e));
      rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _ask(String title, List<Widget> Function(void Function() submit) fields) => showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: fields(() => Navigator.of(context).pop('ok'))),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text(Strings.cancel)),
            TextButton(onPressed: () => Navigator.of(context).pop('ok'), child: const Text(Strings.ok)),
          ],
        ),
      );

  Future<void> _addPayment() async {
    final controller = _amountField..clear();
    final answer = await _ask(
        Strings.layawayAddPayment,
        (submit) => [
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                    labelText: Strings.layawayPaymentAmount,
                    helperText: '${Strings.layawayRemaining} ${_f(_plan.remaining)}'),
              ),
            ]);
    final amount = _amount(controller.text);
    if (answer == null || amount == null) return;
    final key = _paymentKey ??= newIdempotencyKey(_random);
    try {
      await _run((api) => api.pay(_plan.id, amount: amount, key: key));
      _paymentKey = null;
    } on ApiException {
      // Shown on screen; the key stays for the retry.
    }
  }

  Future<void> _handOver() async {
    final ok = await _ask(Strings.layawayHandOver, (_) => [Text('${_plan.item}\n\n${Strings.layawayHandOverHint}')]);
    if (ok == null) return;
    try {
      await _run((api) => api.handOver(_plan.id));
    } on ApiException {
      // Shown on screen.
    }
  }

  Future<void> _cancel() async {
    final reason = _reasonField..clear();
    final refunded = _refundField..text = '${_plan.paid}';
    final ok = await _ask(
        Strings.layawayCancel,
        (_) => [
              TextField(controller: reason, decoration: const InputDecoration(labelText: Strings.layawayCancelReason)),
              TextField(
                controller: refunded,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                    labelText: Strings.layawayRefunded, helperText: '${Strings.layawayPaid} ${_f(_plan.paid)}'),
              ),
            ]);
    final why = reason.text.trim();
    final back = int.tryParse(refunded.text) ?? 0;
    if (ok == null || why.length < 2) return;
    try {
      await _run((api) => api.cancel(_plan.id, reason: why, refunded: back));
    } on ApiException {
      // Shown on screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = _plan;
    final isOwner = ref.watch(sessionProvider).isOwner;
    return Scaffold(
      appBar: AppBar(title: Text(p.item)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.customer ?? '', style: text.labelMedium),
                  const SizedBox(height: 8),
                  Text('${_f(p.paid)} / ${_f(p.price)}', style: serifStyle(26, color: FideliaColors.orangeDeep)),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: p.progress, minHeight: 8),
                  const SizedBox(height: 8),
                  Text(_statusLabel(p), style: text.bodySmall),
                  Text('${Strings.layawayDueBy} ${Strings.shortDate(p.dueBy)}', style: text.bodySmall),
                  if (p.refundedAmount != null)
                    Text('${Strings.layawayRefunded} : ${_f(p.refundedAmount!)}', style: text.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (p.isOpen)
              FilledButton.icon(
                onPressed: _busy ? null : _addPayment,
                icon: const Icon(Icons.add_card_rounded),
                label: const Text(Strings.layawayAddPayment),
              ),
            if (p.readyToHandOver)
              FilledButton.icon(
                onPressed: _busy ? null : _handOver,
                icon: const Icon(Icons.redeem_rounded),
                label: const Text(Strings.layawayHandOver),
              ),
            if (!p.isClosed && isOwner)
              TextButton(onPressed: _busy ? null : _cancel, child: const Text(Strings.layawayCancel)),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            const SectionHeader(Strings.layawayPayments),
            SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  for (final i in p.installments.reversed)
                    ListTile(
                      dense: true,
                      title: Text(_f(i.amount)),
                      trailing:
                          Text('${Strings.shortDate(i.paidAt)} ${Strings.shortTime(i.paidAt)}', style: text.bodySmall),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opening a plan: the good, its fixed price, the end date, the first payment,
/// and the terms read to the customer before anything is recorded.
class NewLayawayScreen extends ConsumerStatefulWidget {
  const NewLayawayScreen({super.key, required this.settings, this.random, this.now});

  final LayawaySettings settings;
  final Random? random;
  final DateTime? now;

  @override
  ConsumerState<NewLayawayScreen> createState() => _NewLayawayScreenState();
}

class _NewLayawayScreenState extends ConsumerState<NewLayawayScreen> {
  final _phone = TextEditingController();
  final _item = TextEditingController();
  final _price = TextEditingController();
  final _first = TextEditingController();
  late final Random _random = widget.random ?? Random.secure();
  late final Map<String, int> _durations = {
    for (final e in Strings.layawayDurations.entries)
      if (e.value <= widget.settings.maxDays) e.key: e.value,
  };
  late String _duration = _durations.keys.contains('3 mois') ? '3 mois' : _durations.keys.first;
  bool _agreed = false;
  bool _busy = false;
  String? _error;
  String? _key;

  @override
  void dispose() {
    for (final c in [_phone, _item, _price, _first]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime get _dueBy => (widget.now ?? DateTime.now()).add(Duration(days: _durations[_duration]!));

  String get _terms => widget.settings.termsFor(
        item: _item.text.trim().isEmpty ? '...' : _item.text.trim(),
        price: _amount(_price.text) == null ? '...' : _f(_amount(_price.text)!).replaceAll(' F', ''),
        dueBy: Strings.shortDate(_dueBy),
      );

  String? _check() {
    if (normalizeIvorianPhone(_phone.text) == null) return Strings.customerPhoneInvalid;
    if (_item.text.trim().length < 2) return Strings.layawayItemMissing;
    final price = _amount(_price.text);
    if (price == null) return Strings.layawayInvalidAmount;
    if (price > widget.settings.maxPrice) return '${Strings.layawayPriceTooHigh} ${_f(widget.settings.maxPrice)}';
    // Required: the first payment's key is what makes a retried "open" return
    // the same plan instead of a second one.
    final first = _amount(_first.text);
    if (first == null) return Strings.layawayFirstMissing;
    if (first > price) return '${Strings.layawayRemaining} ${_f(price)}';
    return null;
  }

  Future<void> _submit() async {
    if (_busy || !_agreed) return;
    final problem = _check();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // One key per attempt to open this plan, kept across retries.
    final key = _key ??= newIdempotencyKey(_random);
    try {
      final plan = await ref.read(layawayApiProvider).open(
            customerPhone: normalizeIvorianPhone(_phone.text)!,
            item: _item.text.trim(),
            price: _amount(_price.text)!,
            dueBy: _dueBy,
            termsVersion: widget.settings.termsVersion,
            key: key,
            firstInstallment: _amount(_first.text),
          );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
          settings: const RouteSettings(name: 'layaway_plan'), builder: (_) => LayawayPlanScreen(plan: plan)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    void changed(String _) => setState(() {
          _error = null;
          _agreed = false;
        });
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.layawayTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [LengthLimitingTextInputFormatter(20)],
              onChanged: changed,
              decoration: const InputDecoration(labelText: Strings.phoneLabel, prefixIcon: Icon(Icons.phone_outlined)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _item,
              inputFormatters: [LengthLimitingTextInputFormatter(120)],
              onChanged: changed,
              decoration: const InputDecoration(labelText: Strings.layawayItem, hintText: Strings.layawayItemHint),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
              onChanged: changed,
              decoration: const InputDecoration(labelText: Strings.layawayPrice),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _duration,
              decoration: const InputDecoration(labelText: Strings.layawayDueBy),
              items: [for (final d in _durations.keys) DropdownMenuItem(value: d, child: Text(d))],
              onChanged: (d) => setState(() {
                _duration = d ?? _duration;
                _agreed = false;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _first,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
              onChanged: changed,
              decoration: const InputDecoration(labelText: Strings.layawayFirst, hintText: Strings.layawayFirstHint),
            ),
            const SizedBox(height: 20),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Strings.layawayTerms, style: text.labelMedium),
                  const SizedBox(height: 6),
                  Text(_terms, key: const Key('layaway_terms'), style: text.bodyMedium),
                ],
              ),
            ),
            // Any edit above clears the box: the customer agrees to the terms
            // as finally written, not an earlier draft.
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v ?? false),
              title: const Text(Strings.layawayAgree),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_error != null) ...[
              Text(_error!, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: _busy || !_agreed ? null : _submit,
              child: Text(_busy ? Strings.layawayOpening : Strings.layawayOpen),
            ),
          ],
        ),
      ),
    );
  }
}
