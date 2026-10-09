# Desi Bazaar — Flutter app (iOS + Android, one codebase)

Marketplace app for the slice-1 backend (`../vertical-slice/`), built
against `../openapi.yaml` + `../media-ads-contract.md` (frozen SRS v1.5,
SC-1 ads, SC-2 listing video).

## Screens

- **Buyer:** browse/search (with Sponsored slot + labels), listing detail
  (photo carousel + video player, badge scope+date, prominent defect
  disclosure), reserve → checkout sheet (immutable snapshot recipient +
  amount, pay-in-Swish instructions), order tracker (five dimensions),
  review.
- **Seller:** listings + create (up to 8 photos via gallery/camera, up to 2
  videos ≤60s, client-side compression before upload per NFR-P1), incoming
  orders, Swish-recipient change (FR-S6), **Promote** (SC-1: day picker with
  prices from `/v1/ads/config`, stub payment → honest "pending admin
  review" state).
- **Auth:** phone/email → OTP (stub in slice); dev quick sign-ins.
- **Admin:** seller approval queue (checklist version + reason).

## Media upload flow (contract)

`POST /v1/media/upload-url` → `PUT` bytes → `POST /v1/media/{id}/complete`
→ `media_ids` attached on `POST /v1/listings`. 422s (type/size/server
rejection) surface as user-readable messages, never silent.

## Ads (SC-1)

Promoted listings rank first with a "Sponsored" label + distinct card;
the label renders exactly when the backend says `promoted` (DB-TC-189).
`SponsoredSlot` renders the feed slot when served, otherwise nothing.
Payment is a slice stub; production is Swish Företag to Baltic Systems AB
(platform revenue, separate from marketplace payments).

## Tests

```sh
flutter test            # 13 widget/unit tests (5 existing + 8 media/ads)
flutter analyze         # clean
```

Screenshots: `screenshots/` (7 original + `08-create-with-media.png`,
`09-sponsored-feed.png`).

## Backend

Run the slice backend for live runs:
```sh
cd ../vertical-slice && .venv/bin/uvicorn app:app --port 8100
```
The app defaults to `http://localhost:8100` (web/iOS) and
`http://10.0.2.2:8100` (Android emulator); override with
`--dart-define=API_URL=...`.

## Honest limits (review build)

- Auth is the `X-Principal` dev header (TODO: OTP sessions).
- No real SMS, push, or device builds from the agent VM — see
  `MORNING_SETUP.md` for Siva's machine.
- Video duration probing is native-only; on web the server re-checks on
  complete (contract) and the UI states the 60s limit up front.
