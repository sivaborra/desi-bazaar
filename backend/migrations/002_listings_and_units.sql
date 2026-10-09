-- Migration 002: listings, immutable snapshots, inventory units
BEGIN;

CREATE TABLE listings (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id          UUID NOT NULL REFERENCES sellers(user_id),
  category           TEXT NOT NULL,
  condition          TEXT NOT NULL,
  size_text          TEXT NOT NULL,
  defect_disclosure  TEXT,
  price_sek          INT NOT NULL CHECK (price_sek > 0),
  fulfilment_options JSONB NOT NULL,
  status             TEXT NOT NULL DEFAULT 'draft',
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE listing_snapshots (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id   UUID NOT NULL REFERENCES listings(id),
  snapshot     JSONB NOT NULL,
  recipient    TEXT NOT NULL,
  amount_sek   INT NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE listing_units (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id UUID NOT NULL REFERENCES listings(id),
  status     unit_status NOT NULL DEFAULT 'available'
);

COMMIT;
