# Desi Bazaar

A marketplace mobile app (iOS + Android) for the South Asian community in Sweden — eBay-style buying and selling with trust built in: manual admin seller approval, AI-moderated reviews, direct buyer→seller Swish payments.

Built as a portfolio/showcase project by [Baltic Systems AB](https://balticitsystems.com), demonstrating spec-first engineering: frozen requirements → adversarial review → implementation with honest test evidence.

## Status

**Vertical slice in progress.** The transaction engine, API, and mobile app are implemented against SRS v1.6. OTP is stubbed in development (codes print in the backend terminal — no real SMS/email is sent). Not production-ready: launch is gated on legal review and acceptance-test evidence.

## What's here

```
backend/          FastAPI vertical slice (auth, sellers, listings, orders, media, ads)
  migrations/     Postgres migrations 001–004
  tests/          demo checks, 43/43 transition tests, 8/8 end-to-end simulation acts
mobile/           Flutter app (buyer, seller, admin screens)
docs/             SRS v1.6, design document, test plan (191 cases), OpenAPI spec
```

## Honest test record (2026-10-09)

- Backend transition engine: **43/43 passed**
- Synthetic backend demo: **30/30 passed**
- End-to-end simulation (8 acts, real OTP endpoints): **8/8 passed**
- Combined backend suite: **51/51 passed**
- Flutter suite: 27/27 on last device run; re-run pending after latest changes

## Quick start (backend)

```bash
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/uvicorn app:app --port 8100
```

## License

TBD
