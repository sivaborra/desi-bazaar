-- Migration 001: extensions, §11/§12 enums, users, sellers
-- Target: PostgreSQL 14+
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE payment_state AS ENUM (
  'payment_unreported', 'payment_reported', 'payment_seller_confirmed',
  'payment_unresolved', 'payment_established_unpaid'
);
CREATE TYPE fulfilment_state AS ENUM (
  'stock_reserved', 'stock_released', 'dispatched',
  'receipt_confirmed', 'delivery_evidenced', 'delivery_unconfirmed'
);
CREATE TYPE cancel_state AS ENUM (
  'no_cancel', 'cancellation_requested', 'cancelled_unpaid',
  'refund_requested', 'refund_reported', 'refund_acknowledged', 'refund_contested'
);
CREATE TYPE dispute_state AS ENUM (
  'dispute_none', 'dispute_open', 'dispute_decided',
  'dispute_resolved', 'dispute_closed_unconfirmed', 'dispute_non_compliant'
);
CREATE TYPE return_state AS ENUM (
  'return_none', 'return_requested', 'return_authorised',
  'goods_sent_back', 'return_received'
);
CREATE TYPE return_origin AS ENUM ('buyer_initiated', 'cancellation_converted');
CREATE TYPE return_basis AS ENUM ('statutory_withdrawal', 'defective_goods', 'voluntary_policy');
CREATE TYPE remedy_outcome AS ENUM (
  'remedy_acknowledged', 'remedy_independently_evidenced',
  'closed_unconfirmed', 'unresolved_non_compliant'
);
CREATE TYPE user_role AS ENUM ('buyer', 'seller', 'admin');
CREATE TYPE seller_status AS ENUM ('pending', 'approved', 'rejected', 'suspended');
CREATE TYPE unit_status AS ENUM ('available', 'reserved', 'sold');

CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone         TEXT NOT NULL UNIQUE,
  email         TEXT,
  role          user_role NOT NULL DEFAULT 'buyer',
  otp_verified  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE sellers (
  user_id            UUID PRIMARY KEY REFERENCES users(id),
  status             seller_status NOT NULL DEFAULT 'pending',
  trader             BOOLEAN NOT NULL,
  trader_basis       TEXT,
  id_document_ref    TEXT,
  badge_scope        TEXT,
  badge_date         DATE,
  badge_active       BOOLEAN NOT NULL DEFAULT FALSE,
  swish_recipient    TEXT,
  checklist_version  TEXT,
  reviewed_evidence  JSONB,
  reviewer_id        UUID REFERENCES users(id),
  reviewed_at        TIMESTAMPTZ,
  rejection_reason   TEXT,
  reapplications     INT NOT NULL DEFAULT 0
);

COMMIT;
