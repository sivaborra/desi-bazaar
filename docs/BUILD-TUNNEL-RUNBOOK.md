# Desi Bazaar — Build & Tunnel Runbook (v12, 2026-10-12)

## Quick reference

| Item | Value |
|------|-------|
| Package source | `/mnt/d/phone/Desi-Bazaar-Complete-Package/` |
| Backend | `implementation-review/vertical-slice/app.py` (FastAPI, port 8100) |
| Mobile | `mobile/` (Flutter) |
| Current version | v1.12.0 (build 12) |

## Backend bring-up

```bash
cd /mnt/d/phone/Desi-Bazaar-Complete-Package/implementation-review/vertical-slice
# First time only:
python3 -m venv .venv && .venv/bin/pip install fastapi uvicorn pytest

# SMTP config (for real email OTP) — set before starting:
export SMTP_HOST="smtp.bizmail.yahoo.com"
export SMTP_PORT="465"
export SMTP_USER="assistant@balticitsystems.com"
export SMTP_PASS="<app-specific-password>"  # Generate at login.yahoo.com/account/security

# Start:
.venv/bin/uvicorn app:app --host 0.0.0.0 --port 8100
# Logs: tail -f /mnt/d/phone/Desi-Bazaar-Complete-Package/bring-up-logs/backend.log
```

Or use the script: `./desi-bazaar-bring-up.sh` (starts backend + named tunnel)

## Cloudflare tunnel

### Quick tunnel (WORKING — use this for testing)

```bash
cd /mnt/d/phone/Desi-Bazaar-Complete-Package
./cloudflared tunnel --url http://localhost:8100 2>&1 | grep -o "https://[^ ]*trycloudflare.com"
```

- Generates a random URL like `https://xyz.trycloudflare.com`
- **Dies every ~45 minutes** — Cloudflare kills it server-side even though the process stays alive
- When it dies: `kill <pid>`, restart for a fresh URL, **rebuild APK** with the new URL
- Check if alive: `ping <url>` or `curl <url>/v1/listings -H "X-Principal: buyer-rohan"`

### Named tunnel (BROKEN — backlogged)

- Name: `desi-bazaar`, ID: `b4155904-78fb-462b-9402-67b3d8bdde73`
- Config: `/home/sivab/.cloudflared/desi-bazaar.yml`
- Hostname `b4155904-78fb-462b-9402-67b3d8bdde73.cfargotunnel.com` only resolves to IPv6 ULA (`fd10:aec2:5dae::`)
- Unreachable from AIBeast and phone. Public Hostname route was added in dashboard but didn't fix DNS.
- `cloudflared tunnel login` OAuth didn't complete (browser authorized, cert never downloaded).
- **Status**: backlogged. Needs Cloudflare support or alternative approach.

## APK build

```bash
cd /mnt/d/phone/Desi-Bazaar-Complete-Package/mobile
flutter pub get          # first time / after pubspec changes
flutter analyze          # must be clean
flutter test             # must pass
flutter build apk --release --dart-define=API_URL=https://<tunnel-url>
# Output: build/app/outputs/flutter-apk/app-release.apk
```

**IMPORTANT**: Always verify you're building from the right source:
```bash
grep -n "kAppVersion" /mnt/d/phone/Desi-Bazaar-Complete-Package/mobile/lib/version.dart
# Should return: 4:const String kAppVersion = '1.12.0';
```

The app shows **"v1.12.0 (12) — About"** at the bottom of the login screen. If you don't see it, you're on an old APK.

## Backend tests

```bash
cd /mnt/d/phone/Desi-Bazaar-Complete-Package/implementation-review/vertical-slice
.venv/bin/pytest test_registration.py -q
# 17 tests: 12 registration/validation + 5 SMTP config/fallback
```

## Current status (2026-10-12)

### ✅ Working
- Phone OTP → registration → main screen navigation
- Version/About info visible in app
- Backend API via quick tunnel (phone on any network)
- Registration spinner clears on errors
- Already-registered users sign in without hang

### ❌ Broken
- **Email OTP**: Turbify account `assistant@balticitsystems.com` accepts SMTP login but refuses to send (554 error). Account-level restriction — needs Turbify support.
- **Named tunnel DNS**: IPv6-only, unreachable. Backlogged.

### ⏳ Pending
- Real launcher icon
- Nightly regression registration
- Production hardening (in-memory storage, session tokens, DAC7 legal review)
- GitHub push of v12 commit (needs Siva's token)
