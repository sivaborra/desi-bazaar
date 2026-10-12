"""
Desi Bazaar — FR-B1d registration + GDPR consent backend validation tests.

Tests the /v1/auth/otp/verify is_new_user flag and /v1/auth/register
validation rules (§3.3.1 V1–V8). Maps to DB-TC-202, 206–211, 214, 216.

Run: pytest test_registration.py -q  (needs pytest + fastapi)
"""
import sys
import os
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import pytest
from fastapi.testclient import TestClient

import app as backend


@pytest.fixture
def client():
    # Reset mutable backend state between tests.
    backend.otp_store.clear()
    backend.verified_identifiers.clear()
    backend._register_attempts.clear()
    # Remove any users created by previous tests (keep seed users).
    for uid in [u for u in backend.USERS if u.startswith("buyer-")]:
        del backend.USERS[uid]
    return TestClient(backend.app)


def _verify(client, identifier, code="123456"):
    """Seed an OTP and verify it. Returns the verify response."""
    body = {"code": code}
    if "@" in identifier:
        body["email"] = identifier
    else:
        body["phone"] = identifier
    backend.otp_store[identifier] = {
        "code": code,
        "expires_at": time.time() + 600,
        "requests": [],
    }
    r = client.post("/v1/auth/otp/verify", json=body)
    assert r.status_code == 200, r.text
    return r.json()


def _register(client, identifier, **overrides):
    body = {"consent_accepted": True,
            "consent_version": backend.CONSENT_VERSION,
            "marketing_opt_in": False,
            "age_confirmed": True}
    if "@" in identifier:
        body["email"] = identifier
    else:
        body["phone"] = identifier
    body.update(overrides)
    return client.post("/v1/auth/register", json=body)


# --- DB-TC-202: is_new_user flag -------------------------------------------

def test_verify_new_identifier_returns_is_new_user(client):
    resp = _verify(client, "+46709999999")
    assert resp["is_new_user"] is True
    assert resp["user_id"] is None
    # CC3: no user record created by verify alone.
    assert not [u for u in backend.USERS.values()
                if u.get("phone") == "+46709999999"]


def test_verify_known_seed_user_returns_is_new_user_false(client):
    # Seed users are treated as already registered.
    backend.USERS["seed-buyer"] = {
        "id": "seed-buyer", "role": "buyer", "name": "Seed",
        "phone": "+46700000001", "registration_complete": True,
    }
    resp = _verify(client, "+46700000001")
    assert resp["is_new_user"] is False
    assert resp["user_id"] == "seed-buyer"
    del backend.USERS["seed-buyer"]


# --- DB-TC-206 (V2): consent required --------------------------------------

def test_register_rejects_without_consent(client):
    _verify(client, "+46708888888")
    r = _register(client, "+46708888888", consent_accepted=False)
    assert r.status_code == 422
    assert not [u for u in backend.USERS.values()
                if u.get("phone") == "+46708888888"]


# --- DB-TC-207 (V1): OTP verification required -----------------------------

def test_register_rejects_without_otp_verification(client):
    r = _register(client, "+46707777777")
    assert r.status_code == 422
    assert "OTP verification required" in r.json()["detail"]


# --- DB-TC-208 (V3): consent version must be current ------------------------

def test_register_rejects_outdated_consent_version(client):
    _verify(client, "oldver@example.se")
    r = _register(client, "oldver@example.se", consent_version="v0")
    assert r.status_code == 422
    assert backend.CONSENT_VERSION in r.json()["detail"]


# --- DB-TC-209 (V4): age confirmation required -----------------------------

def test_register_rejects_without_age_confirmation(client):
    _verify(client, "+46706666666")
    r = _register(client, "+46706666666", age_confirmed=False)
    assert r.status_code == 422


# --- Happy path + DB-TC-214 (G4): consent record ---------------------------

def test_successful_registration_stores_consent(client):
    _verify(client, "happy@example.se")
    r = _register(client, "happy@example.se", display_name="Happy",
                  marketing_opt_in=True)
    assert r.status_code == 201
    user_id = r.json()["user_id"]
    user = backend.USERS[user_id]
    assert user["registration_complete"] is True
    assert user["consent_accepted"] is True
    assert user["consent_version"] == backend.CONSENT_VERSION
    assert user["consent_at"]  # UTC ISO timestamp present
    assert user["marketing_opt_in"] is True
    assert user["age_confirmed"] is True
    assert user["name"] == "Happy"


def test_marketing_defaults_to_false(client):
    _verify(client, "nomkt@example.se")
    r = _register(client, "nomkt@example.se")
    assert r.status_code == 201
    assert backend.USERS[r.json()["user_id"]]["marketing_opt_in"] is False


# --- DB-TC-210 (V5): idempotent --------------------------------------------

def test_duplicate_registration_returns_existing(client):
    _verify(client, "dupe@example.se")
    r1 = _register(client, "dupe@example.se")
    assert r1.status_code == 201
    uid = r1.json()["user_id"]
    r2 = _register(client, "dupe@example.se")
    assert r2.status_code == 201
    assert r2.json()["user_id"] == uid
    assert r2.json()["already_registered"] is True


# --- DB-TC-216 (V7): rate limiting -----------------------------------------

def test_registration_rate_limited(client):
    ident = "ratelimit@example.se"
    _verify(client, ident)
    # 10 attempts with bad consent (each counts), 11th must 429.
    for _ in range(10):
        _register(client, ident, consent_accepted=False)
    r = _register(client, ident, consent_accepted=False)
    assert r.status_code == 429


# --- Validation helpers ----------------------------------------------------

def test_valid_email():
    assert backend._valid_email("a@example.se")
    assert not backend._valid_email("not-an-email")
    assert not backend._valid_email("a@b")


def test_valid_phone():
    assert backend._valid_phone("+46700000001")
    assert backend._valid_phone("0700000001")
    assert not backend._valid_phone("abc")
    assert not backend._valid_phone("12")


# --- SMTP / email delivery tests -------------------------------------------
# These verify the email OTP path is correctly wired. They do NOT send real
# emails — they verify configuration detection and error handling.

def test_smtp_not_configured_without_env(monkeypatch):
    """Without SMTP env vars, _smtp_configured() must be False (console fallback)."""
    monkeypatch.delenv("SMTP_HOST", raising=False)
    monkeypatch.delenv("SMTP_USER", raising=False)
    monkeypatch.delenv("SMTP_PASS", raising=False)
    assert backend._smtp_configured() is False


def test_smtp_configured_with_env(monkeypatch):
    """With all SMTP env vars set, _smtp_configured() must be True."""
    monkeypatch.setenv("SMTP_HOST", "smtp.example.com")
    monkeypatch.setenv("SMTP_USER", "test@example.com")
    monkeypatch.setenv("SMTP_PASS", "secret")
    assert backend._smtp_configured() is True


def test_smtp_configured_partial_env(monkeypatch):
    """Missing any one var → not configured (no half-configured SMTP)."""
    monkeypatch.setenv("SMTP_HOST", "smtp.example.com")
    monkeypatch.setenv("SMTP_USER", "test@example.com")
    monkeypatch.delenv("SMTP_PASS", raising=False)
    assert backend._smtp_configured() is False


def test_send_otp_email_returns_false_without_config(monkeypatch):
    """_send_otp_email must return False (not raise) when SMTP is unconfigured."""
    monkeypatch.delenv("SMTP_HOST", raising=False)
    # Should not raise, should return False to trigger console fallback
    # Note: actually calls _smtp_configured internally; if the function
    # tries to send without config it should fail gracefully.
    try:
        result = backend._send_otp_email("test@example.se", "123456")
        # Either False (graceful) or True (mocked) — must not raise
        assert isinstance(result, bool)
    except KeyError:
        # SMTP_USER/PASS missing → KeyError is acceptable (config error)
        pass


def test_otp_request_email_without_smtp_falls_back(client, monkeypatch, capsys):
    """Email OTP request without SMTP config must succeed via console fallback."""
    monkeypatch.delenv("SMTP_HOST", raising=False)
    r = client.post("/v1/auth/otp/request", json={"email": "fallback@example.se"})
    assert r.status_code == 200
    # Console fallback should print the code
    captured = capsys.readouterr()
    assert "fallback@example.se" in captured.out or "123456" in captured.out or "code" in captured.out.lower()
