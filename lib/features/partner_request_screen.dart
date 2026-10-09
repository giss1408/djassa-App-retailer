import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/config/env.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import 'account_screen.dart' show ErrorLine;

/// A merchant asks to join. The phone is proven by SMS code and becomes their
/// Fidelia Pro login once an agent has called and an admin approved; the shop
/// itself is created then, from what is typed here.
class PartnerRequestScreen extends ConsumerStatefulWidget {
  const PartnerRequestScreen({super.key});

  @override
  ConsumerState<PartnerRequestScreen> createState() => _PartnerRequestScreenState();
}

class _PartnerRequestScreenState extends ConsumerState<PartnerRequestScreen> {
  final _phone = TextEditingController(text: Env.devPhone);
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _shop = TextEditingController();
  final _commune = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  String _category = Strings.partnerCategories.keys.first;
  String? _wallet = 'wave';
  String? _sentTo;
  String? _done;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_phone, _code, _name, _shop, _commune, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(authRepositoryProvider).requestPartnerCode(_phone.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case CodeSent(:final phoneMasked, :final devCode):
          _sentTo = phoneMasked;
          if (devCode != null && !Env.isRelease) _code.text = devCode;
        case CodeRequestRefused(:final message) || CodeRequestUnavailable(:final message):
          _error = message;
      }
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_name.text.trim().length < 2 || _shop.text.trim().length < 2 || _commune.text.trim().length < 2) {
      setState(() => _error = Strings.partnerMissing);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await ref.read(authRepositoryProvider).filePartnerRequest(
            phone: _phone.text.trim(),
            code: _code.text,
            contactName: _name.text.trim(),
            shopName: _shop.text.trim(),
            category: _category,
            commune: _commune.text.trim(),
            address: _address.text.trim(),
            walletProvider: _wallet,
            notes: _notes.text.trim(),
          );
      if (mounted) setState(() => _done = message);
    } on AccountActionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = _done;
    if (done != null) {
      return Scaffold(
        appBar: AppBar(title: const Text(Strings.partnerTitle)),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Icon(Icons.storefront_rounded, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(Strings.requestSent, style: text.titleLarge),
          const SizedBox(height: 8),
          Text(done),
          const SizedBox(height: 24),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text(Strings.backToSignIn)),
        ]),
      );
    }

    final codeStep = _sentTo != null;
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.partnerTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(Strings.partnerIntro),
          const SizedBox(height: 20),
          TextField(
            controller: _phone,
            enabled: !_busy && !codeStep,
            keyboardType: TextInputType.phone,
            enableSuggestions: false,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(20)],
            decoration: const InputDecoration(
              labelText: Strings.partnerPhone,
              hintText: Strings.signInPhoneHint,
              prefixIcon: Icon(Icons.phone_iphone_rounded),
            ),
          ),
          if (codeStep) ...[
            gap,
            TextField(
              controller: _code,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              decoration: InputDecoration(labelText: '${Strings.signInCodeSentTo} $_sentTo', prefixIcon: const Icon(Icons.sms_outlined)),
            ),
            gap,
            TextField(
              controller: _name,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: Strings.partnerContactName, prefixIcon: Icon(Icons.person_outline_rounded)),
            ),
            gap,
            TextField(
              controller: _shop,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: Strings.partnerShopName, prefixIcon: Icon(Icons.storefront_outlined)),
            ),
            gap,
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: Strings.partnerCategory),
              items: [
                for (final e in Strings.partnerCategories.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _category = v ?? _category),
            ),
            gap,
            TextField(
              controller: _commune,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: Strings.partnerCommune, prefixIcon: Icon(Icons.place_outlined)),
            ),
            gap,
            TextField(
              controller: _address,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: Strings.partnerAddress),
            ),
            gap,
            DropdownButtonFormField<String?>(
              value: _wallet,
              decoration: const InputDecoration(labelText: Strings.partnerWallet),
              items: [
                for (final e in Strings.partnerWallets.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                const DropdownMenuItem(value: null, child: Text(Strings.partnerWalletNone)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _wallet = v),
            ),
            gap,
            TextField(
              controller: _notes,
              enabled: !_busy,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: Strings.partnerNotes, alignLabelWithHint: true),
            ),
          ],
          ErrorLine(_error),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : (codeStep ? _submit : _requestCode),
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text(codeStep ? Strings.sendRequest : Strings.continueLabel),
          ),
        ],
      ),
    );
  }
}
