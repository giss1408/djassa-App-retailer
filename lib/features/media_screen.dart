import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/media_api.dart';
import '../core/net/api_exception.dart';
import '../core/providers.dart';
import '../l10n/strings.dart';
import '../ui/theme.dart';

/// The shop's photos and videos, as customers will see them.
///
/// Photos are shrunk on the phone before they leave it (1600 px, JPEG 80):
/// a 4 MB camera shot goes up as ~300 KB. Videos cannot be shrunk here
/// without bundling a codec, so a heavy one asks first and suggests Wi-Fi;
/// the server re-encodes it to ~4.5 MB a minute for customers.
///
/// This screen loads only the 320 px thumbnails, and only when opened: the
/// app's no-images rule still holds everywhere else.
class MediaScreen extends ConsumerStatefulWidget {
  const MediaScreen({super.key});

  @override
  ConsumerState<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends ConsumerState<MediaScreen> {
  final _picker = ImagePicker();
  List<ShopMedia> _media = const [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  static const _heavyBytes = 20 * 1024 * 1024;

  int get _images => _media.where((m) => !m.isVideo && m.status != 'failed').length;
  int get _videos => _media.where((m) => m.isVideo && m.status != 'failed').length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final media = await ref.read(mediaApiProvider).mine();
      if (mounted) setState(() => _media = media);
    } on ApiException {
      if (mounted) setState(() => _error = Strings.locationNeedsConnection);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(ApiException e) =>
      e is ClientErrorException && e.detail is String ? e.detail! as String : Strings.locationNeedsConnection;

  Future<void> _pick({required bool video, ImageSource source = ImageSource.gallery}) async {
    final full = video ? _videos >= MediaApi.maxVideos : _images >= MediaApi.maxImages;
    if (full) {
      setState(() => _error = Strings.mediaLimitReached);
      return;
    }
    final file = video
        ? await _picker.pickVideo(source: source, maxDuration: const Duration(seconds: 60))
        : await _picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
    if (file == null || !mounted) return;

    final bytes = await File(file.path).length();
    if (video && bytes > _heavyBytes && !await _confirmHeavy(bytes)) return;

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      await ref.read(mediaApiProvider).upload(file.path);
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<bool> _confirmHeavy(int bytes) async {
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(0);
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Strings.mediaHeavyTitle),
        content: Text('${Strings.mediaHeavyHint} $mb Mo. ${Strings.mediaHeavyAdvice}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(Strings.notNow)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(Strings.mediaSendAnyway)),
        ],
      ),
    );
    return go == true;
  }

  Future<void> _delete(ShopMedia media) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Strings.mediaDeleteQuestion),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(Strings.notNow)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(Strings.mediaDelete)),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await ref.read(mediaApiProvider).delete(media.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  Future<void> _putFirst(ShopMedia media) async {
    try {
      final media0 = await ref.read(mediaApiProvider).putFirst(media.id, _media);
      if (mounted) setState(() => _media = media0);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final busy = _uploading || _loading;
    return Scaffold(
      appBar: AppBar(title: const Text(Strings.mediaTitle)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(Strings.mediaIntro, style: text.bodyMedium),
            const SizedBox(height: 8),
            Text('$_images/${MediaApi.maxImages} ${Strings.mediaPhotos} · $_videos/${MediaApi.maxVideos} ${Strings.mediaVideos}',
                style: text.labelMedium),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: busy ? null : () => _pick(video: false),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text(Strings.mediaAddPhoto),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _pick(video: false, source: ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text(Strings.mediaTakePhoto),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _pick(video: true),
                icon: const Icon(Icons.videocam_outlined),
                label: const Text(Strings.mediaAddVideo),
              ),
            ]),
            if (_uploading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Text(Strings.mediaUploading, style: text.bodySmall),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: FideliaColors.danger, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_media.isEmpty)
              Text(Strings.mediaEmpty, style: text.bodyMedium)
            else
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final (i, m) in _media.indexed)
                    _Tile(
                      media: m,
                      first: i == 0,
                      onDelete: () => _delete(m),
                      onPutFirst: () => _putFirst(m),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.media, required this.first, required this.onDelete, required this.onPutFirst});

  final ShopMedia media;
  final bool first;
  final VoidCallback onDelete;
  final VoidCallback onPutFirst;

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (media.status) {
      'ready' when media.thumbUrl != null => Image.network(
          media.thumbUrl!,
          fit: BoxFit.cover,
          cacheWidth: 320,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
        ),
      'failed' => Padding(
          padding: const EdgeInsets.all(6),
          child: Text('${Strings.mediaFailed} : ${media.error ?? ''}',
              style: const TextStyle(color: FideliaColors.danger, fontSize: 11), maxLines: 4, overflow: TextOverflow.ellipsis),
        ),
      _ => const Padding(
          padding: EdgeInsets.all(6),
          child: Text(Strings.mediaProcessing, style: TextStyle(fontSize: 11), maxLines: 4),
        ),
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(FideliaRadius.md),
      child: Stack(fit: StackFit.expand, children: [
        ColoredBox(color: const Color(0xFFF1ECE4), child: Center(child: body)),
        if (media.isVideo && media.status == 'ready')
          const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 36)),
        Positioned(
          top: 0,
          right: 0,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white, shadows: [Shadow(blurRadius: 4)]),
            onSelected: (v) => v == 'first' ? onPutFirst() : onDelete(),
            itemBuilder: (_) => [
              if (!first && media.status == 'ready') const PopupMenuItem(value: 'first', child: Text(Strings.mediaPutFirst)),
              const PopupMenuItem(value: 'delete', child: Text(Strings.mediaDelete)),
            ],
          ),
        ),
      ]),
    );
  }
}
