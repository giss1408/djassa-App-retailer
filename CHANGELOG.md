# Changelog — Fidelia Pro (merchant app)

What each version of the merchant app does, newest first. Versions are git
tags (`vX.Y.Z`); each one builds signed APKs (GitHub Releases) and, from
v0.2.0, the bundle for Google Play. The app was called **Djassa Pro** up to
v0.1.12, briefly **Hossouko Pro**, and is **Fidelia Pro** from v0.2.0.

## v0.2.0 — 2026-10-09

First version prepared for Google Play.

- **New name and look: Fidelia Pro**, slogan "La fidélité, ça compte". New
  launcher icon and start-up screen (the green "F" with its orange point and
  "pro"), and the same mark on the sign-in screen.
- **New app ID `com.regisse.fidelia.pro`** (was `ci.djassa…`): it installs as
  a new app; sync the old one before switching.
- **Customer consent at the counter**: a sale earns points for a phone number
  only once the merchant has ticked that the customer agrees (ARTCI). Without
  it the sale is recorded but earns nothing.
- **Payer en plusieurs fois (layaway)**, for shops where the team switched it
  on: open a plan for one named good after reading the terms to the customer,
  record each payment, hand the good over when it is paid (it then counts as
  one sale), or cancel and record the refund.
- **Deal banners**: choose the corner banner of a deal (bon plan, flash, promo).
- **Aide**: the menu opens a WhatsApp conversation with the Fidelia team.
- **Demo mode**: try the app without an account, on sample data that is never
  sent anywhere.
- **Partner request**: Restaurant is its own category, apart from Maquis.
- **Delete my account** (Compte → Supprimer mon compte): sends a request to
  the team, who settle the shop and delete the account within 30 days.
- Targets **Android 16** (API 36), as Google Play requires.

## v0.1.12 — 2026-10-04

- **Sign in with your phone number** and a code received by SMS, instead of a
  username and password; shared test numbers for the pilot.
- **Account**: see your number, move the account to a new number, sign out
  other phones, and recover an account after losing the number.
- **Ask to join** from the sign-in screen (partner request): the team calls,
  checks the shop and the wallet, then approves.
- **Team**: the owner adds cashiers, who sign in with their own number and
  only record sales.
- **Photos and videos** of the shop, shown on its page in the customer app.
- **Error reports and pilot usage figures** sent to Fidelia's own server (no
  phone number, no third-party analytics).
- Icon with "pro" under the mark, without a background.

## v0.1.11 — 2026-09-30

- Connecting Wave: a red warning to tick only the *Checkout* permission on the
  Wave key.

## v0.1.10 — 2026-09-30

- **Connect your Wave Business account**: Wave payments from customers go
  straight to the merchant's own wallet.

## v0.1.9 — 2026-09-30

- Named **Djassa Pro**, on a green icon.

## v0.1.8 — 2026-09-30

- The brand mark replaces the Flutter logo on the launcher and the start-up
  screen.

## v0.1.7 — 2026-09-30

- **Encaisser**: show a QR code for an amount; the customer scans it and pays
  from their mobile wallet. A fixed QR for the counter, too.
- Download about half as large.

## v0.1.6 — 2026-09-30

- **Shop position**: record where the shop is from the phone's GPS (asked
  first), so customers find it on the map.

## v0.1.1 to v0.1.5 — 2026-09-30

Build and release only, no change in the app: the server address must be set
at build time, and the signing key is generated and checked automatically.

## v0.1.0 — 2026-09-30

First test version, installed from a link shared on WhatsApp.

- **Record a sale in seconds**, even with no network: it is kept on the phone
  and sent when the connection returns, never twice.
- **Today's total** and the latest sales on the home screen.
- **Points for cash customers**: enter the customer's number with a sale, and
  they earn the shop's points without the customer app.
- **Points client**: look up a customer's points at the counter and hand over
  a reward.
- **Bons plans**: publish deals that appear in the customer app.
- What the name means, from the sign-in screen.
