# Hossouko merchant app — architecture

Flutter app for the [Hossouko](../hossouko-BE) backend. One audience: the **merchant**.
It records sales on a cheap Android phone with unreliable connectivity, and
syncs when there is signal.

## Why one app

`../hossouko-BE/docs/business/CONCEPT.md` sets the boundary:

> Customers also need a simple way to earn benefits from repeat purchases
> **without installing a heavy application** [...] SMS, WhatsApp, QR codes,
> USSD-compatible workflows, and mobile money are more important than complex
> native-app features at the beginning.

So the customer never installs anything. They identify at the counter with a QR
code or a phone number, on the merchant's device. A customer-facing points
lookup, if it ships, belongs in the existing web site (`../hossouko-FE`) where it
weighs a few KB — not as a second Flutter binary that costs an order of
magnitude more over 2G.

A merchant/customer role switch in one binary was rejected too: it puts both
code paths on every device, grows the download for everyone, and mixes two
threat models in one process.

**The `lib/core/` layer must not import anything from `lib/features/` or
`lib/ui/`.** Transport, storage, auth and models stay UI-free, so if usage ever
justifies a customer app it is a new UI over the same core rather than a
rewrite.

## Why payment is a flow, not an app

`/api/payments` in the backend **initiates** a payment and returns a
`checkout_url`; the money moves inside Orange Money, Wave, or MTN MoMo. There is
no wallet model, no balance endpoint, and no user-to-user transfer in
`../hossouko-BE/backend-api/app/models.py`. The only working adapter today is
`SandboxPaymentProvider`, which returns `https://sandbox.invalid/` URLs; a live
provider name resolves to `ConfiguredProviderUnavailable` and raises.

That is deliberate. From the concept doc:

> Hossouko should facilitate access to financial services. It should not present
> itself as a bank, hold customer deposits, or lend directly unless the required
> regulatory status exists.

A standalone payment app implies moving or holding funds, which in the UEMOA
zone means BCEAO authorisation — a licensing programme, not a sprint. So payment
appears as a step inside the sale flow and inside tontine contributions.

The handoff is also the right security call: **the PIN is entered in the
operator's own app, never in ours.** We never handle a payment credential, and
we never need that scope on a handset we do not control.

## Stack, and what each dependency buys

| Package | Why it earns its size |
|---|---|
| `flutter_riverpod` | State and dependency injection without codegen. Compile-time safe, testable without a widget tree. |
| `sqflite` | The offline sale queue needs real durability. SQLite ships with Android, so no engine is bundled. Raw SQL, hand-written DAOs — Drift's codegen was not worth the APK weight here. |
| `flutter_secure_storage` | Access and refresh tokens in the Android Keystore. `SharedPreferences` is world-readable to anyone with adb or root. |
| `image_picker` | Shop photos and videos (*Photos et videos*). Hands over to Android's own picker and camera apps, so no camera or codec code is bundled. Photos are shrunk on the phone (1600 px, JPEG 80) before upload: a 4 MB shot goes up as ~300 KB. |
| `http_parser` | `MediaType` for the multipart upload. Already a dependency of `http`. |
| `path_provider` | Where unsent error reports wait between launches. Already compiled in through `flutter_secure_storage`, so declaring it costs nothing. |
| `http` | A handful of endpoints with explicit timeouts. Thinner than `dio`. |
| `path` | Joining the database path. Transitive anyway. |
| `geolocator` | One GPS fix of the shop, so customers get directions to it (the customer app's "Itinéraire"). Taken only after the merchant confirms "I am in my shop", in the foreground, never in the background. Costs about 0.3 MB per APK. `geolocator_android` is pinned to 4.6.1 in `dependency_overrides`: 4.6.2 does not build with Flutter 3.24. |

Every addition costs download size and attack surface on a 2014-era handset.
Justify it in this table before adding it.

`intl` was dropped after being added: the money formatter is ~40 lines by hand
(`lib/ui/money_text.dart`) and needs a non-breaking group separator plus XOF
symbol placement that `intl`'s locale data does not provide anyway. An unused
dependency in a table like this is exactly the rot the table exists to prevent.

## Verified on a real device

The offline loop was exercised on a Samsung Galaxy A51 (Android 13, arm64)
against the live backend over `adb reverse`, not only in tests:

1. Signed in; the backend logged `POST /api/token 200 OK`.
2. Recorded 2 500 XOF with connectivity. It synced on its own and landed in
   Postgres as row 3 with the device's key `sale-2RLaSMBI_OjH-75BjVFrmg`.
3. **Cut the tunnel** and recorded 700 XOF. The app still accepted it; the day's
   total read 3 200 F, the sale read "Pas encore envoyee", and the server
   correctly still held 3 rows.
4. Restored the tunnel and pressed "Envoyer maintenant". The queued sale reached
   the server as row 4 with its original key, and the list read "Envoyee".

Two bugs only a real handset surfaced, both fixed:

* **The back arrow rendered as the CJK glyph 咄.** `Icons.arrow_back` has no
  glyph once `uses-material-design: false` drops the icon font, so Android
  substituted from the system font. Anything icon-shaped must now be drawn —
  see `lib/ui/back_button.dart`.
* **The queue count was stale** right after recording a sale, showing "1 waiting
  to send" for a sale already on the server, because the background sync lands
  just after the home screen redraws.

## Bandwidth budget

The merchant pays for every byte out of a prepaid bundle, so:

- **Writes go in batches** through `POST /api/transactions/sync`, which accepts
  up to 50 operations, each with an `idempotency_key`. One round trip, not
  fifty. Idempotency keys are generated on the device so a retry after a dropped
  response cannot double-record a sale.
- **gzip is requested explicitly.** Note the backend has **no compression
  middleware** today, so the header changes nothing yet — it costs ~20 bytes and
  starts paying the day `GZipMiddleware` is added server-side, with no app update
  needed on every merchant's phone. Adding it is a backend task worth doing.
- The app **never polls** and never refreshes on its own; sync is triggered by
  recording a sale, by the merchant, or by a pull-to-refresh.
- **No images over the network**, with one exception the merchant asks for:
  the *Photos et videos* screen shows its own 320 px thumbnails (~15 KB
  each), only while open. Videos are never downloaded by this app. Uploads
  have their own 10-minute budget (`Env.uploadTimeout`), and a video over
  20 MB asks first and suggests Wi-Fi.
- **No analytics or third-party crash SDK.** Those upload silently on the
  merchant's bundle. Errors go to our own backend instead
  (`lib/core/monitoring/error_reporter.dart` → `POST /api/client-events`):
  deduplicated with a count, at most 30 queued, sent in one request at start-up
  or when the app returns to the foreground, never on a timer. A healthy app
  sends nothing. Messages are stripped of digit runs before they leave.
- **Usage for the pilot goes the same way, to our own backend**
  (`lib/core/monitoring/usage_tracker.dart` → `POST /api/usage-events`).
  A random install id (not a device id) counts installs; the shop is attached
  from the token because the pilot is measured per merchant. Events are
  aggregated per day on the device (40 sales are one entry with a count),
  sent at start-up or on return to the foreground, never on a timer, and the
  byte counter alone never triggers a request. What is sent: screen names,
  the sale form (opened, recorded in 5-second steps, abandoned and how far),
  the pilot's end-of-day sales estimate (`Env.pilotDailyReport`), and the
  bytes each API call cost (`ApiClient.onTraffic`). Never what was typed,
  never an amount or a phone number. Pushed screens need a
  `RouteSettings(name:)`: release builds are obfuscated, so class names are
  not readable labels.

## Security decisions

Recorded here because each one is a deliberate trade, not a default:

- **`minifyEnabled` + `shrinkResources`**, with `SourceFile` renamed but the
  line table kept, so crash reports stay mappable against `mapping.txt` without
  handing a reader the original file names.
- **A release build is never debug-signed.** Signing config comes from
  `android/key.properties` (gitignored); without it the release build is
  unsigned on purpose. A debug-signed APK is trivially replaced by an
  attacker's build on the same device.
- **`usesCleartextTraffic="false"`** plus a system-only trust anchor in
  `network_security_config.xml`. On a shared market cell, one downgraded request
  leaks a bearer token and a full sales history. Debug builds override this in
  `src/debug/` for loopback only, so it cannot reach a release APK.
- **No certificate pinning yet.** Pinning inside an APK that merchants update
  rarely is an outage waiting to happen. It belongs in the client on a rotation
  schedule once the production hostname and CA are fixed.
- **`allowBackup="false"`** and both `cloud-backup` and `device-transfer`
  excluded wholesale, so queued sales and tokens never leave the handset. Wholesale
  rather than filtered, so a file added later is not included by accident.
- **API base URL is a `--dart-define`**, not a runtime setting. `Env.assertHttpsInRelease()`
  kills a release build pointed at http at launch, rather than failing every
  request later.
- **Few permissions**: `INTERNET`, `ACCESS_NETWORK_STATE`, and foreground
  location (`ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`). Location is asked
  for only on the "Position du commerce" screen, after the merchant confirms
  they are standing in the shop, and is used for one fix; there is no
  background location permission. No contacts, storage, or phone state —
  every permission skipped is one less consent to explain to a merchant.

## Size discipline

- `uses-material-design: false` — the Material icon font alone is ~1.6 MB, for
  a handful of glyphs we can draw.
- `splits.abi` for `armeabi-v7a` and `arm64-v8a`, so a download is one ABI
  instead of both. A universal APK is also produced, because sideloading over
  WhatsApp is common where Play Store use is low.
- Current release sizes, with obfuscation and R8 on: **armeabi-v7a 12.98 MB**,
  arm64-v8a 15.8 MB, universal 28.0 MB. Dropping the x86 ABIs from the universal
  build removed ~12 MB of weight no merchant handset can use. Treat a v7a build
  above ~15 MB as a regression worth investigating.
- `resourceConfigurations = ["fr", "en"]` drops unused AndroidX translations.
- No custom font is bundled; the system font costs nothing.

## Layout

```
lib/
  core/            no Flutter UI imports, ever
    config/        build-time env, feature limits
    net/           http client, gzip, timeouts, error mapping
    auth/          phone + SMS code sign-in, token storage and renewal
    monitoring/    uncaught error capture and reporting
    data/          sqflite schema, DAOs, the sync queue
    model/         plain Dart types mirroring the API schemas
  features/        one directory per merchant task
  ui/              theme and shared widgets
```

## Verified backend behaviour

Checked against the running backend, not just read from the source:

* Replaying an `idempotency_key` returns `status: already_processed` with the
  **same** transaction id, and creates no second row. This is the guarantee the
  whole offline queue rests on.
* XOF amounts come back as `"1500"`, not `"1500.00"` — which is why `Money`
  treats XOF as zero-decimal.
* `user_id` is derived from the bearer token; the client omits it from the body.

## Backend facts that shape the client

Read from `../hossouko-BE/backend-api` as of this writing:

- **Sign-in is phone + SMS code** (`app/api/auth.py`). `POST /api/auth/otp/request`
  sends a 6-digit code; `/api/auth/otp/verify` with `app: "merchant"` returns a
  60-minute access token and a 90-day single-use refresh token, but only for a
  number an admin has given the merchant role and linked to a venue
  (`POST /api/admin/users/roles`). The token subject is `tel:+225…`.
  `/api/auth/refresh` rotates the pair; replaying a used refresh token revokes
  the session on every device that holds it, which is why renewals in the app
  are single-flight. A renewal that cannot reach the server throws a
  `NetworkException` instead of failing, so a merchant offline with queued
  sales is never signed out. The old `/api/token` demo login answers 404 in
  production.
- **Points on cash sales are earned by phone number.** A sale sent to
  `/api/merchant/sales/sync` may carry `customer_phone`; the server grants the
  venue's points and returns `points_awarded` per sale. The number is
  normalised on the device first (`lib/core/model/phone.dart`, mirroring
  `app/core/phone.py`) so a typo is caught while the customer is still at the
  counter. Balance and redemption go through
  `/api/merchant/customers/loyalty` and `/redeem`, as POSTs so the number never
  sits in a URL. They need a connection: the balance lives on the server.
- **`user_id` in a request body is ignored**; the server derives ownership from
  the token. The client must not rely on sending it.
- **Amounts are decimal strings** with 2 places, and the API rejects a currency
  that does not match the country (`/api/config/countries` is the source of
  truth for currency, phone prefixes, languages, and providers).
- Supported countries: CI (XOF), GH (GHS), NG (NGN), KE (KES).

## Build

```bash
# Local backend, Android emulator
flutter run --dart-define=HOSSOUKO_API_BASE=http://10.0.2.2:8000

# Release, per-ABI
flutter build apk --release --split-per-abi \
  --dart-define=HOSSOUKO_API_BASE=https://api.hossouko.ci
```
