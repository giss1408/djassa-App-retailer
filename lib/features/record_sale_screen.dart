import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/model/money.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import '../ui/back_button.dart';
import '../ui/money_text.dart';

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
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
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
        _amount.text.trim().replaceAll('\u00A0', '').replaceAll(' ', '');
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

    setState(() {
      _busy = true;
      _error = null;
    });

    final customer = _customer.text.trim();
    await ref.read(saleRepositoryProvider).recordSale(
          amount: amount,
          type: _type,
          customerRef: customer.isEmpty ? null : customer,
        );

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
      appBar: AppBar(
        // The Material icon font is not bundled, so the default back button
        // has no glyph. See DjassaBackButton.
        leading: const DjassaBackButton(),
        title: const Text(Strings.recordSale),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _amount,
                enabled: !_busy,
                autofocus: true,
                // The numeric keypad is the single biggest speed win at a
                // counter: big keys, no letters to hunt through.
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: false,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  LengthLimitingTextInputFormatter(12),
                ],
                style: text.headlineMedium,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  labelText: Strings.amount,
                  hintText: Strings.amountHint,
                ),
              ),
              const SizedBox(height: 8),
              // Echo the parsed amount back, formatted. It is the merchant's
              // check against a mistyped digit before the sale is recorded.
              Text(
                parsed == null ? '' : formatMoney(parsed),
                style: text.bodyMedium,
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
                decoration: const InputDecoration(
                  labelText: Strings.customerOptional,
                  hintText: Strings.customerHint,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: text.bodySmall?.copyWith(color: colors.error),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? Strings.saving : Strings.save),
              ),
              const SizedBox(height: 12),
              // Sets the expectation up front, so a queued sale later is not a
              // surprise.
              Text(Strings.savedOffline, style: text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
