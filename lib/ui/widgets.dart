import 'package:flutter/material.dart';

import 'theme.dart';

/// Shared presentational pieces, mirroring djassa-App-user/lib/ui/widgets.dart
/// so both apps read as one product. Only what the merchant screens actually
/// use is here — the customer app's venue cards, wallet swatches and deal
/// carousels have no counterpart in this app and are not copied in.

/// Brand header: deep-orange gradient with the wax-print texture and a
/// rounded bottom edge, the way the site's hero and the customer app frame a
/// page. [child] sits inside the gradient under the title.
class GradientHeader extends StatelessWidget {
  const GradientHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.child,
    this.gradient = DjassaColors.headerGradient,
    this.bottomPadding = 22,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final Widget? child;
  final Gradient gradient;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return PatternedSurface(
      gradient: gradient,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(DjassaRadius.xl)),
      padding: EdgeInsets.fromLTRB(20, top + 18, 20, bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subtitle != null) ...[
                      Text(subtitle!.toUpperCase(),
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.78), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                      const SizedBox(height: 4),
                    ],
                    Text(title, style: serifStyle(32, color: Colors.white)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (child != null) ...[const SizedBox(height: 18), child!],
        ],
      ),
    );
  }
}

/// A gradient surface carrying the Djassa wax-print texture. The pattern is
/// static and painted once behind a [RepaintBoundary], so it costs nothing
/// while scrolling — a real cost on the low-end GPUs this app targets, not
/// just the customer app's.
class PatternedSurface extends StatelessWidget {
  const PatternedSurface({
    super.key,
    required this.gradient,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.padding = EdgeInsets.zero,
    this.patternOpacity = 0.09,
    this.boxShadow,
  });

  final Gradient gradient;
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsets padding;
  final double patternOpacity;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: gradient, borderRadius: borderRadius, boxShadow: boxShadow),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(child: CustomPaint(painter: WaxPatternPainter(opacity: patternOpacity))),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// Djassa's texture: rows of concentric rings and diamonds, the geometry of
/// the wax prints sold in every djassa. Thin white strokes at low opacity so
/// it reads as fabric, not decoration, and never fights the text on top.
/// Copied from djassa-App-user rather than re-derived, so the pattern is
/// pixel-identical across both apps.
class WaxPatternPainter extends CustomPainter {
  const WaxPatternPainter({this.opacity = 0.09, this.color = Colors.white, this.cell = 44});

  final double opacity;
  final Color color;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final dot = Paint()..color = color.withOpacity(opacity * 1.4);
    final cols = (size.width / cell).ceil() + 1;
    final rows = (size.height / cell).ceil() + 1;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final center = Offset(col * cell, row * cell);
        canvas.drawCircle(center, cell * 0.32, paint);
        canvas.drawCircle(center, 2.2, dot);
      }
    }
  }

  @override
  bool shouldRepaint(WaxPatternPainter oldDelegate) =>
      oldDelegate.opacity != opacity || oldDelegate.color != color || oldDelegate.cell != cell;
}

/// Round, low-opacity icon button for sitting on a gradient header (a back
/// arrow, a settings glyph).
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({super.key, required this.icon, required this.onPressed, required this.tooltip});

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.16),
      shape: const CircleBorder(),
      child: IconButton(onPressed: onPressed, tooltip: tooltip, icon: Icon(icon, color: Colors.white)),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
          if (actionLabel != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(99),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(actionLabel!, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: DjassaColors.orangeDeep)),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: DjassaColors.orangeDeep),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// White rounded surface with the hairline border used across the app.
class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16), this.color});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? DjassaColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DjassaRadius.lg),
        side: const BorderSide(color: DjassaColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Small rounded label. Meaning is carried by the words, never colour alone —
/// the rule the sale list already followed before this app had any styling.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.icon, this.color = DjassaColors.inkSoft, this.background = DjassaColors.sand});

  final String label;
  final IconData? icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          // Flexible rather than a bare Text: "min" only sizes this row to its
          // *preferred* width, so a long label (the merchant app's "Mis en
          // avant par Djassa" is more than twice the customer app's
          // "Sponsorisé") still overflows if the card offering it is narrow.
          // This lets it ellipsize instead of pushing past the pill's edge.
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

const skeletonColor = Color(0xFFECE6D9);

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: DjassaColors.sand, shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: DjassaColors.orangeDeep),
          ),
          const SizedBox(height: 16),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, style: text.bodySmall, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// A load failure, in words first, with a retry big enough for a thumb.
///
/// Takes its strings from the caller rather than a default: every other piece
/// of copy in this app lives in `Strings`, and a fallback string here would
/// be the one exception a translation pass could miss.
class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.onRetry, required this.message, required this.retryLabel});

  final VoidCallback onRetry;
  final String message;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.wifi_off_rounded,
      title: message,
      action: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(160, 48)),
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(retryLabel),
      ),
    );
  }
}

/// Placeholder cards while a list loads: the layout does not jump when the
/// data arrives, which reads as faster than a lone spinner — and replaces the
/// bare "..." this app showed before.
class LoadingCards extends StatelessWidget {
  const LoadingCards({super.key, this.count = 3, this.lineHeight = 64});

  final int count;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: skeletonColor, borderRadius: BorderRadius.circular(6)),
        );
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SoftCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [bar(120, 14), const SizedBox(height: 10), bar(180, 11)],
                    ),
                  ),
                  bar(70, 20),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
