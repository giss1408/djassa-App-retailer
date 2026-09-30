# Djassa — merchant app

Flutter app for merchants: record a sale on a cheap Android phone, even with no
signal, and sync when there is one. Talks to the FastAPI backend in
[`../djassa-BE`](../djassa-BE).

Two constraints shape every decision, and they are not negotiable:

1. **Low bandwidth.** The merchant pays per byte from a prepaid bundle.
2. **Old phones.** Android 5.0 and ~1 GB RAM are target devices, not edge cases.

Read [ARCHITECTURE.md](ARCHITECTURE.md) before adding a dependency, a screen, or
a network call. It records why each trade was made.

## Run against a local backend

Start the backend first:

```bash
cd ../djassa-BE/backend-api
docker compose -f docker-compose.dev.yml up -d db redis
export DJASSA_SECRET_KEY=dev-only-not-a-real-secret
export DATABASE_URL=postgresql+asyncpg://djassa:djassa@127.0.0.1:5432/djassa
alembic -c alembic.ini upgrade head
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Then the app. `10.0.2.2` is the host machine as seen from the Android emulator;
use your LAN IP for a physical device:

```bash
flutter run --dart-define=DJASSA_API_BASE=http://10.0.2.2:8000
```

The backend's CORS default allows `http://localhost:3000` only, which does not
affect a native app — but do set `CORS_ORIGINS` if you also run the web site.

## Test distribution

Testers install from one link shared on WhatsApp: the site's `/app` page.
Signed APKs are published as GitHub Releases by
[`.github/workflows/release.yml`](.github/workflows/release.yml) when a version
tag is pushed (`scripts/create-signing-key.sh` once, then
`git tag v0.1.0 && git push origin v0.1.0`). Full procedure, including the free
backend on Render + Neon and Firebase App Distribution:
[`../djassa-BE/docs/technical/DEPLOY-TEST.md`](../djassa-BE/docs/technical/DEPLOY-TEST.md).

## Build for distribution

```bash
scripts/build-release.sh https://<your-api>.onrender.com
```

This produces one APK per ARM ABI (13.0 MB for armeabi-v7a, 15.8 MB for arm64)
plus a 28.0 MB universal APK for sideloading, with Dart obfuscation on. Signing needs
`android/key.properties` — see `android/key.properties.example`. **Without it the
APKs are unsigned on purpose**; the build never falls back to the debug key.

`build/symbols/` holds the obfuscation map. Archive it with the release or a
crash report from the field is unreadable. Never ship it.

## Commands

```bash
flutter analyze      # must be clean before a commit
flutter test
flutter pub get
```

## Run on a USB-connected phone

```bash
scripts/run-device.sh 8001
```

`adb reverse` tunnels the phone's `localhost:8001` back to this machine over the
cable, so no shared Wi-Fi is needed and the traffic never leaves the USB link.
(`10.0.2.2` is emulator-only and does **not** work on a physical device.)

## Current state

Working end to end, verified on a Galaxy A51 against the live backend:

- Sign-in against `/api/token`, token held in the Android Keystore.
- Record a sale offline; it is durable on disk before anything touches the
  network.
- Batched sync through `/api/transactions/sync` with device-generated
  idempotency keys, exponential backoff and jitter.
- The day's total and a sales list that says, per sale, whether it has left the
  phone.

28 tests pass, including the case that matters most: a response dropped *after*
the server commits does not create a second sale.

Customer points (integration branch): a cash sale can carry the customer's
phone number, checked on the phone, and the customer earns the venue's points
once it syncs; the sale list shows "+N pts". The **Points client** screen looks
up a customer's balance by number and hands over a reward with a voucher code.

Not yet implemented: outlet registration (accounts are created by hand),
tontines, payment initiation, and Dioula translation.

## Known backend gaps that affect this app

- Authentication is a hardcoded demo user (`demo` / `demo123`). No registration,
  no OTP, no refresh token.
- Points earned by phone at the counter are not yet visible in the customer
  app: a customer account cannot prove it owns a number until there is an OTP
  login, so the two are deliberately not merged.

See the last section of [ARCHITECTURE.md](ARCHITECTURE.md) for the full list.
