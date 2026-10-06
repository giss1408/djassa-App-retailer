import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/model/money.dart';
import '../core/model/phone.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import '../ui/money_text.dart';
import '../ui/theme.dart';

/// Records a sale at the counter.
///
/// The whole screen is built around one fact: **the merchant has a customer
/// waiting.** So it asks for an amount, offers a category, and saves. Nothing
/// blocks on the network, and the confirmation appears the moment the row is on
/// disk.
///
/// There is no merchant id here any more. The backend derives the venue from the
/// signed-in account (`app/api/sales.py`), which removed the placeholder this
/// screen used to carry — and with it the possibility of a client naming which
/// business a sale belongs to.
///
/// Visual polish stops at the point where it would cost the merchant a second
/// at the counter: the amount field is still the first thing focused, the
/// keyboard is still numeric-only, and the save button still closes the screen
/// the instant the row is on disk rather than showing a confirmation dialog.
class RecordSaleScreen extends ConsumerStatefulWidget {
  const RecordSaleScreen({super.key});

  /// CI is the first market, so XOF is the default. Once the merchant's outlet
  /// carries a country, this comes from `/api/config/countries`.
  static const defaultCurrency = 'XOF';

  @override
  ConsumerState<RecordSaleScreen> createState() => _RecordSaleScreenState();
}

class _RecordSaleScreenState extends ConsumerState<RecordSaleScreen> {
  final _amount = TextEditingController();
  final _customer = TextEditingController();
  String _type = 'sale';
  // Never pre-ticked: the merchant asks, the customer answers.
  bool _consent = false;
  bool _busy = false;
  String? _error;

  // Pilot measures: how long recording takes, and where merchants give up.
  final _opened = Stopwatch()..start();
  bool _saved = false;
  late final _usage = ref.read(usageTrackerProvider);

  @override
  void initState() {
    super.initState();
    _usage.track('sale_form_opened');
  }

  @override
  void dispose() {
    if (!_saved) {
      // How far the merchant got, never what they typed.
      final step = _amount.text.trim().isEmpty ? 'empty' : (_error != null ? 'error' : 'amount_entered');
      _usage.track('sale_abandoned', {'step': step});
    }
    _amount.dispose();
    _customer.dispose();
    super.dispose();
  }

  /// Parses what the merchant typed into an exact amount.
  ///
  /// Accepts a comma as the decimal mark, because a French keyboard and French
  /// habit both produce `15,50`. Rejects anything else rather than guessing:
  /// a misread amount is money.
  Money? _parseAmount() {
    final raw =
        _amount.text.trim().replaceAll(' ', '').replaceAll(' ', '');
    if (raw.isEmpty) return null;
    final normalized = raw.replaceAll(',', '.');
    try {
      return Money.parse(normalized, RecordSaleScreen.defaultCurrency);
    } on FormatException {
      return null;
    }
  }

  Future<void> _save() async {
    if (_busy) return;

    if (_amount.text.trim().isEmpty) {
      setState(() => _error = Strings.amountRequired);
      return;
    }
    final amount = _parseAmount();
    if (amount == null || amount.isZero || amount.isNegative) {
      setState(() => _error = Strings.amountInvalid);
      return;
    }

    // Checked here, with the customer still at the counter, rather than by the
    // server after sync: a wrong number found hours later cannot be fixed.
    final typed = _customer.text.trim();
    final customer = typed.isEmpty ? null : normalizeIvorianPhone(typed);
    if (typed.isNotEmpty && customer == null) {
      setState(() => _error = Strings.customerPhoneInvalid);
      return;
    }
    if (customer != null && !_consent) {
      setState(() => _error = Strings.customerConsentRequired);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    await ref.read(saleRepositoryProvider).recordSale(
          amount: amount,
          type: _type,
          customerRef: customer,
          customerConsent: customer != null && _consent,
        );
    _saved = true;
    // In 5-second steps (capped at 2 minutes) so a busy day stays a handful
    // of counted entries; the with/without-customer split shows whether the
    // phone-number step is what slows merchants down.
    final seconds = (((_opened.elapsed.inSeconds + 4) ~/ 5) * 5).clamp(5, 120);
    _usage.track('sale_recorded', {'seconds': seconds, 'with_customer': customer != null});

    if (!mounted) return;
    // The sale is on disk. Close immediately — the merchant has a queue of
    // customers, not time for a confirmation dialog.
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final parsed = _parseAmount();

    return Scaffold(
      appBar: AppBar(title: const Text(Strings.recordSale)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                decoration: BoxDecoration(
                  color: DjassaColors.surface,
                  borderRadius: BorderRadius.circular(DjassaRadius.lg),
                  border: Border.all(color: DjassaColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _amount,
                      enabled: !_busy,
                      autofocus: true,
                      // The numeric keypad is the single biggest speed win at
                      // a counter: big keys, no letters to hunt through.
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: false,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        LengthLimitingTextInputFormatter(12),
                      ],
                      style: serifStyle(40),
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() => _error = null),
                      onSubmitted: (_) => _save(),
                      decoration: const InputDecoration(
                        labelText: Strings.amount,
                        hintText: Strings.amountHint,
                        border: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    // Echo the parsed amount back, formatted. It is the
                    // merchant's check against a mistyped digit before the
                    // sale is recorded.
                    if (parsed != null) ...[
                      const SizedBox(height: 4),
                      Text(formatMoney(parsed), style: text.bodyMedium?.copyWith(color: DjassaColors.muted)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(Strings.saleType, style: text.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: Strings.saleTypes.entries.map((entry) {
                  final selected = _type == entry.key;
                  return ChoiceChip(
                    label: Text(entry.value),
                    selected: selected,
                    onSelected:
                        _busy ? null : (_) => setState(() => _type = entry.key),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _customer,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [LengthLimitingTextInputFormatter(20)],
                onChanged: (_) => setState(() => _error = null),
                decoration: const InputDecoration(
                  labelText: Strings.customerOptional,
                  hintText: Strings.customerHint,
                  helperText: Strings.customerEarnsHint,
                  helperMaxLines: 2,
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              if (_customer.text.trim().isNotEmpty)
                CheckboxListTile(
                  value: _consent,
                  onChanged: _busy ? null : (v) => setState(() {
                        _consent = v ?? false;
                        _error = null;
                      }),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(Strings.customerConsent),
                  subtitle: const Text(Strings.customerConsentHint),
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
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Text(Strings.save),
              ),
              const SizedBox(height: 12),
              // Sets the expectation up front, so a queued sale later is not
              // a surprise.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phonelink_lock_outlined, size: 15, color: colors.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(Strings.savedOffline, style: text.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
