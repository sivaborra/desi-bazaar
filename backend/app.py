"""
Desi Bazaar — executable synthetic-data vertical slice (for review).

Slice 1 core loop against the REAL transition engine (../engine.py):
browse -> reserve (atomic) -> checkout -> report payment -> seller confirms ->
dispatch -> receipt -> review, plus dispute and guard-rejection paths.

Persistence is in-memory dicts (synthetic data only, IC-3). The Postgres
migrations in ../migrations are the production persistence target.

Auth is a demo stub: pass X-Principal with a user id from synthetic_data.
In production this comes from the OTP session (NFR-S1); actor identity is
always derived server-side (design §9).

Run:  .venv/bin/uvicorn app:app --port 8100   (from this directory)
"""
import sys
import os
import uuid

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response

from engine import (
    Engine, Order, GuardFailed, BadActor, VersionConflict,
    OperationConflict, Forbidden,
)
from synthetic_data import USERS, LISTINGS

app = FastAPI(title="Desi Bazaar — vertical slice (synthetic)")

# CORS: the Flutter web build calls this API from a browser origin.
# No spec behavior change — only cross-origin headers.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

engine = Engine()
units = {}    # unit_id -> {"listing_id": ..., "status": available|reserved|sold}
orders = {}   # order_id -> Order
snapshots = {}  # snapshot_id -> dict
reviews = {}  # order_id -> review

for lid, l in LISTINGS.items():
    for u in l["units"]:
        units[u] = {"listing_id": lid, "status": "available"}


def principal(x_principal: str | None):
    if not x_principal or x_principal not in USERS:
        raise HTTPException(401, "unknown principal (demo auth: X-Principal header)")
    return USERS[x_principal]


def actor_for(user, order: Order | None, order_meta: dict | None):
    """Derive actor from the authenticated principal — never from the request body."""
    if user["role"] == "admin":
        return "admin"
    if order_meta:
        if user["id"] == order_meta["buyer_id"]:
            return "buyer"
        if user["id"] == order_meta["seller_id"]:
            return "seller"
    raise HTTPException(403, "principal is not a party to this order")


def order_view(order_id, order, meta):
    return {
        "id": order_id,
        "dimensions": {
            "payment": order.payment,
            "fulfilment": order.fulfilment,
            "cancel_refund": order.cancel,
            "dispute": order.dispute,
            "return": order.ret,
        },
        "order_version": order.version,
        "buyer_id": meta["buyer_id"],
        "seller_id": meta["seller_id"],
        "snapshot": snapshots[meta["snapshot_id"]],
    }


def translate(fn):
    try:
        return fn()
    except BadActor as e:
        raise HTTPException(403, str(e))
    except Forbidden as e:
        raise HTTPException(403, str(e))
    except VersionConflict as e:
        raise HTTPException(409, f"VERSION_CONFLICT: {e}")
    except OperationConflict as e:
        raise HTTPException(409, f"OPERATION_CONFLICT: {e}")
    except GuardFailed as e:
        raise HTTPException(422, f"GUARD_FAILED: {e}")


@app.get("/v1/listings")
def list_listings(q: str | None = None, x_principal: str | None = Header(default=None)):
    principal(x_principal)
    promoted_ids = {p["listing_id"] for p in _active_promotions()}
    items = []
    for lid, l in LISTINGS.items():
        if q and q.lower() not in (l["category"] + " " + l["condition"]).lower():
            continue
        seller = USERS[l["seller_id"]]
        if seller["status"] != "approved":
            continue  # pending sellers' listings are not visible
        is_promoted = lid in promoted_ids
        items.append({
            "id": lid, "category": l["category"], "condition": l["condition"],
            "size_text": l["size_text"], "price_sek": l["price_sek"],
            # BUG-005 fix: seller ownership is returned so the seller app can
            # show a true "my listings" list.
            "seller_id": l["seller_id"],
            "seller_badge": {"scope": seller["badge_scope"], "date": seller["badge_date"]},
            "units_available": sum(1 for u in l["units"] if units[u]["status"] == "available"),
            # SC-1: active promotions rank first, labelled "Sponsored".
            # DB-TC-189: non-promoted items never carry the label.
            "promoted": is_promoted,
            "label": "Sponsored" if is_promoted else None,
            "media": [{"media_id": mid, "kind": media[mid]["kind"],
                       "thumb_url": f"/v1/media/{mid}"}
                      for mid in l.get("media_ids", []) if mid in media],
        })
    # promoted first (stable otherwise)
    items.sort(key=lambda it: (not it["promoted"],))
    return {"items": items}


@app.post("/v1/listings/{listing_id}/reserve", status_code=201)
def reserve(listing_id: str, x_principal: str | None = Header(default=None)):
    user = principal(x_principal)
    if user["role"] != "buyer":
        raise HTTPException(403, "only buyers reserve")
    listing = LISTINGS.get(listing_id)
    if not listing or USERS[listing["seller_id"]]["status"] != "approved":
        raise HTTPException(404, "listing not available")
    if USERS[listing["seller_id"]].get("recipient_hold"):
        raise HTTPException(403, "new orders blocked: seller recipient pending admin re-verification (FR-S6)")
    # atomic unit allocation: exactly one winner
    won = next((u for u in listing["units"] if units[u]["status"] == "available"), None)
    if not won:
        raise HTTPException(409, "sold out")
    units[won]["status"] = "reserved"

    seller = USERS[listing["seller_id"]]
    snapshot_id = uuid.uuid4().hex
    snapshots[snapshot_id] = {  # FR-L2: immutable checkout snapshot
        "listing": {k: listing[k] for k in ("category", "condition", "size_text", "price_sek")},
        "recipient": seller["swish_recipient"],
        "amount_sek": listing["price_sek"],
    }
    order_id = uuid.uuid4().hex
    order = Order()  # all five dimensions initialised atomically (DB-TC-177)
    orders[order_id] = {"order": order, "buyer_id": user["id"],
                        "seller_id": listing["seller_id"],
                        "snapshot_id": snapshot_id, "unit_id": won}
    return order_view(order_id, order, orders[order_id])


@app.post("/v1/commands")
def command(body: dict, x_principal: str | None = Header(default=None)):
    user = principal(x_principal)
    order_id = body.get("order_id")
    meta = orders.get(order_id)
    if not meta:
        raise HTTPException(404, "order not found")
    order = meta["order"]
    actor = actor_for(user, order, meta)
    # system-only operations are executed by the demo harness directly

    def run():
        return engine.execute(
            order, order_id, actor, user["id"], body["operation"],
            payload=body.get("payload", {}),
            context=body.get("context", {}),
            expected_version=body.get("expected_order_version"),
            operation_id=body.get("operation_id"),
        )
    op_id = body.get("operation_id")
    was_replay = op_id is not None and (user["id"], op_id) in engine.bindings
    result = translate(run)
    return {
        "order_id": order_id,
        "operation_id": result["operation_id"],
        "replayed": was_replay,
        "dimensions": {
            "payment": order.payment, "fulfilment": order.fulfilment,
            "cancel_refund": order.cancel, "dispute": order.dispute,
            "return": order.ret,
        },
        "order_version": order.version,
    }


@app.get("/v1/orders/{order_id}")
def get_order(order_id: str, x_principal: str | None = Header(default=None)):
    user = principal(x_principal)
    meta = orders.get(order_id)
    if not meta:
        raise HTTPException(404, "order not found")
    actor_for(user, meta["order"], meta)  # object-level authorisation (NFR-S3)
    return order_view(order_id, meta["order"], meta)


@app.post("/v1/orders/{order_id}/review", status_code=201)
def review(order_id: str, body: dict, x_principal: str | None = Header(default=None)):
    user = principal(x_principal)
    meta = orders.get(order_id)
    if not meta:
        raise HTTPException(404, "order not found")
    actor_for(user, meta["order"], meta)
    order = meta["order"]
    eligible = order.fulfilment in ("receipt_confirmed", "delivery_evidenced")
    if not eligible:
        raise HTTPException(422, "not eligible to review (FR-R1)")
    if order_id in reviews:
        raise HTTPException(409, "one review per order")
    reviews[order_id] = {"rating": body["rating"], "text": body.get("text"),
                         "published": True}
    return {"ok": True, "review": reviews[order_id]}


@app.get("/v1/_debug/outbox")
def debug_outbox(x_principal: str | None = Header(default=None)):
    user = principal(x_principal)
    if user["role"] != "admin":
        raise HTTPException(403, "admin only")
    return {"pending": engine.outbox, "audit_entries": len(engine.audit)}


# ------------------------------------------------------------------
# Slice-1 additions: seller onboarding, OTP auth, recipient change, profile
# ------------------------------------------------------------------
import time as _time
import random as _random
from datetime import datetime as _datetime, timezone as _timezone, date as _date

OTP_MAX_REQUESTS = 5        # DB-TC-126: max 5 OTP requests...
OTP_WINDOW_S = 600          # ...per 10 minutes per phone, then 429
OTP_TTL_S = 300             # code valid 5 minutes
REAUTH_WINDOW_S = 600       # fresh OTP verify required within 10 min (FR-S6 re-auth stub)

otp_store = {}              # identifier (phone or email) -> {"code": str, "expires_at": float, "requests": [float, ...]}
applications = {}           # application_id -> application record
reapply_used = set()        # phones that already consumed their one re-application (FR-S5)


def _now_iso():
    return _datetime.now(_timezone.utc).isoformat()


def _users_with_phone(phone):
    return [u for u in USERS.values() if u.get("phone") == phone]


def _latest_seller_with_phone(phone):
    sellers = [u for u in _users_with_phone(phone) if u.get("role") == "seller"]
    return sellers[-1] if sellers else None


def _users_with_identifier(ident):
    """Find users by phone (exact) or email (case-insensitive). FR-B1."""
    low = ident.lower()
    return [u for u in USERS.values()
            if u.get("phone") == ident or str(u.get("email") or "").lower() == low]


def _latest_seller_with_identifier(ident):
    sellers = [u for u in _users_with_identifier(ident) if u.get("role") == "seller"]
    return sellers[-1] if sellers else None


def _require_admin(user):
    if user["role"] != "admin":
        raise HTTPException(403, "admin only")


def _missing_fields(body, required):
    return [f for f in required if f not in body or body[f] in (None, "", [])]


@app.post("/v1/auth/otp/request")
def otp_request(body: dict):
    """OTP registration stub (FR-B1, DB-TC-126). Phone or email identifier.
    Synthetic codes only, logged to console, never sent via SMS/email."""
    phone = (body.get("phone") or "").strip()
    email = (body.get("email") or "").strip().lower()
    if not phone and not email:
        raise HTTPException(422, "phone or email is required")
    ident = email or phone
    now = _time.time()
    entry = otp_store.setdefault(ident, {"requests": []})
    entry["requests"] = [t for t in entry["requests"] if now - t < OTP_WINDOW_S]
    if len(entry["requests"]) >= OTP_MAX_REQUESTS:
        raise HTTPException(429, "rate limited: max 5 OTP requests per 10 minutes")
    entry["requests"].append(now)
    code = f"{_random.randint(0, 999999):06d}"
    entry["code"] = code
    entry["expires_at"] = now + OTP_TTL_S
    print(f"[OTP stub] code for {ident}: {code} (synthetic — never sent)")
    return {"ok": True, "expires_in_s": OTP_TTL_S}


@app.post("/v1/auth/otp/verify")
def otp_verify(body: dict):
    """Verify an OTP code. Marks the user otp_verified and records a fresh
    re-auth timestamp (used by the recipient-change guard, FR-S6)."""
    phone = (body.get("phone") or "").strip()
    email = (body.get("email") or "").strip().lower()
    code = body.get("code")
    if (not phone and not email) or not code:
        raise HTTPException(422, "phone or email, and code are required")
    ident = email or phone
    entry = otp_store.get(ident)
    if not entry or entry.get("code") != code or _time.time() > entry.get("expires_at", 0):
        raise HTTPException(422, "invalid or expired code")
    user = _latest_seller_with_identifier(ident)
    if user is None:
        others = _users_with_identifier(ident)
        user = others[-1] if others else None
    if user is None:
        uid = f"buyer-{uuid.uuid4().hex[:8]}"  # FR-B1: free buyer registration, no approval
        user = {"id": uid, "role": "buyer", "name": "", "phone": phone or None,
                "email": email or None, "otp_verified": False}
        USERS[uid] = user
    user["otp_verified"] = True
    user["otp_verified_recent_at"] = _time.time()
    return {"user_id": user["id"], "otp_verified": True}


@app.post("/v1/sellers/applications", status_code=201)
def apply_seller(body: dict):
    """Seller application (FR-S1). Public endpoint — applicants have no account yet.
    New applications enter `pending` and cannot list (FR-S2)."""
    required = ["name", "phone", "id_document_ref", "categories", "trader"]
    missing = _missing_fields(body, required)
    if body.get("trader") and not body.get("trader_basis"):
        missing.append("trader_basis")
    if missing:
        # DB-TC-002: incomplete forms stay editable; the re-application limit is untouched
        raise HTTPException(422, f"missing fields: {missing}")
    ref = body["id_document_ref"]
    # DB-TC-133 (stub): the slice accepts an opaque document ref, not raw bytes;
    # reject obvious path traversal / executable masquerading. Full content
    # validation and encryption at rest (DB-TC-128) are production concerns.
    if (not isinstance(ref, str) or not (1 <= len(ref) <= 256)
            or ".." in ref or "/" in ref
            or ref.lower().endswith((".exe", ".bat", ".sh", ".dll", ".msi"))):
        raise HTTPException(422, "invalid id_document_ref")
    phone = body["phone"]
    prior = _latest_seller_with_phone(phone)
    if prior and prior.get("status") != "rejected":
        raise HTTPException(409, "an application for this phone is already in progress")
    if prior and prior.get("status") == "rejected":
        if phone in reapply_used:
            raise HTTPException(422, "re-application limit consumed (FR-S5: one re-apply)")
        reapply_used.add(phone)
    uid = f"seller-{uuid.uuid4().hex[:8]}"
    USERS[uid] = {
        "id": uid, "role": "seller", "name": body["name"], "phone": phone,
        "status": "pending", "badge_scope": None, "badge_date": None,
        "badge_active": False, "swish_recipient": body.get("swish_recipient"),
        "otp_verified": False, "trader": bool(body["trader"]),
        "trader_basis": body.get("trader_basis"),
    }
    app_id = f"app-{uuid.uuid4().hex[:8]}"
    applications[app_id] = {
        "id": app_id, "seller_id": uid, "phone": phone,
        "trader": bool(body["trader"]), "trader_basis": body.get("trader_basis"),
        "categories": body["categories"], "profile": body.get("profile", ""),
        "id_document_ref": ref, "status": "pending",
        "submitted_at": _now_iso(), "decision": None,
    }
    return {"application_id": app_id, "seller_id": uid, "status": "pending",
            "message": "Application received and pending review. You cannot list items until approved."}


@app.get("/v1/admin/seller-queue")
def seller_queue(x_principal: str | None = Header(default=None)):
    """Admin verification queue (FR-A1). Shows trader basis for validation (DB-TC-003)."""
    _require_admin(principal(x_principal))
    return {"applications": [
        {"id": a["id"], "seller_id": a["seller_id"], "phone": a["phone"],
         "trader": a["trader"], "trader_basis": a["trader_basis"],
         "categories": a["categories"], "submitted_at": a["submitted_at"]}
        for a in applications.values() if a["status"] == "pending"
    ]}


@app.post("/v1/admin/sellers/{seller_id}/decision")
def seller_decision(seller_id: str, body: dict,
                    x_principal: str | None = Header(default=None)):
    """Versioned checklist approval/rejection (FR-S3, FR-S5, DB-TC-005, DB-TC-176).
    Records reviewer identity + timestamp; audit-friendly."""
    admin = principal(x_principal)
    _require_admin(admin)
    seller = USERS.get(seller_id)
    if not seller or seller.get("role") != "seller":
        raise HTTPException(404, "seller not found")
    pending = [a for a in applications.values()
               if a["seller_id"] == seller_id and a["status"] == "pending"]
    if not pending:
        raise HTTPException(422, "no pending application for this seller")
    decision = body.get("decision")
    if decision not in ("approve", "reject"):
        raise HTTPException(422, "decision must be 'approve' or 'reject'")
    if not body.get("checklist_version"):
        raise HTTPException(422, "checklist_version is required")
    if decision == "reject" and not body.get("reason"):
        raise HTTPException(422, "reason is required for rejection")
    app_rec = pending[-1]
    record = {
        "decision": decision,
        "checklist_version": body["checklist_version"],
        "evidence_reviewed": body.get("evidence_reviewed", []),
        "checks": body.get("checks", []),
        "reason": body.get("reason"),
        "reviewer_id": admin["id"],          # DB-TC-005 / DB-TC-118
        "reviewer_name": admin.get("name"),
        "decided_at": _now_iso(),
    }
    app_rec["decision"] = record
    if decision == "approve":
        seller["status"] = "approved"
        seller["badge_scope"] = "ID verified"   # scope + date only, never a product guarantee
        seller["badge_date"] = str(_date.today())
        seller["badge_active"] = True
        app_rec["status"] = "approved"
    else:
        seller["status"] = "rejected"
        seller["rejection_reason"] = body["reason"]
        app_rec["status"] = "rejected"
    return {"seller_id": seller_id, **record}


@app.patch("/v1/sellers/me/recipient")
def change_recipient(body: dict, x_principal: str | None = Header(default=None)):
    """Swish recipient change (FR-S6, DB-TC-132). Requires fresh OTP re-auth;
    notifies via the outbox and blocks new orders until admin re-verifies."""
    user = principal(x_principal)
    if user.get("role") != "seller":
        raise HTTPException(403, "only sellers change recipients")
    recent = user.get("otp_verified_recent_at", 0)
    if _time.time() - recent > REAUTH_WINDOW_S:
        raise HTTPException(403, "fresh OTP verification required before changing recipient")
    new_recipient = body.get("swish_recipient")
    if not new_recipient:
        raise HTTPException(422, "swish_recipient is required")
    user["swish_recipient"] = new_recipient
    user["recipient_hold"] = True
    engine.outbox.append((user["id"], "swish_recipient_changed"))  # notify (outbox-after-commit)
    return {"swish_recipient": new_recipient, "recipient_hold": True,
            "message": "Recipient updated. New orders are blocked until an admin re-verifies."}


@app.post("/v1/admin/sellers/{seller_id}/recipient/verify")
def verify_recipient(seller_id: str, x_principal: str | None = Header(default=None)):
    """Admin re-verification after a recipient change: clears the hold (FR-S6)."""
    admin = principal(x_principal)
    _require_admin(admin)
    seller = USERS.get(seller_id)
    if not seller or seller.get("role") != "seller":
        raise HTTPException(404, "seller not found")
    if not seller.get("recipient_hold"):
        raise HTTPException(422, "no recipient hold on this seller")
    seller["recipient_hold"] = False
    seller["recipient_verified_by"] = admin["id"]
    seller["recipient_verified_at"] = _now_iso()
    return {"seller_id": seller_id, "recipient_hold": False,
            "verified_by": admin["id"], "verified_at": seller["recipient_verified_at"]}


@app.get("/v1/sellers/{seller_id}/profile")
def seller_profile(seller_id: str):
    """Public seller profile. Badge shows scope + date only — never wording that
    implies product authentication or a transaction guarantee (DB-TC-006).
    Fulfilment history shows evidenced vs unconfirmed separately (DB-TC-147)."""
    seller = USERS.get(seller_id)
    if not seller or seller.get("role") != "seller":
        raise HTTPException(404, "seller not found")
    evidenced = unconfirmed = in_progress = 0
    resolved = closed_unconfirmed = non_compliant = 0
    for meta in orders.values():
        if meta["seller_id"] != seller_id:
            continue
        f = meta["order"].fulfilment
        if f in ("receipt_confirmed", "delivery_evidenced"):
            evidenced += 1
        elif f == "delivery_unconfirmed":
            unconfirmed += 1
        else:
            in_progress += 1
        d = meta["order"].dispute
        if d == "dispute_resolved":
            resolved += 1
        elif d == "dispute_closed_unconfirmed":
            closed_unconfirmed += 1
        elif d == "dispute_non_compliant":
            non_compliant += 1
    badge = None
    if seller.get("badge_active"):
        badge = {"scope": seller["badge_scope"], "date": seller["badge_date"]}
    return {
        "seller_id": seller_id,
        "name": seller.get("name"),
        "status": seller.get("status"),
        "badge": badge,
        "fulfilment_history": {
            "evidenced": evidenced,
            "unconfirmed": unconfirmed,
            "in_progress": in_progress,
            "total_orders": evidenced + unconfirmed + in_progress,
        },
        "dispute_outcomes": {
            "resolved": resolved,
            "closed_unconfirmed": closed_unconfirmed,
            "non_compliant": non_compliant,
        },
        "response_time": {"value": None,
                          "basis": "not measured in synthetic slice"},
    }


@app.post("/v1/listings", status_code=201)
def create_listing(body: dict, x_principal: str | None = Header(default=None)):
    """Minimal listing creation (slice-1): approved sellers only (FR-S2, DB-TC-004).
    SC-2: accepts media_ids — max 8 images + max 2 videos, each accepted and
    owned by the seller, else 422."""
    user = principal(x_principal)
    if user.get("role") != "seller":
        raise HTTPException(403, "only sellers create listings")
    if user.get("status") != "approved":
        raise HTTPException(403, "seller not approved — cannot create listings")
    missing = _missing_fields(body, ["category", "condition", "size_text", "price_sek"])
    if missing:
        raise HTTPException(422, f"missing fields: {missing}")
    media_ids = body.get("media_ids", [])
    if not isinstance(media_ids, list):
        raise HTTPException(422, "media_ids must be a list")
    images, videos = [], []
    for mid in media_ids:
        rec = media.get(mid)
        if not rec or rec["status"] != "accepted":
            raise HTTPException(422, f"media {mid!r} is not accepted")
        if rec["owner_id"] != user["id"]:
            raise HTTPException(422, f"media {mid!r} is not yours")
        if rec["purpose"] not in ("listing_image", "listing_video"):
            raise HTTPException(422, f"media {mid!r} has wrong purpose for a listing")
        (videos if rec["kind"] == "video" else images).append(mid)
    if len(images) > LISTING_MAX_IMAGES:
        raise HTTPException(422, f"max {LISTING_MAX_IMAGES} images per listing (SC-2)")
    if len(videos) > LISTING_MAX_VIDEOS:
        raise HTTPException(422, f"max {LISTING_MAX_VIDEOS} videos per listing (SC-2)")
    lid = f"listing-{uuid.uuid4().hex[:8]}"
    unit_id = f"unit-{uuid.uuid4().hex[:8]}"
    LISTINGS[lid] = {
        "id": lid, "seller_id": user["id"], "category": body["category"],
        "condition": body["condition"], "size_text": body["size_text"],
        "defect_disclosure": body.get("defect_disclosure"),
        "price_sek": body["price_sek"], "units": [unit_id],
        "media_ids": media_ids,
    }
    units[unit_id] = {"listing_id": lid, "status": "available"}
    return {"id": lid, "status": "created", "media_ids": media_ids}


# ------------------------------------------------------------------
# Media upload (SC-2) + Ads (SC-1)
# ------------------------------------------------------------------
import hashlib as _hashlib

from synthetic_data import SEED_PROMOTIONS

MEDIA_PURPOSES = {"listing_image", "listing_video", "dispute_evidence", "id_document"}
IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp"}
VIDEO_TYPES = {"video/mp4"}
IMAGE_MAX_BYTES = 10 * 1024 * 1024      # 10 MB
VIDEO_MAX_BYTES = 100 * 1024 * 1024    # 100 MB
LISTING_MAX_IMAGES = 8                 # SC-2
LISTING_MAX_VIDEOS = 2                 # SC-2

media = {}          # media_id -> record (slice stub for the object store)

ads_config = {"currency": "SEK", "prices": {"1": 29, "3": 69, "7": 129}}
promotions = {}     # promotion_id -> record
ad_slot_cursor = {"n": 0}


def _validate_media_bytes(rec):
    """Server-side type/size/content validation (NFR-S4). Returns (ok, reason)."""
    data, ct = rec["bytes"], rec["content_type"]
    if len(data) > rec["content_length"]:
        return False, "uploaded bytes exceed declared content_length"
    if ct == "image/jpeg" and not data.startswith(b"\xff\xd8\xff"):
        return False, "not a JPEG (magic bytes mismatch)"
    if ct == "image/png" and not data.startswith(b"\x89PNG\r\n\x1a\n"):
        return False, "not a PNG (magic bytes mismatch)"
    if ct == "image/webp" and not (data.startswith(b"RIFF") and data[8:12] == b"WEBP"):
        return False, "not a WebP (magic bytes mismatch)"
    if ct == "video/mp4" and not (len(data) >= 12 and data[4:8] == b"ftyp"):
        return False, "not an MP4 (ftyp box missing)"
    return True, None


@app.post("/v1/media/upload-url", status_code=201)
def media_upload_url(body: dict, x_principal: str | None = Header(default=None)):
    """Signed-URL flow, step 1 (SC-2). Slice stubs the object store: upload_url
    points back at this API."""
    user = principal(x_principal)
    purpose = body.get("purpose")
    content_type = body.get("content_type")
    content_length = body.get("content_length")
    if purpose not in MEDIA_PURPOSES:
        raise HTTPException(422, f"purpose must be one of {sorted(MEDIA_PURPOSES)}")
    allowed = VIDEO_TYPES if purpose == "listing_video" else IMAGE_TYPES
    if content_type not in allowed:
        raise HTTPException(422, f"content_type {content_type!r} not allowed for {purpose}")
    if not isinstance(content_length, int) or content_length <= 0:
        raise HTTPException(422, "content_length must be a positive integer")
    limit = VIDEO_MAX_BYTES if purpose == "listing_video" else IMAGE_MAX_BYTES
    if content_length > limit:
        raise HTTPException(422, f"content_length {content_length} exceeds {limit} bytes for {purpose}")
    media_id = f"media-{uuid.uuid4().hex[:12]}"
    media[media_id] = {
        "id": media_id, "owner_id": user["id"], "purpose": purpose,
        "content_type": content_type, "content_length": content_length,
        "kind": "video" if purpose == "listing_video" else "image",
        "status": "uploading", "bytes": None, "created_at": _now_iso(),
    }
    return {"media_id": media_id, "upload_url": f"/v1/media/{media_id}/bytes",
            "expires_at": _now_iso()}


@app.put("/v1/media/{media_id}/bytes")
async def media_put_bytes(media_id: str, request: Request,
                          x_principal: str | None = Header(default=None)):
    """Signed-URL flow, step 2: bytes land here (slice stub store)."""
    user = principal(x_principal)
    rec = media.get(media_id)
    if not rec:
        raise HTTPException(404, "media not found")
    if rec["owner_id"] != user["id"]:
        raise HTTPException(403, "not your upload")
    if rec["status"] != "uploading":
        raise HTTPException(422, "upload already completed")
    data = await request.body()
    if len(data) != rec["content_length"]:
        raise HTTPException(422,
                            f"received {len(data)} bytes, declared {rec['content_length']}")
    rec["bytes"] = data
    return {"ok": True, "received_bytes": len(data)}


@app.post("/v1/media/{media_id}/complete")
def media_complete(media_id: str, body: dict,
                   x_principal: str | None = Header(default=None)):
    """Signed-URL flow, step 3: validate type/size/content (+ checksum) and queue
    moderation screening (FR-R7; slice: stubbed allow, clearly marked)."""
    user = principal(x_principal)
    rec = media.get(media_id)
    if not rec:
        raise HTTPException(404, "media not found")
    if rec["owner_id"] != user["id"]:
        raise HTTPException(403, "not your upload")
    if rec["status"] != "uploading":
        raise HTTPException(422, "upload already completed")
    if rec["bytes"] is None:
        raise HTTPException(422, "no bytes uploaded yet")
    checksum = body.get("checksum")
    if checksum and checksum != _hashlib.sha256(rec["bytes"]).hexdigest():
        rec["status"] = "rejected"
        rec["reason"] = "checksum mismatch"
        return {"status": "rejected", "reason": "checksum mismatch"}
    ok, reason = _validate_media_bytes(rec)
    if not ok:
        rec["status"] = "rejected"
        rec["reason"] = reason
        return {"status": "rejected", "reason": reason}
    rec["status"] = "accepted"
    rec["moderation"] = "stub-allow — production queues FR-R7 image screening here"
    return {"status": "accepted"}


@app.get("/v1/media/{media_id}")
def media_get(media_id: str):
    """Serve bytes (slice). Production returns a signed read URL. Public: listing
    media is visible to buyers."""
    rec = media.get(media_id)
    if not rec or rec["status"] != "accepted" or rec["bytes"] is None:
        raise HTTPException(404, "media not found")
    return Response(content=rec["bytes"], media_type=rec["content_type"])


# ---------------- Ads (SC-1) ----------------

def _active_promotions():
    """Lazy expiry: active -> expired on read (slice). Production: worker."""
    now = _time.time()
    for p in promotions.values():
        if p["state"] == "active" and p.get("expires_at_ts", 0) <= now:
            p["state"] = "expired"
    return [p for p in promotions.values() if p["state"] == "active"]


def _promotion_view(p):
    view = {"promotion_id": p["id"], "listing_id": p["listing_id"],
            "seller_id": p["seller_id"], "days": p["days"],
            "amount_sek": p["amount_sek"], "state": p["state"]}
    if p.get("expires_at"):
        view["expires_at"] = p["expires_at"]
    return view


@app.get("/v1/ads/config")
def ads_config_get(x_principal: str | None = Header(default=None)):
    principal(x_principal)
    return {"currency": ads_config["currency"], "prices": dict(ads_config["prices"])}


@app.put("/v1/admin/ads/config")
def ads_config_put(body: dict, x_principal: str | None = Header(default=None)):
    _require_admin(principal(x_principal))
    prices = body.get("prices")
    if not isinstance(prices, dict) or not prices:
        raise HTTPException(422, "prices must be a non-empty map of days -> price_sek")
    for days, price in prices.items():
        if not (isinstance(price, int) and price > 0):
            raise HTTPException(422, f"invalid price for {days!r}")
    ads_config["prices"] = {str(k): v for k, v in prices.items()}
    if "currency" in body:
        ads_config["currency"] = body["currency"]
    return {"currency": ads_config["currency"], "prices": dict(ads_config["prices"])}


@app.post("/v1/ads/promotions", status_code=201)
def promotion_create(body: dict, x_principal: str | None = Header(default=None)):
    """Seller buys a boost for an owned, approved-seller listing (SC-1)."""
    user = principal(x_principal)
    if user.get("role") != "seller":
        raise HTTPException(403, "only sellers create promotions")
    listing = LISTINGS.get(body.get("listing_id"))
    if not listing or listing["seller_id"] != user["id"]:
        raise HTTPException(404, "listing not found")
    if USERS[listing["seller_id"]].get("status") != "approved":
        raise HTTPException(422, "listing must belong to an approved seller")
    price = ads_config["prices"].get(str(body.get("days")))
    if price is None:
        raise HTTPException(422, f"days must be one of {sorted(ads_config['prices'])}")
    pid = f"promo-{uuid.uuid4().hex[:8]}"
    promotions[pid] = {
        "id": pid, "listing_id": listing["id"], "seller_id": user["id"],
        "days": int(body["days"]), "amount_sek": price, "state": "pending_payment",
        "created_at": _now_iso(),
    }
    return {"promotion_id": pid, "state": "pending_payment", "amount_sek": price}


@app.post("/v1/ads/promotions/{promotion_id}/pay")
def promotion_pay(promotion_id: str, x_principal: str | None = Header(default=None)):
    """Stub payment (slice). Production: Swish Företag to Baltic Systems AB —
    platform revenue, separate from marketplace payments."""
    user = principal(x_principal)
    p = promotions.get(promotion_id)
    if not p:
        raise HTTPException(404, "promotion not found")
    if p["seller_id"] != user["id"]:
        raise HTTPException(403, "not your promotion")
    if p["state"] != "pending_payment":
        raise HTTPException(422, f"promotion is {p['state']}, not pending_payment")
    p["state"] = "pending_review"
    p["paid_at"] = _now_iso()
    p["payment"] = "stub — production: Swish Företag to Baltic Systems AB"
    return {"promotion_id": promotion_id, "state": "pending_review"}


@app.post("/v1/admin/ads/promotions/{promotion_id}/decision")
def promotion_decide(promotion_id: str, body: dict,
                     x_principal: str | None = Header(default=None)):
    """Admin review: approve -> active (expires_at = now + days) or rejected."""
    admin = principal(x_principal)
    _require_admin(admin)
    p = promotions.get(promotion_id)
    if not p:
        raise HTTPException(404, "promotion not found")
    if p["state"] != "pending_review":
        raise HTTPException(422, f"promotion is {p['state']}, not pending_review")
    approve = body.get("approve")
    if approve is True:
        p["state"] = "active"
        p["expires_at_ts"] = _time.time() + p["days"] * 86400
        p["expires_at"] = _datetime.fromtimestamp(
            p["expires_at_ts"], _timezone.utc).isoformat()
    elif approve is False:
        p["state"] = "rejected"
        p["reason"] = body.get("reason")
    else:
        raise HTTPException(422, "approve must be true or false")
    p["decided_by"] = admin["id"]
    p["decided_at"] = _now_iso()
    return _promotion_view(p)


@app.get("/v1/ads/slot")
def ads_slot(placement: str | None = None,
             x_principal: str | None = Header(default=None)):
    """Sponsored slot inventory (slice: serves active promotions round-robin, else empty)."""
    principal(x_principal)
    if placement != "feed":
        raise HTTPException(422, "placement must be 'feed' (slice supports feed only)")
    active = _active_promotions()
    if not active:
        return {"type": "none", "placement": placement}
    p = active[ad_slot_cursor["n"] % len(active)]
    ad_slot_cursor["n"] += 1
    return {"type": "promotion", "placement": placement,
            "promotion_id": p["id"], "listing_id": p["listing_id"],
            "label": "Sponsored"}


# Seed one active promotion so the Flutter track sees promoted ranking (SC-1).
for _sp in SEED_PROMOTIONS:
    _pid = f"promo-seed-{uuid.uuid4().hex[:6]}"
    _exp_ts = _time.time() + _sp["days"] * 86400
    promotions[_pid] = {
        "id": _pid, "listing_id": _sp["listing_id"], "seller_id": _sp["seller_id"],
        "days": _sp["days"], "amount_sek": ads_config["prices"][str(_sp["days"])],
        "state": "active", "expires_at_ts": _exp_ts,
        "expires_at": _datetime.fromtimestamp(_exp_ts, _timezone.utc).isoformat(),
        "created_at": _now_iso(), "decided_by": "admin-1", "decided_at": _now_iso(),
        "payment": "seed (synthetic)",
    }
