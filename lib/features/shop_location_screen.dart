import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../core/location_api.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// The shop's position, so customers get directions ("Itineraire") to it.
///
/// The merchant is the only person reliably standing in the shop, so the
/// position comes from their phone. Nothing is read silently:
///   1. the app asks "Etes-vous dans votre commerce en ce moment ?";
///   2. only then does it ask Android for location permission, if needed;
///   3. it watches the GPS for up to [_maxWait], stopping early once the fix is
///      within [targetAccuracyM], and shows the precision as it improves;
///   4. it asks once more, with the precision, before saving.
/// One fix, in the foreground. No background location.
class ShopLocationScreen extends ConsumerStatefulWidget {
  const ShopLocationScreen({super.key});

  @override
  ConsumerState<ShopLocationScreen> createState() => _ShopLocationScreenState();
}

class _ShopLocationScreenState extends ConsumerState<ShopLocationScreen> {
  static const _maxWait = Duration(seconds: 30);

  ShopLocation? _saved;
  bool _loading = true;
  bool _locating = false;
  bool _saving = false;
  double? _liveAccuracy;
  String? _error;
  bool _offerSettings = false;
  StreamSubscription<Position>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final saved = await ref.read(locationApiProvider).mine();
      if (mounted) setState(() => _saved = saved);
    } on ApiException {
      if (mounted) setState(() => _error = Strings.locationNeedsConnection);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _start() async {
    final inShop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Strings.inShopQuestion),
        content: const Text(Strings.inShopQuestionHint),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(Strings.notNow)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(Strings.yesInShop)),
        ],
      ),
    );
    if (inShop != true || !mounted) return;

    setState(() {
      _error = null;
      _offerSettings = false;
    });

    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() {
        _error = Strings.locationServiceOff;
        _offerSettings = true;
      });
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() {
        _error = Strings.locationDenied;
        _offerSettings = permission == LocationPermission.deniedForever;
      });
      return;
    }

    final fix = await _bestFix();
    if (!mounted) return;
    if (fix == null || !isSavable(fix.accuracy)) {
      setState(() => _error = Strings.locationTooVague);
      return;
    }
    await _confirmAndSave(fix);
  }

  /// Watch the GPS and keep the most precise fix; stop at [targetAccuracyM]
  /// or after [_maxWait]. The first fix of a cold GPS is often hundreds of
  /// metres off, which is why this waits instead of taking the first one.
  Future<Position?> _bestFix() async {
    setState(() {
      _locating = true;
      _liveAccuracy = null;
    });
    Position? best;
    final done = Completer<void>();
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0),
    ).listen(
      (p) {
        if (best == null || p.accuracy < best!.accuracy) best = p;
        if (mounted) setState(() => _liveAccuracy = best!.accuracy);
        if (p.accuracy <= targetAccuracyM && !done.isCompleted) done.complete();
      },
      onError: (Object _) {
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future.timeout(_maxWait, onTimeout: () {});
    await _sub?.cancel();
    _sub = null;
    if (mounted) setState(() => _locating = false);
    return best;
  }

  Future<void> _confirmAndSave(Position fix) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Strings.useThisPosition),
        content: Text('${Strings.useThisPositionHint} : ${fix.accuracy.round()} ${Strings.meters}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(Strings.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(Strings.save)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(locationApiProvider)
          .save(latitude: fix.latitude, longitude: fix.longitude, accuracyM: fix.accuracy);
      if (!mounted) return;
      setState(() => _saved = saved);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(Strings.locationSaved)));
    } on ApiException catch (e) {
      if (!mounted) return;
      // The server's own words when it refused (French, plain); otherwise the
      // connection notice. Never blame the merchant for the network.
      setState(() => _error = e is ClientErrorException && e.detail is String
          ? e.detail! as String
          : Strings.locationNeedsConnection);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final saved = _saved;
    final busy = _locating || _saving;

    return Scaffold(
      appBar: AppBar(title: const Text(Strings.shopLocation)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(Strings.shopLocationIntro, style: text.bodyMedium),
            const SizedBox(height: 20),
            if (_loading)
              const LoadingCards(count: 1)
            else
              SoftCard(
                child: Row(
                  children: [
                    Icon(
                      saved?.isSet == true ? Icons.where_to_vote_rounded : Icons.location_off_outlined,
                      color: saved?.isSet == true ? DjassaColors.success : DjassaColors.muted,
                      size: 30,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(saved?.isSet == true ? Strings.shopLocationSet : Strings.shopLocationNotSet,
                              style: text.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            saved?.isSet == true
                                ? '${Strings.precision} : ${saved!.accuracyM ?? '?'} ${Strings.meters}'
                                    '${saved.setAt != null ? ' - ${Strings.shortDate(saved.setAt!)}' : ''}'
                                : Strings.shopLocationNotSetHint,
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            if (_locating) ...[
              Row(
                children: [
                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _liveAccuracy == null
                          ? Strings.locating
                          : '${Strings.precision} : ${_liveAccuracy!.round()} ${Strings.meters}',
                      style: text.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(Strings.locatingHint, style: text.bodySmall),
              const SizedBox(height: 20),
            ],
            FilledButton.icon(
              onPressed: busy || _loading ? null : _start,
              icon: const Icon(Icons.my_location_rounded),
              label: Text(saved?.isSet == true ? Strings.updateHere : Strings.recordHere),
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
              if (_offerSettings)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => _error == Strings.locationServiceOff
                        ? Geolocator.openLocationSettings()
                        : Geolocator.openAppSettings(),
                    child: const Text(Strings.openSettings),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
