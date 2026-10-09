-- Migration 004: command audit, transactional outbox, indexes
BEGIN;

CREATE TABLE commands (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  operation_id     UUID NOT NULL,
  principal_id     UUID NOT NULL,
  order_id         UUID NOT NULL REFERENCES orders(id),
  actor            TEXT NOT NULL,
  operation        TEXT NOT NULL,
  fingerprint      TEXT NOT NULL,
  payload          JSONB NOT NULL,
  before_state     JSONB NOT NULL,
  after_state      JSONB NOT NULL,
  committed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (principal_id, operation_id)
);

CREATE TABLE outbox (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  command_id   UUID NOT NULL REFERENCES commands(id),
  recipient_id UUID NOT NULL,
  channel      TEXT NOT NULL,
  payload      JSONB NOT NULL,
  attempts     INT NOT NULL DEFAULT 0,
  delivered_at TIMESTAMPTZ,
  alerted      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_orders_buyer ON orders(buyer_id);
CREATE INDEX idx_orders_seller ON orders(seller_id);
CREATE INDEX idx_orders_payment ON orders(payment);
CREATE INDEX idx_orders_fulfilment ON orders(fulfilment);
CREATE INDEX idx_refunds_order ON refund_actions(order_id);
CREATE INDEX idx_outbox_pending ON outbox(delivered_at) WHERE delivered_at IS NULL;

COMMIT;
