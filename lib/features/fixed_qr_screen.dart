import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/net/api_exception.dart';
import '../core/payment_api.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// The shop's fixed QR, to print and stick on the counter. The customer scans
/// it and types the amount themselves; the per-sale QR (Encaisser) carries the
/// amount instead and suits a merchant who wants to set it.
class FixedQrScreen extends ConsumerStatefulWidget {
  const FixedQrScreen({super.key});

  @override
  ConsumerState<FixedQrScreen> createState() => _FixedQrScreenState();
}

class _FixedQrScreenState extends ConsumerState<FixedQrScreen> {
  ShopPayCode? _code;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final code = await ref.read(paymentApiProvider).fixedCode();
      if (mounted) setState(() => _code = code);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error =
            e is ClientErrorException && e.detail is String ? e.detail! as String : Strings.paymentNeedsConnection);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final code = _code;
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.fixedQr)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(Strings.fixedQrIntro, style: text.bodyMedium),
            const SizedBox(height: 20),
            if (_error != null)
              LoadError(onRetry: _load, message: _error!, retryLabel: Strings.retry)
            else if (code == null)
              const LoadingCards(count: 1, lineHeight: 280)
            else ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(DjassaRadius.lg)),
                  child: Column(
                    children: [
                      Text(code.name, style: serifStyle(26, color: Colors.black)),
                      const SizedBox(height: 10),
                      QrImageView(data: code.qrPayload, size: 260, backgroundColor: Colors.white),
                      const SizedBox(height: 8),
                      Text(code.code,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 4, color: Colors.black)),
                      const SizedBox(height: 4),
                      const Text('Djassa', style: TextStyle(fontSize: 13, color: Colors.black54)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(Strings.printHint, textAlign: TextAlign.center, style: text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
