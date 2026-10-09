# Desi Bazaar — Morning Setup (run the app on your machine)

You have VS Code / Antigravity with (probably) the Android SDK. The app was
built and widget-tested overnight on a Linux VM that has no Android SDK, so
this is the first time it meets a real device. Copy-paste friendly.

## 1. Open the project

1. Open VS Code (or Antigravity).
2. Install the **Flutter** extension (by Dart Code) if it isn't there:
   Extensions view → search "Flutter" → Install.
3. File → Open Folder → select this folder:
   `implementation-review/mobile/desi_bazaar`

## 2. Sanity check

Open a terminal **inside that folder** and run:

```sh
flutter doctor
```

You want green ticks on `Flutter`, `Android toolchain`, and your IDE.
If `Android toolchain` complains about licenses, run:

```sh
flutter doctor --android-licenses
```
(accept with `y`).

## 3. Start a device

Either:

- **Emulator:** in VS Code, open the Command Palette (`Ctrl+Shift+P`),
  type `Flutter: Launch Emulator`, pick (or create) a Pixel device; or
- **Your own phone:** enable Developer options → USB debugging, plug it in,
  accept the RSA prompt. Check it appears with:

```sh
flutter devices
```

## 4. Point the app at the backend

The FastAPI backend from the review package must be reachable. Two options:

### Option A — run the backend locally (recommended)

```sh
cd implementation-review/vertical-slice
python3 -m venv .venv
.venv/bin/pip install -q fastapi uvicorn httpx pytest
.venv/bin/uvicorn app:app --port 8100
```

Then launch the app with:

```sh
flutter run --dart-define=API_URL=http://10.0.2.2:8100   # Android emulator
flutter run --dart-define=API_URL=http://localhost:8100  # physical phone via USB (adb reverse) or iOS simulator
```

> Physical Android phone over USB: run `adb reverse tcp:8100 tcp:8100` first,
> then `API_URL=http://localhost:8100` works too.

### Option B — use the VM's backend (port-forward)

If the overnight VM is still up and the backend runs there on port 8100,
forward it:

```sh
ssh -L 8100:localhost:8100 <your-vm>
```

then `flutter run --dart-define=API_URL=http://localhost:8100`.

No `--dart-define` at all also works: the app defaults to
`http://10.0.2.2:8100` on Android and `http://localhost:8100` elsewhere.

## 5. Sign in (demo)

On the sign-in screen you have two paths:

- **Real OTP flow:** enter a phone number *or* email (toggle on the sign-in screen) → the backend prints the 6-digit
  code in *its* console (never SMS in this build) → type it in.
- **Developer shortcuts:** "Buyer: Rohan", "Seller: Anaya", "Admin" — these
  sign straight in as the synthetic users. Clearly labelled; not a login
  method, just for trying the flows.

Try: Browse → open the saree → Reserve → checkout sheet (recipient + amount)
→ "I have paid" → order tracker shows the five dimensions.

## 6. Run the tests

```sh
flutter test
```

Expect all 5 widget tests green (browse, checkout, tracker, guard-error,
review). There is also `test/screenshot_test.dart` (4 tests) which drives
the REAL app against the REAL backend and writes PNG goldens — it needs
the backend running on :8100 and proxy vars unset; see the file header.
Backend suite, from `vertical-slice/`:

```sh
.venv/bin/python -m pytest ../transition-tests/test_transitions.py -q   # 43 passed
.venv/bin/python demo.py                                                # 25 steps, ALL DEMO CHECKS PASSED
```

## Known limits (not bugs — future work)

- No real SMS, no push notifications, no real Swish integration: money moves
  in the user's own Swish app; the app records assertions only (Phase-1 model).
- Auth is phone/email + OTP stub — no BankID by design (FR-B1). Codes print to the backend console; use one email per role to test buyer/seller/admin flows.
- `flutter build apk` / `flutter build ipa` not yet attempted — that's the
  next step once it runs clean on your emulator/phone.
- Screenshots in `screenshots/` are the real app against the real backend,
  captured via the test harness (the VM's Chromium is org-blocked from
  localhost, so no live browser shots). Closest executable proof available
  from the VM; a `flutter build web` output also exists in `build/web/`.
