import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/model/deal.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import '../ui/back_button.dart';
import 'deals_screen.dart';

enum _Kind { percent, price }

/// Publishes a deal. Three questions (what, how much off, how long) and a
/// preview of what customers will see, so there is no surprise once it is live.
class NewDealScreen extends ConsumerStatefulWidget {
  const NewDealScreen({super.key});

  @override
  ConsumerState<NewDealScreen> createState() => _NewDealScreenState();
}

class _NewDealScreenState extends ConsumerState<NewDealScreen> {
  final _title = TextEditingController();
  final _percent = TextEditingController();
  final _price = TextEditingController();
  final _original = TextEditingController();
  final _description = TextEditingController();
  _Kind _kind = _Kind.price;
  String _duration = '1 semaine';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _percent, _price, _original, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  DealDraft get _draft => DealDraft(
        title: _title.text,
        description: _description.text,
        discountPercent: _kind == _Kind.percent ? int.tryParse(_percent.text) : null,
        price: _kind == _Kind.price ? int.tryParse(_price.text) : null,
        originalPrice: _kind == _Kind.price ? int.tryParse(_original.text) : null,
        duration: Strings.dealDurations[_duration]!,
      );

  Future<void> _publish() async {
    if (_busy) return;
    final draft = _draft;
    final problem = draft.validate(
      titleTooShort: Strings.titleTooShort,
      nothingOffered: Strings.nothingOffered,
      percentRange: Strings.percentRange,
      priceNotLower: Strings.priceNotLower,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dealsApiProvider).publish(draft);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = dealErrorMessage(e);
        });
      }
    }
  }

  void _changed(String _) => setState(() => _error = null);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final draft = _draft;
    final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)];

    return Scaffold(
      appBar: AppBar(leading: const DjassaBackButton(), title: const Text(Strings.newDeal)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                enabled: !_busy,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [LengthLimitingTextInputFormatter(120)],
                onChanged: _changed,
                decoration: const InputDecoration(labelText: Strings.dealTitle, hintText: Strings.dealTitleHint),
              ),
              const SizedBox(height: 20),
              Text(Strings.dealKind, style: text.labelMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                ChoiceChip(
                  label: const Text(Strings.kindPrice),
                  selected: _kind == _Kind.price,
                  onSelected: _busy ? null : (_) => setState(() => _kind = _Kind.price),
                ),
                ChoiceChip(
                  label: const Text(Strings.kindPercent),
                  selected: _kind == _Kind.percent,
                  onSelected: _busy ? null : (_) => setState(() => _kind = _Kind.percent),
                ),
              ]),
              const SizedBox(height: 16),
              if (_kind == _Kind.percent)
                TextField(
                  controller: _percent,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                  onChanged: _changed,
                  decoration: const InputDecoration(labelText: Strings.percent, hintText: Strings.percentHint),
                )
              else ...[
                TextField(
                  controller: _price,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  onChanged: _changed,
                  decoration: const InputDecoration(labelText: Strings.promoPrice),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _original,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  onChanged: _changed,
                  decoration: const InputDecoration(labelText: Strings.originalPrice),
                ),
              ],
              const SizedBox(height: 20),
              Text(Strings.dealDuration, style: text.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in Strings.dealDurations.keys)
                    ChoiceChip(
                      label: Text(label),
                      selected: _duration == label,
                      onSelected: _busy ? null : (_) => setState(() => _duration = label),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _description,
                enabled: !_busy,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [LengthLimitingTextInputFormatter(300)],
                decoration: const InputDecoration(labelText: Strings.dealDescription, hintText: Strings.dealDescriptionHint),
              ),
              const SizedBox(height: 24),
              Text(Strings.preview, style: text.labelMedium),
              const SizedBox(height: 8),
              _Preview(draft: draft),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: text.bodySmall?.copyWith(color: colors.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _publish,
                child: Text(_busy ? Strings.publishing : Strings.publish),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Roughly how the offer reads in the customer app: headline, title, end date.
class _Preview extends StatelessWidget {
  const _Preview({required this.draft});

  final DealDraft draft;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final offer = dealOffer(draft.discountPercent, draft.price, draft.originalPrice);
    final ends = DateTime.now().add(draft.duration);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(offer.isEmpty ? '...' : offer, style: text.headlineMedium?.copyWith(color: colors.primary)),
          const SizedBox(height: 4),
          Text(draft.title.trim().isEmpty ? Strings.dealTitleHint : draft.title.trim(), style: text.titleMedium),
          if (draft.description != null && draft.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(draft.description!.trim(), style: text.bodySmall),
          ],
          const SizedBox(height: 6),
          Text('${Strings.endsOn} ${Strings.shortDate(ends)}', style: text.bodySmall),
        ],
      ),
    );
  }
}
