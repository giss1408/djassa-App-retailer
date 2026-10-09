import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'about_name_screen.dart';
import 'demo/demo_mode.dart';
import 'partner_request_screen.dart';
import 'phone_sign_in_form.dart';

/// Sign-in with the phone number registered for the shop and an SMS code.
/// A number becomes a merchant account when an admin links it to a venue
/// (`POST /api/admin/users/roles`); any other number is told to contact us.
class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Same treatment as the customer app's sign-in header, so the two
          // apps' first screen reads as one product before a merchant ever
          // sees the rest of either.
          PatternedSurface(
            gradient: FideliaColors.headerGradient,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
            padding: EdgeInsets.fromLTRB(28, top + 44, 28, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FideliaMark(size: 58),
                const SizedBox(height: 22),
                Text(Strings.signInTitle, style: serifStyle(42, color: Colors.white)),
                const SizedBox(height: 8),
                Text(Strings.signInSubtitle, style: TextStyle(color: Colors.white.withOpacity(0.88), fontSize: 15.5)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PhoneSignInForm(),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: 'partner_request'), builder: (_) => const PartnerRequestScreen())),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text(Strings.becomePartner, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 8),
                // Everything a merchant can do, on a pretend shop, before any
                // account. Their real sales and shop stay behind sign-in.
                if (DemoHost.maybeOf(context) case final host?)
                  TextButton.icon(
                    onPressed: host.start,
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: const Text(Strings.tryDemo),
                  ),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(settings: const RouteSettings(name: 'about_name'), builder: (_) => const AboutNameScreen()),
                    ),
                    child: const Text(Strings.aboutNameLink),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
