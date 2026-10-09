-- Migration 003: orders (five dimensions), refund ledger, returns, disputes, reviews
BEGIN;

CREATE TABLE orders (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id       UUID NOT NULL REFERENCES users(id),
  seller_id      UUID NOT NULL REFERENCES sellers(user_id),
  unit_id        UUID NOT NULL REFERENCES listing_units(id),
  snapshot_id    UUID NOT NULL REFERENCES listing_snapshots(id),
  payment        payment_state NOT NULL DEFAULT 'payment_unreported',
  fulfilment     fulfilment_state NOT NULL DEFAULT 'stock_reserved',
  cancel_refund  cancel_state NOT NULL DEFAULT 'no_cancel',
  dispute        dispute_state NOT NULL DEFAULT 'dispute_none',
  return_state   return_state NOT NULL DEFAULT 'return_none',
  order_version  INT NOT NULL DEFAULT 1,
  placed_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE refund_actions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id        UUID NOT NULL REFERENCES orders(id),
  amount_sek      INT NOT NULL CHECK (amount_sek > 0),
  related_claim   TEXT NOT NULL,
  seller_report   JSONB,
  buyer_ack       BOOLEAN NOT NULL DEFAULT FALSE,
  buyer_contested BOOLEAN NOT NULL DEFAULT FALSE,
  evidence_status TEXT NOT NULL DEFAULT 'asserted',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE return_records (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id     UUID NOT NULL REFERENCES orders(id),
  origin       return_origin NOT NULL,
  basis        return_basis NOT NULL,
  reason       TEXT NOT NULL,
  request_time TIMESTAMPTZ NOT NULL DEFAULT now(),
  deadline     TIMESTAMPTZ,
  corrections  JSONB NOT NULL DEFAULT '[]'
);

CREATE TABLE disputes (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id         UUID NOT NULL REFERENCES orders(id),
  reason           TEXT NOT NULL,
  evidence         JSONB NOT NULL DEFAULT '[]',
  proposed_outcome JSONB,
  remedy_outcome   remedy_outcome,
  sla_ack_due      TIMESTAMPTZ,
  sla_decision_due TIMESTAMPTZ,
  decided_by       UUID REFERENCES users(id),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE reviews (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id   UUID NOT NULL UNIQUE REFERENCES orders(id),
  rating     INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  text       TEXT,
  published  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMIT;
