"""
Desi Bazaar — marketplace simulation tests (2026-10-09).

A full dress rehearsal with realistic (synthetic) identities instead of stub principals:
  - Buyer:  buyer@example.se    (email OTP)
  - Seller: seller@example.se   (email OTP) + synthetic Swish phone for the
            seller application and payouts
  - Admin:  admin-1             (seed principal)

Unlike demo.py (which uses the X-Principal dev header directly), this exercises
the REAL registration path: OTP request -> synthetic code -> verify -> user id,
exactly as the phone app does it. The "email delivery" step is simulated by
reading the stub's code from otp_store — in production the code would arrive
by email.

Run:  .venv/bin/python -m pytest test_simulation.py -v   (from vertical-slice/)
"""
import sys
import os
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient
from app import app, otp_store

client = TestClient(app)

BUYER_EMAIL = "buyer@example.se"
SELLER_EMAIL = "seller@example.se"
SELLER_PHONE = "+46700000090"          # synthetic seller Swish/phone (FR-S1 application)
ADMIN = {"X-Principal": "admin-1"}

_ctx = {}  # shared simulation state between the acts


def _otp_login(email):
    """Simulate a user tapping 'send code', reading their email, and verifying."""
    r = client.post("/v1/auth/otp/request", json={"email": email})
    assert r.status_code == 200, f"OTP request failed for {email}: {r.text}"
    # In production the code arrives by email; here we read the stub's outbox.
    code = otp_store[email.lower()]["code"]
    r = client.post("/v1/auth/otp/verify", json={"email": email, "code": code})
    assert r.status_code == 200 and r.json()["otp_verified"] is True
    user_id = r.json()["user_id"]
    print(f"    {email} verified -> user {user_id}")
    return {"X-Principal": user_id}


def _cmd(principal, order_id, operation, **kw):
    body = {"operation_id": uuid.uuid4().hex, "order_id": order_id,
            "operation": operation}
    body.update(kw)
    r = client.post("/v1/commands", headers=principal, json=body)
    return r


# ------------------------------------------------------------------ the play

def test_01_buyer_registers_via_email_otp():
    print("\n=== Act 1: buyer registers with email OTP")
    _ctx["buyer"] = _otp_login(BUYER_EMAIL)
    # Same email twice -> same account (FR-B1 identity rule)
    again = _otp_login(BUYER_EMAIL)
    assert again == _ctx["buyer"], "same email must resolve to the same account"


def test_02_seller_registers_and_applies():
    print("\n=== Act 2: seller registers with email OTP and applies")
    _ctx["seller_person"] = _otp_login(SELLER_EMAIL)

    # Incomplete application stays editable, consumes nothing (DB-TC-002)
    r = client.post("/v1/sellers/applications", json={"name": "Siva Borra"})
    assert r.status_code == 422
    print("    incomplete application -> 422 (stays editable)")

    r = client.post("/v1/sellers/applications", json={
        "name": "Siva Borra", "phone": SELLER_PHONE,
        "id_document_ref": "ref-idoc-siva-001",
        "categories": ["saree", "kurti"],
        "profile": "Pre-loved desi wear, Upplands Väsby.",
        "trader": False, "swish_recipient": SELLER_PHONE})
    assert r.status_code == 201 and r.json()["status"] == "pending"
    _ctx["seller_id"] = r.json()["seller_id"]
    _ctx["seller"] = {"X-Principal": _ctx["seller_id"]}
    print(f"    application accepted -> seller {_ctx['seller_id']} (pending)")

    # Pending sellers cannot list (FR-S2, DB-TC-004)
    r = client.post("/v1/listings", headers=_ctx["seller"], json={
        "category": "saree", "condition": "like_new",
        "size_text": "M", "price_sek": 450})
    assert r.status_code == 403
    print("    pending seller lists -> 403 (correctly blocked)")


def test_03_admin_approves_seller():
    print("\n=== Act 3: admin approves the seller")
    assert _ctx.get("seller_id"), "run Act 2 first"
    queue = client.get("/v1/admin/seller-queue", headers=ADMIN).json()
    assert any(a["seller_id"] == _ctx["seller_id"] for a in queue["applications"])
    r = client.post(f"/v1/admin/sellers/{_ctx['seller_id']}/decision", headers=ADMIN,
                    json={"decision": "approve", "checklist_version": "v1",
                          "evidence_reviewed": ["id_document"],
                          "checks": ["identity"], "reason": "ID verified"})
    assert r.status_code == 200 and r.json()["reviewer_id"] == "admin-1"
    badge = client.get(f"/v1/sellers/{_ctx['seller_id']}/profile").json()["badge"]
    assert badge["scope"] == "ID verified"
    print(f"    approved by {r.json()['reviewer_id']}; badge: {badge['scope']}")


def test_04_seller_lists_item():
    print("\n=== Act 4: seller lists a saree")
    assert _ctx.get("seller"), "run Act 3 first"
    r = client.post("/v1/listings", headers=_ctx["seller"], json={
        "category": "saree", "condition": "like_new", "size_text": "M",
        "price_sek": 450, "title": "Banarasi silk saree, worn once"})
    assert r.status_code == 201, r.text
    _ctx["listing_id"] = r.json()["id"]
    print(f"    listing {_ctx['listing_id']} live")

    # Buyer can see it while browsing, and it carries the seller's id (BUG-005)
    items = client.get("/v1/listings", headers=_ctx["buyer"]).json()["items"]
    mine = [i for i in items if i["id"] == _ctx["listing_id"]]
    assert mine and mine[0]["seller_id"] == _ctx["seller_id"], \
        "listing must carry its seller's id"
    print("    buyer browse shows the new listing with seller_id")


def test_05_buyer_reserves_and_reports_payment():
    print("\n=== Act 5: buyer reserves and reports Swish payment")
    assert _ctx.get("listing_id"), "run Act 4 first"
    r = client.post(f"/v1/listings/{_ctx['listing_id']}/reserve",
                    headers=_ctx["buyer"])
    assert r.status_code == 201, r.text
    _ctx["order_id"] = r.json()["id"]
    dims = r.json()["dimensions"]
    assert dims["payment"] == "payment_unreported"
    snap = r.json()["snapshot"]
    print(f"    order {_ctx['order_id']}; pay {snap['amount_sek']} SEK to {snap['recipient']} (direct Swish)")

    r = _cmd(_ctx["buyer"], _ctx["order_id"], "report_payment")
    assert r.status_code == 200
    assert r.json()["dimensions"]["payment"] == "payment_reported"
    print("    buyer reported payment -> payment_reported")


def test_06_seller_confirms_and_dispatches():
    print("\n=== Act 6: seller confirms payment and dispatches")
    assert _ctx.get("order_id"), "run Act 5 first"
    # Dispatch before confirmation is rejected (guard)
    r = _cmd(_ctx["seller"], _ctx["order_id"], "dispatch")
    assert r.status_code == 422
    print("    dispatch before confirm -> 422 (guard holds)")

    r = _cmd(_ctx["seller"], _ctx["order_id"], "confirm_payment",
             context={"swish_verified": True})
    assert r.json()["dimensions"]["payment"] == "payment_seller_confirmed"
    print("    seller confirmed Swish receipt -> payment_seller_confirmed")

    r = _cmd(_ctx["seller"], _ctx["order_id"], "dispatch")
    assert r.json()["dimensions"]["fulfilment"] == "dispatched"
    print("    dispatched -> fulfilment=dispatched")


def test_07_buyer_receives_and_reviews():
    print("\n=== Act 7: buyer confirms receipt and reviews")
    assert _ctx.get("order_id"), "run Act 6 first"
    r = _cmd(_ctx["buyer"], _ctx["order_id"], "confirm_receipt")
    assert r.json()["dimensions"]["fulfilment"] == "receipt_confirmed"
    r = client.post(f"/v1/orders/{_ctx['order_id']}/review",
                    headers=_ctx["buyer"],
                    json={"rating": 5, "text": "Beautiful saree, smooth handover."})
    assert r.status_code == 201 and r.json()["ok"]
    print("    receipt confirmed; 5-star review left")


def test_08_role_permissions_enforced():
    print("\n=== Act 8: roles and permissions hold under test")
    buyer, seller = _ctx["buyer"], _ctx["seller"]
    order_id = _ctx["order_id"]

    # Buyer cannot run seller/admin commands on the order
    r = _cmd(buyer, order_id, "dispatch")
    assert r.status_code in (403, 422), f"buyer dispatch -> {r.status_code}"
    print(f"    buyer tries dispatch -> {r.status_code} (denied)")

    # Seller cannot touch the admin queue
    r = client.get("/v1/admin/seller-queue", headers=seller)
    assert r.status_code == 403
    print("    seller reads admin queue -> 403 (denied)")

    # A stranger cannot read someone else's order (NFR-S3, DB-TC-129)
    stranger = _otp_login("stranger@example.se")
    r = client.get(f"/v1/orders/{order_id}", headers=stranger)
    assert r.status_code == 403
    print("    stranger reads the order -> 403 (denied)")

    # The sold listing cannot be double-reserved (FR-L3 atomic allocation)
    r = client.post(f"/v1/listings/{_ctx['listing_id']}/reserve", headers=stranger)
    assert r.status_code in (403, 409), f"double reserve -> {r.status_code}"
    print(f"    stranger reserves sold listing -> {r.status_code} (denied)")
