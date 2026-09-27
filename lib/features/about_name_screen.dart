import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../ui/back_button.dart';

/// Explains the word "djassa", laid out like a dictionary entry.
///
/// Most merchants in Abidjan know the word; the screen is for everyone else who
/// holds the phone (a new hire, a relative, a pilot partner) and for the
/// merchant who wonders why an app carries a street name.
class AboutNameScreen extends StatelessWidget {
  const AboutNameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        // No Material icon font is bundled. See DjassaBackButton.
        leading: const DjassaBackButton(),
        title: const Text(Strings.aboutNameTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'djassa',
                    style: text.headlineMedium
                        ?.copyWith(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 4),
                  Text(Strings.aboutNameGrammar, style: text.bodySmall),
                  const SizedBox(height: 2),
                  Text(
                    Strings.aboutNameOrigin,
                    style: text.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const _Sense(number: 1, body: Strings.aboutNameSense1),
            const SizedBox(height: 16),
            const _Sense(number: 2, body: Strings.aboutNameSense2),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            Text(Strings.aboutNameWhy, style: text.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _Sense extends StatelessWidget {
  const _Sense({required this.number, required this.body});

  final int number;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Text('$number.', style: text.titleMedium),
        ),
        Expanded(child: Text(body, style: text.bodyMedium)),
      ],
    );
  }
}
