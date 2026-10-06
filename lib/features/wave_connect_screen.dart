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
/// **Points only, the default.** A webhook in the merchant's Wave portal tells
/// Hossouko about every payment to their ordinary Wave QR, and the payer earns
/// points. Hossouko keeps only the webhook's signing secret, which can verify
/// Wave's messages but cannot create or move a payment. Customers change
/// nothing.
///
/// **In-app payment, optional.** An API key with "Checkout API" access also
/// lets customers pay the shop from the Hossouko app. Kept folded away: most
/// merchants never need it, and it is the only secret here that can create a
/// payment.
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

  /// Runs one server change and shows its outcome.
  Future<void> _save(Future<WaveConnection> Function(WaveApi api) action, {String? done}) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final c = await action(ref.read(waveApiProvider));
      if (!mounted) return;
      _key.clear();
      _secret.clear();
      setState(() => _conn = c);
      if (done != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ClientErrorException && e.detail is String ? e.detail! as String : Strings.locationNeedsConnection);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _saveSecret() {
    final secret = _secret.text.trim();
    if (secret.length < 8) {
      setState(() => _error = Strings.waveSecretMissing);
      return;
    }
    _save((api) => api.connect(webhookSecret: secret), done: Strings.waveSaved);
  }

  void _saveKey() {
    final key = _key.text.trim();
    if (key.length < 16) {
      setState(() => _error = Strings.waveKeyMissing);
      return;
    }
    _save((api) => api.connect(apiKey: key), done: Strings.waveSaved);
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

  Widget _busyOr(String label) => _saving
      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
      : Text(label);

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
                if (c == null || !c.connected)
                  FilledButton(onPressed: _saving ? null : () => _save((api) => api.start()), child: _busyOr(Strings.waveStart))
                else ...[
                  _Status(connection: c),
                  const SizedBox(height: 16),
                  if (!c.webhookConfigured) ...[
                    const _Steps(Strings.waveSteps),
                    const SizedBox(height: 12),
                  ],
                  if (c.webhookUrl != null) _WebhookAddress(url: c.webhookUrl!),
                  const SizedBox(height: 16),
                  if (c.webhookConfigured) Text(Strings.waveReplaceSecret, style: text.labelMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _secret,
                    enabled: !_saving,
                    autocorrect: false,
                    enableSuggestions: false,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: Strings.waveSecretLabel, prefixIcon: Icon(Icons.lock_outline_rounded)),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _saving ? null : _saveSecret, child: _busyOr(Strings.waveSave)),
                  const SizedBox(height: 12),
                  const _Note(icon: Icons.shield_outlined, text: Strings.waveSafetyPoints),
                  const SizedBox(height: 20),
                  _InAppPayment(
                    connection: c,
                    keyController: _key,
                    saving: _saving,
                    onSave: _saveKey,
                  ),
                  const SizedBox(height: 12),
                  TextButton(onPressed: _saving ? null : _disconnect, child: const Text(Strings.waveDisconnect)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: const TextStyle(color: HossoukoColors.danger, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.connection});

  final WaveConnection connection;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final on = connection.webhookConfigured;
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(on ? Icons.check_circle_rounded : Icons.pending_outlined, color: on ? HossoukoColors.green : HossoukoColors.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(on ? Strings.wavePointsOn : Strings.wavePointsOff, style: text.titleSmall)),
        ]),
        if (connection.paymentsEnabled) ...[
          const SizedBox(height: 8),
          Text('${Strings.wavePayOn} ${connection.keyHint ?? ''}', style: text.bodySmall),
        ],
        if (connection.lastEventAt != null)
          Text('${Strings.waveLastEvent} ${connection.lastEventAt!.toString().substring(0, 16)}', style: text.bodySmall),
      ]),
    );
  }
}

/// The optional API key, folded away. Opened by default only when a key is
/// already connected, so the merchant can see and replace it.
class _InAppPayment extends StatelessWidget {
  const _InAppPayment({required this.connection, required this.keyController, required this.saving, required this.onSave});

  final WaveConnection connection;
  final TextEditingController keyController;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: connection.paymentsEnabled,
        leading: const Icon(Icons.phone_android_rounded),
        title: Text(Strings.wavePayTitle, style: text.titleSmall),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(Strings.wavePayIntro, style: text.bodyMedium),
          const SizedBox(height: 12),
          const _Steps(Strings.wavePaySteps),
          const SizedBox(height: 12),
          const _ScopeWarning(),
          const SizedBox(height: 12),
          TextField(
            controller: keyController,
            enabled: !saving,
            autocorrect: false,
            enableSuggestions: false,
            obscureText: true,
            decoration: const InputDecoration(labelText: Strings.waveKeyLabel, prefixIcon: Icon(Icons.key_rounded)),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: saving ? null : onSave, child: const Text(Strings.waveSave)),
          const SizedBox(height: 12),
          const _Note(icon: Icons.shield_outlined, text: Strings.wavePaySafety),
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
        borderRadius: BorderRadius.circular(HossoukoRadius.md),
        border: Border.all(color: HossoukoColors.danger),
      ),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber_rounded, color: HossoukoColors.danger),
        SizedBox(width: 10),
        Expanded(
          child: Text(Strings.waveScopeWarning,
              style: TextStyle(color: Color(0xFF8E1C1C), fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.35)),
        ),
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: HossoukoColors.muted),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}

class _Steps extends StatelessWidget {
  const _Steps(this.steps);

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, step) in steps.indexed)
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
