import 'package:flutter/material.dart';

/// A back chevron drawn with a path instead of a font glyph.
///
/// The app ships without the Material icon font (`uses-material-design: false`
/// saves ~1.6MB), so `Icons.arrow_back` has no glyph to render and Android
/// substitutes whatever the system font offers at that code point — on a
/// Samsung device that surfaced as the CJK character 咄. Found on a real
/// handset, not in the analyzer.
///
/// Anything that needs an icon must therefore be drawn, as here, or replaced
/// with a text label.
class DjassaBackButton extends StatelessWidget {
  const DjassaBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      // The screen reader needs a name; there is no glyph to infer one from.
      label: MaterialLocalizations.of(context).backButtonTooltip,
      child: InkResponse(
        onTap: () => Navigator.of(context).maybePop(),
        radius: 24,
        // 48dp square: the Android accessibility minimum, and what a thumb
        // needs while the merchant is holding goods.
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: CustomPaint(
              size: const Size(12, 20),
              painter: _ChevronPainter(color),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      // 2.2 rather than a hairline: a thin stroke disappears on a cheap panel
      // in direct sunlight.
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(0, size.height / 2)
      ..lineTo(size.width, size.height);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => oldDelegate.color != color;
}
