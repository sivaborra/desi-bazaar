# Desi Bazaar widget-test suite

## Test files

| File | Backend? | What it proves |
|---|---|---|
| `app_test.dart` | No (FakeApiClient) | Browse, reserve→checkout, tracker dimensions, guard-error presentation, review submit (FR-R1 positive + negative presentation) |
| `media_ads_test.dart` | No (fakes) | SC-2/SC-1: photo limits, upload call sequence, 422 surfacing, Sponsored label, promote flow, carousel, image compression (NFR-P1) |
| `backend_enforcement_test.dart` | **Yes** (real slice backend) | Backend transition guards (dispatch-before-confirm → real 422), FR-R1 review eligibility positive + negative (real 201/422/409) |
| `screenshot_test.dart` | No (fakes, realistic seed) | Golden verification of auth/browse/detail/checkout/tracker/seller/admin screens |
| `media_ads_shots_test.dart` | No (fakes) | Golden verification of create-with-media + Sponsored feed screens |
| `test_setup.dart` | — | Shared setup: bundled test font, HTTP overrides, backend probe, phone viewports |

All files use `test_setup.dart` — no duplicated loaders, no stray global state.

## Screenshot capture vs regression verification

These are **separate commands with separate acceptance criteria**:

**Capture** (writes goldens, compares nothing):
```sh
env -u https_proxy -u http_proxy -u HTTPS_PROXY -u HTTP_PROXY \
    -u ALL_PROXY -u all_proxy \
    flutter test test/screenshot_test.dart test/media_ads_shots_test.dart --update-goldens
```
Acceptance: all PNGs in `test/goldens/` and `screenshots/` are produced and
visually show the expected screen (auth, browse, detail, checkout, tracker,
seller home, admin queue, create-with-media, sponsored feed).

**Verify** (compares against goldens, writes nothing):
```sh
env -u https_proxy -u http_proxy -u HTTPS_PROXY -u HTTP_PROXY \
    -u ALL_PROXY -u all_proxy \
    flutter test test/screenshot_test.dart test/media_ads_shots_test.dart
```
Acceptance: every `matchesGoldenFile` passes. Note the honest caveat: text
renders with the bundled test font, so these are proof-of-execution shots,
not cross-machine golden masters — do not promote them as such.

Convenience wrappers: `test/capture_screenshots.sh`, `test/verify_screenshots.sh`
(note: the scripts run plain `flutter test`, which needs pub.dev reachable;
on this VM use the `--no-pub` commands above — the sandbox proxy blocks pub).

## Full suite

```sh
# 1. backend fresh (in-memory state):
cd vertical-slice && .venv/bin/uvicorn app:app --port 8100
# 2. from mobile/desi_bazaar:
env -u https_proxy -u http_proxy -u HTTPS_PROXY -u HTTP_PROXY \
    -u ALL_PROXY -u all_proxy \
    flutter test
```
Acceptance: all tests pass. `flutter analyze` must be clean.

## Honest limits of this suite (read before trusting it)

- **No device verification on this VM.** There is no phone, emulator, or
  simulator here, so `image_picker` and camera capture are NOT verified on a
  physical device in this environment. Widget tests use in-memory synthetic
  bytes via `FakeMediaPicker` (labelled as fakes, not device proof). Camera
  and gallery picking MUST be verified on Siva's machine per
  `mobile/MORNING_SETUP.md` before any launch claim.
- **Real socket I/O hangs inside `testWidgets` on this VM** (verified with
  raw `Socket.connect`: works in plain `test()`, hangs in `testWidgets`).
  Therefore live-backend assertions live in plain `test()`s
  (`backend_enforcement_test.dart`); widget tests use fakes. Revisit on a
  real device/CI runner.
- **Screenshots are proof-of-execution**, not cross-machine golden masters
  (test font is bundled, but rendering still varies by platform).
- The slice backend is in-memory with stubbed OTP, object storage,
  moderation, and promotion payment.

