"""
Desi Bazaar — executable §11 transition tests (for review, 2026-10-08).

Tests the canonical engine in ../engine.py: every §11 row, guard rejections,
the 9 invariants, and the §9 operation-identity contract.

Run:  pytest test_transitions.py -q   (needs pytest)
"""
import sys, os, uuid
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import pytest
from engine import (
    Engine, Order, GuardFailed, BadActor, VersionConflict,
    OperationConflict, Forbidden, request_fingerprint,
)
# ---------------------------------------------------------------- tests ---

@pytest.fixture
def eng():
    return Engine()


def oid():
    return "order-1"


# ---- payment dimension: every row ----

def test_payment_report(eng):
    o = Order()
    eng.execute(o, oid(), "buyer", "b1", "report_payment")
    assert o.payment == "payment_reported"


def test_payment_late_report(eng):
    o = Order()
    eng.execute(o, oid(), "system", "sys", "late_report", context={"reservation_expired": True})
    assert o.payment == "payment_unresolved"


def test_payment_seller_confirms(eng):
    o = Order(payment="payment_reported")
    eng.execute(o, oid(), "seller", "s1", "confirm_payment", context={"swish_verified": True})
    assert o.payment == "payment_seller_confirmed"


def test_payment_report_to_unresolved_on_silence(eng):
    o = Order(payment="payment_reported")
    eng.execute(o, oid(), "system", "sys", "seller_silent_24h", context={"hours_since_report": 30})
    assert o.payment == "payment_unresolved"


def test_payment_unresolved_to_confirmed(eng):
    o = Order(payment="payment_unresolved")
    eng.execute(o, oid(), "seller", "s1", "resolve_verified",
                context={"allocation_intact": True, "swish_verified": True})
    assert o.payment == "payment_seller_confirmed"


def test_payment_unresolved_to_refund_on_allocation_loss(eng):
    o = Order(payment="payment_unresolved")
    eng.execute(o, oid(), "seller", "s1", "allocation_lost_refund",
                context={"allocation_intact": False, "swish_verified": True})
    assert o.cancel == "refund_requested"          # no dispatch possible (invariant 9)
    assert o.payment == "payment_unresolved"       # payment dim untouched


def test_payment_established_unpaid_releases_stock_atomically(eng):
    o = Order(payment="payment_unresolved", fulfilment="stock_reserved")
    eng.execute(o, oid(), "admin", "a1", "establish_unpaid",
                context={"non_payment_established": True})
    assert o.payment == "payment_established_unpaid"
    assert o.fulfilment == "stock_released"        # IC-1: atomic cross-dimension


def test_payment_confirm_requires_swish_evidence(eng):
    o = Order(payment="payment_reported")
    with pytest.raises(GuardFailed):
        eng.execute(o, oid(), "seller", "s1", "confirm_payment", context={"swish_verified": False})
    assert o.payment == "payment_reported"


# ---- fulfilment dimension ----

def test_dispatch_requires_confirmed_payment(eng):   # invariant 1
    o = Order(payment="payment_reported", fulfilment="stock_reserved")
    with pytest.raises(GuardFailed):
        eng.execute(o, oid(), "seller", "s1", "dispatch")
    assert o.fulfilment == "stock_reserved"


def test_dispatch_after_confirmation(eng):
    o = Order(payment="payment_seller_confirmed", fulfilment="stock_reserved")
    eng.execute(o, oid(), "seller", "s1", "dispatch")
    assert o.fulfilment == "dispatched"


def test_unpaid_expiry_releases_stock(eng):
    o = Order(payment="payment_unreported", fulfilment="stock_reserved")
    eng.execute(o, oid(), "system", "sys", "reservation_expired",
                context={"reservation_expired": True})
    assert o.fulfilment == "stock_released"


def test_reported_payment_blocks_expiry_release(eng):
    # paid-but-unconfirmed is never treated as unpaid (spec §11)
    o = Order(payment="payment_reported", fulfilment="stock_reserved")
    with pytest.raises(GuardFailed):
        eng.execute(o, oid(), "system", "sys", "reservation_expired",
                    context={"reservation_expired": True})
    assert o.fulfilment == "stock_reserved"


@pytest.mark.parametrize("event,ctx,expected", [
    ("confirm_receipt", {}, "receipt_confirmed"),
    ("carrier_scan", {"carrier_evidence": True}, "delivery_evidenced"),
    ("evidence_window_lapsed", {"window_lapsed": True}, "delivery_unconfirmed"),
])
def test_dispatched_outcomes(eng, event, ctx, expected):
    o = Order(payment="payment_seller_confirmed", fulfilment="dispatched")
    actor = "buyer" if event == "confirm_receipt" else "system"
    eng.execute(o, oid(), actor, "x", event, context=ctx)
    assert o.fulfilment == expected


def test_late_carrier_evidence_after_unconfirmed(eng):
    o = Order(fulfilment="delivery_unconfirmed")
    eng.execute(o, oid(), "system", "sys", "late_carrier_scan",
                context={"carrier_evidence": True})
    assert o.fulfilment == "delivery_evidenced"


def test_late_buyer_confirmation(eng):
    o = Order(fulfilment="delivery_unconfirmed")
    eng.execute(o, oid(), "buyer", "b1", "confirm_receipt")
    assert o.fulfilment == "receipt_confirmed"


# ---- cancellation / refund ----

def test_cancel_unpaid_releases_stock(eng):
    o = Order(payment="payment_unreported", fulfilment="stock_reserved")
    eng.execute(o, oid(), "buyer", "b1", "request_cancellation")
    eng.execute(o, oid(), "system", "sys", "process_cancellation")
    assert o.cancel == "cancelled_unpaid"
    assert o.fulfilment == "stock_released"


def test_cancel_paid_opens_refund(eng):
    o = Order(payment="payment_seller_confirmed")
    eng.execute(o, oid(), "buyer", "b1", "request_cancellation")
    eng.execute(o, oid(), "system", "sys", "process_cancellation")
    assert o.cancel == "refund_requested"


def test_refund_flow_buyer_only_ack(eng):            # invariant 8
    o = Order(cancel="refund_requested")
    eng.execute(o, oid(), "seller", "s1", "report_refund")
    assert o.cancel == "refund_reported"
    with pytest.raises((BadActor, GuardFailed)):
        eng.execute(o, oid(), "admin", "a1", "admin_acknowledge_refund")
    assert o.cancel == "refund_reported"
    eng.execute(o, oid(), "buyer", "b1", "acknowledge_refund")
    assert o.cancel == "refund_acknowledged"


def test_refund_contest_then_escalate(eng):
    o = Order(cancel="refund_reported")
    eng.execute(o, oid(), "buyer", "b1", "contest_refund")
    assert o.cancel == "refund_contested"
    eng.execute(o, oid(), "admin", "a1", "escalate_to_dispute")
    assert o.dispute == "dispute_open"               # IC-1 atomic


def test_wrong_actor_cannot_report_refund(eng):
    o = Order(cancel="refund_requested")
    with pytest.raises(BadActor):
        eng.execute(o, oid(), "buyer", "b1", "report_refund")


# ---- return dimension (IC-2a) ----

def test_statutory_withdrawal_needs_no_authorisation(eng):
    o = Order(fulfilment="dispatched", ret="return_none", return_basis="statutory_withdrawal")
    eng.execute(o, oid(), "buyer", "b1", "request_return")
    eng.execute(o, oid(), "buyer", "b1", "ship_return")   # no authorise_return step
    assert o.ret == "goods_sent_back"


def test_voluntary_return_needs_authorisation(eng):
    o = Order(ret="return_none", return_basis="voluntary_policy")
    eng.execute(o, oid(), "buyer", "b1", "request_return")
    with pytest.raises(GuardFailed):
        eng.execute(o, oid(), "buyer", "b1", "ship_return")
    eng.execute(o, oid(), "seller", "s1", "authorise_return")
    eng.execute(o, oid(), "buyer", "b1", "ship_return")
    assert o.ret == "goods_sent_back"


def test_defective_goods_ship_without_authorisation(eng):
    o = Order(ret="return_none", return_basis="defective_goods")
    eng.execute(o, oid(), "buyer", "b1", "request_return")
    eng.execute(o, oid(), "buyer", "b1", "ship_return")
    assert o.ret == "goods_sent_back"


def test_shipping_evidence_opens_refund(eng):
    o = Order(ret="goods_sent_back", return_basis="statutory_withdrawal")
    eng.execute(o, oid(), "buyer", "b1", "shipping_evidence_refund",
                context={"shipping_evidence": True})
    assert o.cancel == "refund_requested"


def test_return_received_opens_refund(eng):
    o = Order(ret="goods_sent_back")
    eng.execute(o, oid(), "seller", "s1", "confirm_return_receipt")
    assert o.ret == "return_received"
    eng.execute(o, oid(), "system", "sys", "return_received_refund")
    assert o.cancel == "refund_requested"


# ---- dispute dimension ----

def test_dispute_full_flow(eng):
    o = Order()
    eng.execute(o, oid(), "buyer", "b1", "open_dispute")
    eng.execute(o, oid(), "admin", "a1", "decide_dispute")
    eng.execute(o, oid(), "system", "sys", "remedy_validated",
                context={"remedy": "remedy_acknowledged"})
    assert o.dispute == "dispute_resolved"


def test_dispute_closed_unconfirmed_on_weak_evidence(eng):
    o = Order(dispute="dispute_decided")
    eng.execute(o, oid(), "admin", "a1", "close_unconfirmed")
    assert o.dispute == "dispute_closed_unconfirmed"


def test_dispute_non_compliant(eng):
    o = Order(dispute="dispute_decided")
    eng.execute(o, oid(), "admin", "a1", "record_non_compliance",
                context={"deadline_ignored": True})
    assert o.dispute == "dispute_non_compliant"


@pytest.mark.parametrize("closed", ["dispute_closed_unconfirmed", "dispute_resolved",
                                    "dispute_non_compliant"])
def test_new_evidence_reopens(eng, closed):
    o = Order(dispute=closed)
    eng.execute(o, oid(), "system", "sys", "new_evidence", context={"new_evidence": True})
    assert o.dispute == "dispute_open"


def test_resolved_requires_valid_remedy(eng):
    o = Order(dispute="dispute_decided")
    with pytest.raises(GuardFailed):
        eng.execute(o, oid(), "system", "sys", "remedy_validated",
                    context={"remedy": "seller_said_so"})


# ---- §9 command contract ----

# ---- §9 operation identity (required tests 1–5) ----

def test_replay_same_id_same_payload_returns_original(eng):
    o = Order()
    op = uuid.uuid4().hex
    r1 = eng.execute(o, oid(), "buyer", "b1", "report_payment", operation_id=op)
    v1 = o.version
    r2 = eng.execute(o, oid(), "buyer", "b1", "report_payment", operation_id=op)
    assert r1["operation_id"] == r2["operation_id"] == op
    assert o.version == v1                       # no re-execution
    assert len([e for e in eng.outbox if e[1] == "report_payment"]) == 1
    assert len(eng.audit) == 1


def test_same_id_different_payload_is_conflict(eng):
    o = Order()
    op = uuid.uuid4().hex
    eng.execute(o, oid(), "buyer", "b1", "report_payment",
                payload={"note": "a"}, operation_id=op)
    with pytest.raises(OperationConflict):
        eng.execute(o, oid(), "buyer", "b1", "report_payment",
                    payload={"note": "b"}, operation_id=op)
    assert o.version == 2                        # committed once; conflict mutated nothing
    assert len(eng.audit) == 1


def test_different_ids_identical_payloads_both_commit(eng):
    # two separate 300 SEK refund reports against the same claim
    o1, o2 = Order(), Order()
    r1 = eng.execute(o1, "order-1", "buyer", "b1", "report_payment",
                     payload={}, operation_id=uuid.uuid4().hex)
    r2 = eng.execute(o2, "order-2", "buyer", "b1", "report_payment",
                     payload={}, operation_id=uuid.uuid4().hex)
    assert r1["operation_id"] != r2["operation_id"]
    assert o1.payment == o2.payment == "payment_reported"   # no false dedup
    assert len(eng.audit) == 2


def test_concurrent_retries_commit_once(eng):
    o = Order()
    op = uuid.uuid4().hex
    # two racing retries of the same logical operation
    r1 = eng.execute(o, oid(), "buyer", "b1", "report_payment", operation_id=op)
    r2 = eng.execute(o, oid(), "buyer", "b1", "report_payment", operation_id=op)
    assert r1["after"] == r2["after"]
    assert o.version == 2                        # exactly one commit
    assert len(eng.outbox) == 1


def test_other_principal_replay_denied(eng):
    o = Order()
    op = uuid.uuid4().hex
    eng.execute(o, oid(), "buyer", "b1", "report_payment", operation_id=op)
    with pytest.raises(Forbidden):
        eng.execute(o, oid(), "buyer", "b2", "report_payment", operation_id=op)
    assert len(eng.audit) == 1                   # nothing new committed


def test_replay_ignores_stale_expected_version(eng):
    o = Order()
    op = uuid.uuid4().hex
    eng.execute(o, oid(), "buyer", "b1", "report_payment", operation_id=op)
    # response lost; client retries with the now-stale version it sent
    r = eng.execute(o, oid(), "buyer", "b1", "report_payment",
                    expected_version=1, operation_id=op)
    assert r["after"][0] == "payment_reported"
    assert o.version == 2


def test_version_conflict_rejects(eng):
    o = Order()
    with pytest.raises(VersionConflict):
        eng.execute(o, oid(), "buyer", "b1", "report_payment", expected_version=99)
    assert o.payment == "payment_unreported"


def test_outbox_queued_after_commit(eng):
    o = Order()
    eng.execute(o, oid(), "buyer", "b1", "report_payment")
    assert eng.outbox == [(oid(), "report_payment")]
    assert eng.audit[0]["before"][0] == "payment_unreported"
    assert eng.audit[0]["after"][0] == "payment_reported"


def test_unknown_transition_rejected(eng):
    o = Order()  # payment_unreported: buyer cannot confirm payment
    with pytest.raises((BadActor, GuardFailed)):
        eng.execute(o, oid(), "buyer", "b1", "confirm_payment",
                    context={"swish_verified": True})
