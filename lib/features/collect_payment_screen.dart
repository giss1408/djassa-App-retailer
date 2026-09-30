import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/model/money.dart';
import '../core/net/api_exception.dart';
import '../core/payment_api.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import '../ui/money_text.dart';
import '../ui/theme.dart';
import 'fixed_qr_screen.dart';

/// Getting paid by QR: the merchant types the amount, the customer scans the
/// QR with the Djassa app and pays from their own wallet, straight to the
/// merchant's (Djassa never holds the money). The paid sale is recorded by the
/// server as a provider-confirmed event, and the customer earns points.
///
/// Unlike recording a cash sale, this needs a connection: the request lives
/// on the server, and so does the payment.
///
/// While the QR is on screen, the status is checked every [_pollEvery] -- a
/// few hundred bytes each, and only while this screen is open, never in the
/// background -- and stops as soon as the request is paid, expired or
/// cancelled.
class CollectPaymentScreen extends ConsumerStatefulWidget {
  const CollectPaymentScreen({super.key});

  @override
  ConsumerState<CollectPaymentScreen> createState() => _CollectPaymentScreenState();
}

class _CollectPaymentScreenState extends ConsumerState<CollectPaymentScreen> {
  static const _pollEvery = Duration(seconds: 3);

  final _amount = TextEditingController();
  PaymentRequest? _request;
  bool _busy = false;
  String? _error;
  Timer? _poll;
  Timer? _clock;

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    _amount.dispose();
    super.dispose();
  }

  int? get _parsedAmount {
    final raw = _amount.text.replaceAll(RegExp(r'[\s  .]'), '');
    return raw.isEmpty ? null : int.tryParse(raw);
  }

  String _message(ApiException e) {
    if (e is ClientErrorException && e.detail is String) return e.detail! as String;
    return Strings.paymentNeedsConnection;
  }

  Future<void> _create() async {
    final amount = _parsedAmount;
    if (amount == null || !isPayableAmount(amount)) {
      setState(() => _error = Strings.amountRange);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = await ref.read(paymentApiProvider).request(amount);
      if (!mounted) return;
      setState(() => _request = request);
      _startWatching();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startWatching() {
    _poll?.cancel();
    _clock?.cancel();
    // Redraws the countdown once a second, locally: no network involved.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _poll = Timer.periodic(_pollEvery, (_) => _refresh());
  }

  void _stopWatching() {
    _poll?.cancel();
    _clock?.cancel();
    _poll = null;
    _clock = null;
  }

  Future<void> _refresh() async {
    final current = _request;
    if (current == null) return;
    try {
      final latest = await ref.read(paymentApiProvider).status(current.id);
      if (!mounted) return;
      setState(() => _request = latest);
      if (!latest.isOpen) {
        _stopWatching();
        if (latest.isPaid) HapticFeedback.heavyImpact();
      }
    } on ApiException {
      // A dropped poll is not an error the merchant needs to see: the next
      // tick tries again, and the QR stays valid until it expires.
    }
  }

  Future<void> _cancel() async {
    final current = _request;
    if (current == null) return;
    setState(() => _busy = true);
    try {
      final latest = await ref.read(paymentApiProvider).cancel(current.id);
      if (!mounted) return;
      _stopWatching();
      setState(() => _request = latest);
    } on ApiException catch (e) {
      // 409: too late, the customer is paying or has paid. Keep watching.
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    _stopWatching();
    setState(() {
      _request = null;
      _error = null;
      _amount.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    return Scaffold(
      appBar: AppBar(
        title: const Text(Strings.collect),
        actions: [
          IconButton(
            tooltip: Strings.fixedQr,
            icon: const Icon(Icons.qr_code_2_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FixedQrScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            if (request == null) ..._amountForm(context) else ..._requestView(context, request),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, size: 18, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _amountForm(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final parsed = _parsedAmount;
    return [
      Text(Strings.collectIntro, style: text.bodyMedium),
      const SizedBox(height: 16),
      TextField(
        controller: _amount,
        enabled: !_busy,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
        style: serifStyle(40),
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _create(),
        decoration: const InputDecoration(labelText: Strings.amount, hintText: Strings.amountHint),
      ),
      if (parsed != null) ...[
        const SizedBox(height: 4),
        Text(formatMoney(Money.fromMinor(parsed, 'XOF')), style: text.bodyMedium?.copyWith(color: DjassaColors.muted)),
      ],
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _busy ? null : _create,
        icon: const Icon(Icons.qr_code_2_rounded),
        label: Text(_busy ? Strings.creatingQr : Strings.showQr),
      ),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 16, color: DjassaColors.muted),
          const SizedBox(width: 6),
          Expanded(child: Text(Strings.moneyGoesToYou, style: text.bodySmall)),
        ],
      ),
    ];
  }

  List<Widget> _requestView(BuildContext context, PaymentRequest r) {
    final text = Theme.of(context).textTheme;
    final amount = formatMoney(Money.fromMinor(r.amount, 'XOF'));

    if (r.isPaid) {
      return [
        const SizedBox(height: 24),
        const Icon(Icons.check_circle_rounded, size: 88, color: DjassaColors.success),
        const SizedBox(height: 12),
        Text(Strings.paid, textAlign: TextAlign.center, style: text.headlineSmall),
        Text(amount, textAlign: TextAlign.center, style: serifStyle(44)),
        if (r.walletProvider != null)
          Text('${Strings.paidWith} ${_wallet(r.walletProvider!)}', textAlign: TextAlign.center, style: text.bodyMedium),
        if ((r.pointsAwarded ?? 0) > 0) ...[
          const SizedBox(height: 8),
          Text('+${r.pointsAwarded} ${Strings.customerEarned}',
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(color: DjassaColors.green, fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 28),
        FilledButton(onPressed: _reset, child: const Text(Strings.newCollect)),
      ];
    }

    if (!r.isOpen) {
      return [
        const SizedBox(height: 24),
        const Icon(Icons.timer_off_outlined, size: 64, color: DjassaColors.muted),
        const SizedBox(height: 12),
        Text(r.status == 'expired' ? Strings.qrExpired : Strings.qrCancelled,
            textAlign: TextAlign.center, style: text.titleMedium),
        const SizedBox(height: 24),
        FilledButton(onPressed: _reset, child: const Text(Strings.newCollect)),
      ];
    }

    final left = r.expiresAt.difference(DateTime.now().toUtc());
    final mm = left.isNegative ? 0 : left.inMinutes;
    final ss = left.isNegative ? 0 : left.inSeconds % 60;
    return [
      Text(amount, textAlign: TextAlign.center, style: serifStyle(40)),
      const SizedBox(height: 4),
      Text(Strings.scanToPay, textAlign: TextAlign.center, style: text.bodyMedium),
      const SizedBox(height: 16),
      Center(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(DjassaRadius.lg)),
          // Black on white, large quiet zone: what cheap cameras read best.
          child: QrImageView(data: r.qrPayload, size: 240, backgroundColor: Colors.white),
        ),
      ),
      const SizedBox(height: 12),
      Text(Strings.orTypeCode, textAlign: TextAlign.center, style: text.bodySmall),
      SelectableText(r.code,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 4)),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(r.status == 'processing' ? Strings.customerPaying : Strings.waitingForPayment, style: text.bodyMedium),
        ],
      ),
      const SizedBox(height: 4),
      Text('${Strings.expiresIn} $mm:${ss.toString().padLeft(2, '0')}',
          textAlign: TextAlign.center, style: text.bodySmall),
      const SizedBox(height: 20),
      TextButton(onPressed: _busy ? null : _cancel, child: const Text(Strings.cancelQr)),
    ];
  }

  static String _wallet(String provider) => switch (provider) {
        'wave' => 'Wave',
        'orange' => 'Orange Money',
        'mtn' => 'MTN MoMo',
        'moov' => 'Moov Money',
        _ => provider,
      };
}
