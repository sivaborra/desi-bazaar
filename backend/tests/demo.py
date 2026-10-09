"""
Scripted walkthrough of the vertical slice. Run:
    .venv/bin/python demo.py   (from this directory)
"""
import sys
import os
import uuid
import hashlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient
from app import app, engine, orders, otp_store
import json as _json

client = TestClient(app)
ROHAN = {"X-Principal": "buyer-rohan"}
SARA = {"X-Principal": "buyer-sara"}
ANAYA = {"X-Principal": "seller-anaya"}
ADMIN = {"X-Principal": "admin-1"}


def show(step, resp):
    body = resp.json() if resp.status_code < 500 else resp.text
    print(f"\n=== {step} -> {resp.status_code}")
    if isinstance(body, dict):
        for k in ("dimensions", "replayed", "items", "ok", "review"):
            if k in body:
                print(f"    {k}: {body[k]}")
    return body


# 1. browse: pending seller's listing is hidden
body = show("1. browse listings (rohan)", client.get("/v1/listings", headers=ROHAN))
assert len(body["items"]) == 2, "pending seller's sherwani must be hidden"

# 2. atomic allocation: kurti has 1 unit; two buyers race
r1 = client.post("/v1/listings/listing-kurti/reserve", headers=ROHAN)
r2 = client.post("/v1/listings/listing-kurti/reserve", headers=SARA)
print(f"\n=== 2. allocation race -> {r1.status_code} / {r2.status_code}")
assert r1.status_code == 201 and r2.status_code == 409, "exactly one winner"
kurti_order = r1.json()["id"]

# 3. reserve saree for the main flow
body = show("3. reserve saree (rohan)", client.post("/v1/listings/listing-saree/reserve", headers=ROHAN))
order_id = body["id"]
assert body["dimensions"] == {"payment": "payment_unreported", "fulfilment": "stock_reserved",
                              "cancel_refund": "no_cancel", "dispute": "dispute_none",
                              "return": "return_none"}
snap = body["snapshot"]
print(f"    checkout: pay {snap['amount_sek']} SEK to {snap['recipient']} (direct Swish, no platform hold)")

# 4. buyer reports payment
op_pay = uuid.uuid4().hex
body = show("4. buyer reports payment", client.post("/v1/commands", headers=ROHAN, json={
    "operation_id": op_pay, "order_id": order_id, "operation": "report_payment"}))
assert body["dimensions"]["payment"] == "payment_reported" and not body["replayed"]

# 5. guard: dispatch before seller confirmation is rejected
r = client.post("/v1/commands", headers=ANAYA, json={
    "operation_id": uuid.uuid4().hex, "order_id": order_id, "operation": "dispatch"})
print(f"\n=== 5. dispatch before payment confirm -> {r.status_code} ({r.json()['detail'][:60]}...)")
assert r.status_code == 422

# 6. seller confirms actual Swish receipt
op_conf = uuid.uuid4().hex
body = show("6. seller confirms payment", client.post("/v1/commands", headers=ANAYA, json={
    "operation_id": op_conf, "order_id": order_id, "operation": "confirm_payment",
    "context": {"swish_verified": True}}))
assert body["dimensions"]["payment"] == "payment_seller_confirmed"

# 7. replay of the payment report: recorded result, no duplicate
body = show("7. replay payment report (same operation_id)", client.post("/v1/commands", headers=ROHAN, json={
    "operation_id": op_pay, "order_id": order_id, "operation": "report_payment"}))
assert body["replayed"] is True

# 8. conflicting reuse of an operation_id is rejected
r = client.post("/v1/commands", headers=ROHAN, json={
    "operation_id": op_pay, "order_id": order_id, "operation": "report_payment",
    "payload": {"note": "different"}})
print(f"\n=== 8. same operation_id, different payload -> {r.status_code}")
assert r.status_code == 409

# 9. stale version rejected
r = client.post("/v1/commands", headers=ANAYA, json={
    "operation_id": uuid.uuid4().hex, "order_id": order_id, "operation": "dispatch",
    "expected_order_version": 1})
print(f"\n=== 9. stale expected_order_version -> {r.status_code}")
assert r.status_code == 409

# 10. dispatch now works
op_disp = uuid.uuid4().hex
body = show("10. seller dispatches", client.post("/v1/commands", headers=ANAYA, json={
    "operation_id": op_disp, "order_id": order_id, "operation": "dispatch"}))
assert body["dimensions"]["fulfilment"] == "dispatched"

# 11. buyer confirms receipt + reviews
body = show("11. buyer confirms receipt", client.post("/v1/commands", headers=ROHAN, json={
    "operation_id": uuid.uuid4().hex, "order_id": order_id, "operation": "confirm_receipt"}))
assert body["dimensions"]["fulfilment"] == "receipt_confirmed"
body = show("12. buyer reviews", client.post(f"/v1/orders/{order_id}/review", headers=ROHAN,
                                             json={"rating": 5, "text": "Beautiful saree, fast handover."}))
assert body["ok"]

# 13. dispute flow on the kurti order (system ops via engine, as production would)
kmeta = orders[kurti_order]
ko = kmeta["order"]
engine.execute(ko, kurti_order, "buyer", "buyer-rohan", "report_payment", operation_id=uuid.uuid4().hex)
engine.execute(ko, kurti_order, "seller", "seller-anaya", "confirm_payment",
               context={"swish_verified": True}, operation_id=uuid.uuid4().hex)
engine.execute(ko, kurti_order, "seller", "seller-anaya", "dispatch", operation_id=uuid.uuid4().hex)
body = show("13. buyer opens dispute (not received)", client.post("/v1/commands", headers=ROHAN, json={
    "operation_id": uuid.uuid4().hex, "order_id": kurti_order, "operation": "open_dispute",
    "payload": {"reason": "not_received"}}))
assert body["dimensions"]["dispute"] == "dispute_open"
body = show("14. admin decides", client.post("/v1/commands", headers=ADMIN, json={
    "operation_id": uuid.uuid4().hex, "order_id": kurti_order, "operation": "decide_dispute"}))
assert body["dimensions"]["dispute"] == "dispute_decided"
engine.execute(ko, kurti_order, "system", "system", "remedy_validated",
               context={"remedy": "remedy_acknowledged"}, operation_id=uuid.uuid4().hex)
print(f"\n=== 15. remedy validated -> dispute = {ko.dispute}")
assert ko.dispute == "dispute_resolved"

# 16. cross-principal object access denied (NFR-S3)
r = client.get(f"/v1/orders/{order_id}", headers=SARA)
print(f"\n=== 16. sara reads rohan's order -> {r.status_code}")
assert r.status_code == 403

# 17. OTP registration: request + verify -> buyer registered (FR-B1, DB-TC-151)
r = client.post("/v1/auth/otp/request", json={"phone": "+46700000111"})
assert r.status_code == 200
code = otp_store["+46700000111"]["code"]
r = client.post("/v1/auth/otp/verify", json={"phone": "+46700000111", "code": code})
body = r.json()
print(f"\n=== 17. OTP register -> {r.status_code} (user {body['user_id']})")
assert r.status_code == 200 and body["otp_verified"] is True
NEWBUYER = {"X-Principal": body["user_id"]}

# 18. OTP rate limit: 6 rapid requests -> 6th is 429 (NFR-S1, DB-TC-126)
spam = [client.post("/v1/auth/otp/request", json={"phone": "+46700000222"}).status_code
        for _ in range(6)]
print(f"\n=== 18. OTP rate limit -> {spam}")
assert spam == [200] * 5 + [429], "max 5 per 10 min, then 429"

# 19. seller application: incomplete -> 422 (no re-apply consumed); complete -> 201 pending
r = client.post("/v1/sellers/applications", json={"name": "Meera Iyer"})
print(f"\n=== 19a. incomplete application -> {r.status_code} (missing {r.json()['detail']})")
assert r.status_code == 422
r = client.post("/v1/sellers/applications", json={
    "name": "Meera Iyer", "phone": "+46700000333", "id_document_ref": "ref-idoc-001",
    "categories": ["saree"], "profile": "Selling pre-loved sarees.",
    "trader": True, "trader_basis": "org 559999-1234", "swish_recipient": "+46700000333"})
body = r.json()
print(f"\n=== 19b. complete application -> {r.status_code} (status {body['status']})")
assert r.status_code == 201 and body["status"] == "pending"
MEERA = {"X-Principal": body["seller_id"]}
meera_id = body["seller_id"]

# 20. pending seller cannot create listings (FR-S2, DB-TC-004)
r = client.post("/v1/listings", headers=MEERA, json={
    "category": "kurti", "condition": "new", "size_text": "S", "price_sek": 300})
print(f"\n=== 20. pending seller creates listing -> {r.status_code}")
assert r.status_code == 403

# 21. admin queue shows the application incl. trader basis (DB-TC-003)
body = client.get("/v1/admin/seller-queue", headers=ADMIN).json()
print(f"\n=== 21. admin seller queue -> {len(body['applications'])} pending")
assert any(a["trader_basis"] == "org 559999-1234" for a in body["applications"])
# non-admin cannot see the queue (DB-TC-131)
assert client.get("/v1/admin/seller-queue", headers=ROHAN).status_code == 403

# 22. admin approves via checklist: reviewer identity + timestamp recorded (DB-TC-005)
r = client.post(f"/v1/admin/sellers/{meera_id}/decision", headers=ADMIN, json={
    "decision": "approve", "checklist_version": "v1",
    "evidence_reviewed": ["id_document"], "checks": ["identity", "trader_basis"],
    "reason": "all checks passed"})
d = r.json()
print(f"\n=== 22. admin approves -> {r.status_code} (reviewer {d['reviewer_id']})")
assert r.status_code == 200 and d["reviewer_id"] == "admin-1" and d["decided_at"]
prof = client.get(f"/v1/sellers/{meera_id}/profile").json()
print(f"    badge: {prof['badge']}")
assert prof["badge"]["scope"] == "ID verified" and prof["badge"]["date"]
assert "guarantee" not in _json.dumps(prof).lower(), "no guarantee wording (DB-TC-006)"

# 23. recipient change: needs fresh OTP; sets hold; blocks new orders (FR-S6, DB-TC-132)
r = client.patch("/v1/sellers/me/recipient", headers=MEERA,
                 json={"swish_recipient": "+46700000999"})
print(f"\n=== 23a. recipient change without fresh OTP -> {r.status_code}")
assert r.status_code == 403
client.post("/v1/auth/otp/request", json={"phone": "+46700000333"})
client.post("/v1/auth/otp/verify",
            json={"phone": "+46700000333", "code": otp_store["+46700000333"]["code"]})
r = client.patch("/v1/sellers/me/recipient", headers=MEERA,
                 json={"swish_recipient": "+46700000999"})
print(f"=== 23b. recipient change after fresh OTP -> {r.status_code} (hold={r.json()['recipient_hold']})")
assert r.status_code == 200 and r.json()["recipient_hold"] is True
r = client.post("/v1/listings", headers=MEERA, json={
    "category": "kurti", "condition": "new", "size_text": "S", "price_sek": 300})
meera_listing = r.json()["id"]
r = client.post(f"/v1/listings/{meera_listing}/reserve", headers=ROHAN)
print(f"=== 23c. reserve during recipient hold -> {r.status_code}")
assert r.status_code == 403, "new orders blocked until admin re-verifies"
r = client.post(f"/v1/admin/sellers/{meera_id}/recipient/verify", headers=ADMIN)
assert r.status_code == 200 and r.json()["recipient_hold"] is False
r = client.post(f"/v1/listings/{meera_listing}/reserve", headers=ROHAN)
print(f"=== 23d. reserve after admin re-verify -> {r.status_code}")
assert r.status_code == 201
assert r.json()["snapshot"]["recipient"] == "+46700000999", "new orders use the new recipient"

# 24. rejection + one re-application (FR-S5, DB-TC-176)
def _apply_vikram():
    return client.post("/v1/sellers/applications", json={
        "name": "Vikram Rao", "phone": "+46700000444", "id_document_ref": "ref-idoc-002",
        "categories": ["shirts"], "trader": False})
r = _apply_vikram()
vikram_id = r.json()["seller_id"]
r = client.post(f"/v1/admin/sellers/{vikram_id}/decision", headers=ADMIN, json={
    "decision": "reject", "checklist_version": "v1",
    "evidence_reviewed": ["id_document"], "checks": ["identity"],
    "reason": "ID document unreadable"})
print(f"\n=== 24a. admin rejects -> {r.status_code} (reason: {r.json()['reason']})")
assert r.status_code == 200 and r.json()["reason"] == "ID document unreadable"
r = _apply_vikram()
print(f"=== 24b. first re-apply -> {r.status_code}")
assert r.status_code == 201
vikram2 = r.json()["seller_id"]
client.post(f"/v1/admin/sellers/{vikram2}/decision", headers=ADMIN, json={
    "decision": "reject", "checklist_version": "v1",
    "evidence_reviewed": ["id_document"], "checks": ["identity"], "reason": "still unreadable"})
r = _apply_vikram()
print(f"=== 24c. second re-apply -> {r.status_code}")
assert r.status_code == 422, "one re-application only (FR-S5)"

# 25. public profile: fulfilment history split evidenced vs unconfirmed (DB-TC-147)
prof = client.get("/v1/sellers/seller-anaya/profile").json()
fh = prof["fulfilment_history"]
print(f"\n=== 25. anaya fulfilment history -> {fh}")
assert fh["evidenced"] >= 1 and "unconfirmed" in fh
assert prof["dispute_outcomes"]["resolved"] >= 1

# 26. media upload: signed URL -> bytes -> complete (DB-TC-184, SC-2)
jpeg = b"\xff\xd8\xff" + b"\x00" * 100
r = client.post("/v1/media/upload-url", headers=ANAYA, json={
    "purpose": "listing_image", "content_type": "image/jpeg",
    "content_length": len(jpeg)})
assert r.status_code == 201
mid = r.json()["media_id"]
assert r.json()["upload_url"] == f"/v1/media/{mid}/bytes"
print(f"\n=== 26. upload-url -> 201 ({mid})")
r = client.post("/v1/media/upload-url", headers=ANAYA, json={
    "purpose": "listing_image", "content_type": "video/mp4", "content_length": 100})
print(f"=== 26b. wrong content_type -> {r.status_code}")
assert r.status_code == 422
r = client.post("/v1/media/upload-url", headers=ANAYA, json={
    "purpose": "listing_image", "content_type": "image/jpeg",
    "content_length": 11 * 1024 * 1024})
print(f"=== 26c. oversize image -> {r.status_code}")
assert r.status_code == 422
r = client.put(f"/v1/media/{mid}/bytes", headers=ANAYA, content=jpeg)
assert r.status_code == 200 and r.json()["received_bytes"] == len(jpeg)
r = client.post(f"/v1/media/{mid}/complete", headers=ANAYA,
                json={"checksum": hashlib.sha256(jpeg).hexdigest()})
print(f"=== 26d. complete (valid jpeg) -> {r.json()}")
assert r.json()["status"] == "accepted"
fake_png = b"NOT-A-PNG" + b"\x00" * 100
r = client.post("/v1/media/upload-url", headers=ANAYA, json={
    "purpose": "listing_image", "content_type": "image/png",
    "content_length": len(fake_png)})
mid_bad = r.json()["media_id"]
client.put(f"/v1/media/{mid_bad}/bytes", headers=ANAYA, content=fake_png)
r = client.post(f"/v1/media/{mid_bad}/complete", headers=ANAYA,
                json={"checksum": hashlib.sha256(fake_png).hexdigest()})
print(f"=== 26e. bad magic bytes -> {r.json()}")
assert r.json()["status"] == "rejected"
r = client.get(f"/v1/media/{mid}")
assert r.status_code == 200 and r.content == jpeg
assert r.headers["content-type"] == "image/jpeg"
print(f"=== 26f. GET media serves bytes -> 200 ({r.headers['content-type']})")

# 27. listing with media: attached, listed, limits enforced (DB-TC-185)
r = client.post("/v1/listings", headers=ANAYA, json={
    "category": "dupatta", "condition": "new", "size_text": "2.5m",
    "price_sek": 350, "media_ids": [mid]})
assert r.status_code == 201
dupatta_id = r.json()["id"]
items = {i["id"]: i for i in client.get("/v1/listings", headers=ROHAN).json()["items"]}
m = items[dupatta_id]["media"]
print(f"\n=== 27. listing media -> {m}")
assert len(m) == 1 and m[0]["media_id"] == mid and m[0]["kind"] == "image"
nine = []
for _ in range(9):
    rr = client.post("/v1/media/upload-url", headers=ANAYA, json={
        "purpose": "listing_image", "content_type": "image/jpeg",
        "content_length": len(jpeg)})
    m2 = rr.json()["media_id"]
    client.put(f"/v1/media/{m2}/bytes", headers=ANAYA, content=jpeg)
    client.post(f"/v1/media/{m2}/complete", headers=ANAYA,
                json={"checksum": hashlib.sha256(jpeg).hexdigest()})
    nine.append(m2)
r = client.post("/v1/listings", headers=ANAYA, json={
    "category": "dupatta", "condition": "new", "size_text": "2.5m",
    "price_sek": 350, "media_ids": nine})
print(f"=== 27b. 9 images -> {r.status_code}")
assert r.status_code == 422
r = client.post("/v1/listings", headers=MEERA, json={
    "category": "kurti", "condition": "new", "size_text": "S",
    "price_sek": 300, "media_ids": [mid]})
print(f"=== 27c. another seller's media -> {r.status_code}")
assert r.status_code == 422

# 28. listing video (SC-2, DB-TC-186)
mp4 = b"\x00\x00\x00\x18ftyp" + b"\x00" * 100
vids = []
for _ in range(3):
    rr = client.post("/v1/media/upload-url", headers=ANAYA, json={
        "purpose": "listing_video", "content_type": "video/mp4",
        "content_length": len(mp4)})
    assert rr.status_code == 201
    v = rr.json()["media_id"]
    client.put(f"/v1/media/{v}/bytes", headers=ANAYA, content=mp4)
    cr = client.post(f"/v1/media/{v}/complete", headers=ANAYA,
                     json={"checksum": hashlib.sha256(mp4).hexdigest()})
    assert cr.json()["status"] == "accepted"
    vids.append(v)
r = client.post("/v1/media/upload-url", headers=ANAYA, json={
    "purpose": "listing_image", "content_type": "video/mp4", "content_length": 100})
print(f"\n=== 28a. video as image purpose -> {r.status_code}")
assert r.status_code == 422
r = client.post("/v1/listings", headers=ANAYA, json={
    "category": "lehenga", "condition": "new", "size_text": "M",
    "price_sek": 1500, "media_ids": vids[:2]})
print(f"=== 28b. listing with 2 videos -> {r.status_code}")
assert r.status_code == 201
r = client.post("/v1/listings", headers=ANAYA, json={
    "category": "lehenga", "condition": "new", "size_text": "M",
    "price_sek": 1500, "media_ids": vids})
print(f"=== 28c. listing with 3 videos -> {r.status_code}")
assert r.status_code == 422

# 29. ads promotion flow: create -> pay -> admin approve -> active (DB-TC-187, SC-1)
r = client.get("/v1/ads/config", headers=ANAYA)
cfg = r.json()
print(f"\n=== 29. ads config -> {cfg}")
assert cfg["currency"] == "SEK" and cfg["prices"] == {"1": 29, "3": 69, "7": 129}
r = client.post("/v1/ads/promotions", headers=ANAYA,
                json={"listing_id": dupatta_id, "days": 3})
p = r.json()
print(f"=== 29b. promotion created -> {p}")
assert r.status_code == 201 and p["state"] == "pending_payment" and p["amount_sek"] == 69
pid = p["promotion_id"]
r = client.post("/v1/ads/promotions", headers=ANAYA,
                json={"listing_id": dupatta_id, "days": 5})
print(f"=== 29c. invalid days -> {r.status_code}")
assert r.status_code == 422
r = client.post(f"/v1/ads/promotions/{pid}/pay", headers=MEERA)
print(f"=== 29d. non-owner pay -> {r.status_code}")
assert r.status_code == 403
r = client.post(f"/v1/ads/promotions/{pid}/pay", headers=ANAYA)
assert r.json()["state"] == "pending_review"
r = client.post(f"/v1/ads/promotions/{pid}/pay", headers=ANAYA)
print(f"=== 29e. double pay -> {r.status_code}")
assert r.status_code == 422
r = client.post(f"/v1/admin/ads/promotions/{pid}/decision", headers=ADMIN,
                json={"approve": True})
d = r.json()
print(f"=== 29f. admin approves -> {d}")
assert d["state"] == "active" and d["expires_at"]

# 30. sponsored ranking + slot; non-promoted never labelled (DB-TC-188/189)
items = client.get("/v1/listings", headers=ROHAN).json()["items"]
promoted = [i for i in items if i["promoted"]]
plain = [i for i in items if not i["promoted"]]
print(f"\n=== 30. listings: {len(promoted)} promoted, {len(plain)} plain")
assert promoted, "seed + new promotions must rank"
assert all(i["label"] == "Sponsored" for i in promoted)
assert all(i["label"] is None for i in plain), "DB-TC-189: never label non-promoted"
first_plain = next((n for n, i in enumerate(items) if not i["promoted"]), len(items))
assert all(n < first_plain for n, i in enumerate(items) if i["promoted"]), \
    "promoted rank first"
slot = client.get("/v1/ads/slot", headers=ROHAN, params={"placement": "feed"}).json()
print(f"=== 30b. ad slot -> {slot}")
assert slot["type"] == "promotion" and slot["label"] == "Sponsored"

print("\nALL DEMO CHECKS PASSED")
