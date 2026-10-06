import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Presents the name Hossouko and its slogan, laid out like a dictionary entry.
///
/// For the merchant and anyone else who holds the phone (a new hire, a
/// relative, a pilot partner). Same layout as the customer app's about-name
/// screen, so the explanation reads identically wherever a reader meets it.
class AboutNameScreen extends StatelessWidget {
  const AboutNameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text(Strings.aboutNameTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: HossoukoColors.surface,
              borderRadius: BorderRadius.circular(HossoukoRadius.lg),
              border: const Border(left: BorderSide(color: HossoukoColors.orange, width: 4)),
              boxShadow: hossoukoShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('hossouko', style: text.displaySmall?.copyWith(fontStyle: FontStyle.italic, fontSize: 52)),
                const SizedBox(height: 6),
                Text(Strings.aboutNameGrammar, style: text.bodyMedium?.copyWith(color: HossoukoColors.muted)),
                const SizedBox(height: 4),
                Text(Strings.aboutNameOrigin.toUpperCase(), style: text.labelSmall?.copyWith(color: HossoukoColors.orangeDeep)),
              ],
            ),
          ),
          const SizedBox(height: 22),
          for (final (i, sense) in [Strings.aboutNameSense1, Strings.aboutNameSense2].indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: HossoukoColors.orangeTint, shape: BoxShape.circle),
                    child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, color: HossoukoColors.orangeDeep)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(sense, style: text.bodyLarge)),
                ],
              ),
            ),
          const SizedBox(height: 6),
          SoftCard(
            color: HossoukoColors.sand,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome_rounded, color: HossoukoColors.orangeDeep),
                const SizedBox(width: 12),
                Expanded(child: Text(Strings.aboutNameWhy, style: text.bodyMedium?.copyWith(fontStyle: FontStyle.italic))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
