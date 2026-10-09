import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/config/env.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import 'account_screen.dart';

/// Phone number, then the 6-digit code sent by SMS.
///
/// Two steps in one widget so "change number" and "resend" never lose what
/// was typed. Nothing is remembered between launches: the number is the
/// account, and a shared phone should not offer the last person's.
class PhoneSignInForm extends ConsumerStatefulWidget {
  const PhoneSignInForm({super.key});

  @override
  ConsumerState<PhoneSignInForm> createState() => _PhoneSignInFormState();
}

class _PhoneSignInFormState extends ConsumerState<PhoneSignInForm> {
  // Prefilled only in debug builds given FIDELIA_DEV_PHONE. See Env.
  final _phone = TextEditingController(text: Env.devPhone);
  final _code = TextEditingController();
  bool _codeStep = false;
  bool _busy = false;
  String? _error;
  String? _sentTo;
  int _resendLeft = 0;
  Timer? _countdown;

  @override
  void dispose() {
    _countdown?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(authRepositoryProvider).requestCode(_phone.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case CodeSent(:final phoneMasked, :final resendIn, :final devCode):
          _codeStep = true;
          _sentTo = phoneMasked;
          _code.text = (devCode != null && !Env.isRelease) ? devCode : '';
          _startCountdown(resendIn.inSeconds);
        case CodeRequestRefused(:final message) || CodeRequestUnavailable(:final message):
          _error = message;
      }
    });
  }

  void _startCountdown(int seconds) {
    _countdown?.cancel();
    _resendLeft = seconds;
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendLeft <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendLeft = 0);
        return;
      }
      setState(() => _resendLeft--);
    });
  }

  Future<void> _verify() async {
    if (_busy || _code.text.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(sessionProvider.notifier).verifyCode(phone: _phone.text.trim(), code: _code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = switch (result) {
        // The session gate swaps this screen out.
        SignInSuccess() => null,
        SignInRejected(:final message) || SignInUnavailable(:final message) => message,
      };
    });
  }

  void _changeNumber() {
    _countdown?.cancel();
    setState(() {
      _codeStep = false;
      _error = null;
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_codeStep)
          TextField(
            controller: _phone,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            autocorrect: false,
            // Never suggest a number: a market phone is often shared.
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(20)],
            onSubmitted: (_) => _requestCode(),
            decoration: const InputDecoration(
              labelText: Strings.signInPhoneLabel,
              hintText: Strings.signInPhoneHint,
              helperText: Strings.signInPhoneHelper,
              prefixIcon: Icon(Icons.phone_iphone_rounded),
            ),
          )
        else ...[
          Text('${Strings.signInCodeSentTo} $_sentTo', style: text.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            // Six digits is the whole answer; no extra tap needed.
            onChanged: (value) {
              if (value.length == 6) _verify();
            },
            onSubmitted: (_) => _verify(),
            style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(labelText: Strings.signInCodeLabel, prefixIcon: Icon(Icons.sms_outlined)),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.error_outline_rounded, size: 18, color: colors.error),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!, style: text.bodyMedium?.copyWith(color: colors.error))),
          ]),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : (_codeStep ? _verify : _requestCode),
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Text(_codeStep ? Strings.signIn : Strings.signInSendCode),
        ),
        if (!_codeStep) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: 'lost_number'), builder: (_) => const LostNumberScreen())),
            child: const Text(Strings.lostNumber),
          ),
        ],
        if (_codeStep) ...[
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton(onPressed: _busy ? null : _changeNumber, child: const Text(Strings.signInChangeNumber)),
            TextButton(
              onPressed: (_busy || _resendLeft > 0) ? null : _requestCode,
              child: Text(_resendLeft > 0 ? '${Strings.signInResendCode} (${_resendLeft}s)' : Strings.signInResendCode),
            ),
          ]),
        ],
      ],
    );
  }
}
