import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../core/wave_api.dart';
import '../l10n/strings.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Connect the merchant's OWN Wave Business account (pilot option B).
///
/// Customers who pay with Wave in Djassa then pay through a Wave checkout
/// created with this key: the money lands in the merchant's Wave wallet,
/// never with Djassa. The key can create payments, not withdraw; the merchant
/// can revoke it in the Wave portal at any time.
///
/// Two things come from business.wave.com → Developer: an API key with
/// "Checkout API" access, and the signing secret of a webhook pointed at the
/// address this screen shows. Both are sent once, then kept sealed on the
/// server; this screen never shows them again.
class WaveConnectScreen extends ConsumerStatefulWidget {
  const WaveConnectScreen({super.key});

  @override
  ConsumerState<WaveConnectScreen> createState() => _WaveConnectScreenState();
}

class _WaveConnectScreenState extends ConsumerState<WaveConnectScreen> {
  final _key = TextEditingController();
  final _secret = TextEditingController();
  WaveConnection? _conn;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _key.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final c = await ref.read(waveApiProvider).mine();
      if (mounted) setState(() => _conn = c);
    } on ApiException {
      if (mounted) setState(() => _error = Strings.locationNeedsConnection);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    final key = _key.text.trim();
    if (key.length < 16) {
      setState(() => _error = Strings.waveKeyMissing);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final c = await ref.read(waveApiProvider).connect(apiKey: key, webhookSecret: _secret.text.trim());
      if (!mounted) return;
      _key.clear();
      _secret.clear();
      setState(() => _conn = c);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(Strings.waveConnected)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ClientErrorException && e.detail is String ? e.detail! as String : Strings.locationNeedsConnection);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _disconnect() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Strings.waveDisconnectQuestion),
        content: const Text(Strings.waveDisconnectHint),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(Strings.notNow)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(Strings.waveDisconnect)),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(waveApiProvider).disconnect();
      if (mounted) setState(() => _conn = const WaveConnection(connected: false));
    } on ApiException {
      if (mounted) setState(() => _error = Strings.locationNeedsConnection);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = _conn;
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.waveTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(Strings.waveIntro, style: text.bodyMedium),
                const SizedBox(height: 16),
                if (c != null && c.connected) ...[
                  SoftCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.check_circle_rounded, color: DjassaColors.green),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${Strings.waveConnectedKey} ${c.keyHint ?? ''}', style: text.titleSmall)),
                      ]),
                      const SizedBox(height: 8),
                      Text(c.webhookConfigured ? Strings.waveWebhookOk : Strings.waveWebhookMissing, style: text.bodySmall),
                      if (c.lastEventAt != null)
                        Text('${Strings.waveLastEvent} ${c.lastEventAt!.toString().substring(0, 16)}', style: text.bodySmall),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  if (c.webhookUrl != null) _WebhookAddress(url: c.webhookUrl!),
                  const SizedBox(height: 20),
                  Text(Strings.waveReplace, style: text.labelMedium),
                  const SizedBox(height: 8),
                ] else ...[
                  const _Steps(),
                  const SizedBox(height: 16),
                ],
                const _ScopeWarning(),
                const SizedBox(height: 16),
                TextField(
                  controller: _key,
                  enabled: !_saving,
                  autocorrect: false,
                  enableSuggestions: false,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: Strings.waveKeyLabel, prefixIcon: Icon(Icons.key_rounded)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _secret,
                  enabled: !_saving,
                  autocorrect: false,
                  enableSuggestions: false,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: Strings.waveSecretLabel,
                    helperText: Strings.waveSecretHelp,
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _saving ? null : _connect,
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : Text(c != null && c.connected ? Strings.waveUpdate : Strings.waveConnect),
                ),
                if (c != null && c.connected) ...[
                  const SizedBox(height: 8),
                  TextButton(onPressed: _saving ? null : _disconnect, child: const Text(Strings.waveDisconnect)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: const TextStyle(color: DjassaColors.danger, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 20),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.shield_outlined, size: 18, color: DjassaColors.muted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(Strings.waveSafety, style: text.bodySmall)),
                ]),
              ],
            ),
    );
  }
}

/// The one rule that keeps a leaked key harmless: Checkout only, never Payout.
class _ScopeWarning extends StatelessWidget {
  const _ScopeWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDE4E4),
        borderRadius: BorderRadius.circular(DjassaRadius.md),
        border: Border.all(color: DjassaColors.danger),
      ),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber_rounded, color: DjassaColors.danger),
        SizedBox(width: 10),
        Expanded(
          child: Text(Strings.waveScopeWarning,
              style: TextStyle(color: Color(0xFF8E1C1C), fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.35)),
        ),
      ]),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, step) in Strings.waveSteps.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 22, child: Text('${i + 1}.', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w800))),
              Expanded(child: Text(step, style: text.bodyMedium)),
            ]),
          ),
      ]),
    );
  }
}

class _WebhookAddress extends StatelessWidget {
  const _WebhookAddress({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(Strings.waveWebhookAddress, style: text.labelMedium),
        const SizedBox(height: 6),
        SelectableText(url, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        const SizedBox(height: 4),
        Text(Strings.waveWebhookEvents, style: text.bodySmall),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(Strings.copied)));
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text(Strings.copy),
          ),
        ),
      ]),
    );
  }
}
