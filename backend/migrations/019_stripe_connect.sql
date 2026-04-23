-- Stripe Connect: creator payout accounts + ledger.
--
-- creator_payout_accounts mirrors one Stripe Express account per creator. We
-- store the minimum we need (id, status, payouts_enabled) so the dashboard can
-- render without a round-trip to Stripe on every request; the full source of
-- truth is always Stripe itself.
--
-- creator_payouts is the local ledger for transfers we queue. Rows are created
-- in `pending` state by the payout request endpoint, then flipped to
-- `paid`/`failed` by the background job that calls `stripe.transfers.create`.
-- The ledger is append-only: never mutate amount_cents after insert.

CREATE TABLE IF NOT EXISTS creator_payout_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  stripe_account_id VARCHAR(128) UNIQUE NOT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'pending',
  payouts_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS creator_payouts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  stripe_transfer_id VARCHAR(128) UNIQUE,
  amount_cents INTEGER NOT NULL,
  currency VARCHAR(8) NOT NULL DEFAULT 'usd',
  status VARCHAR(32) NOT NULL DEFAULT 'pending',
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_creator_payouts_user ON creator_payouts(user_id, created_at DESC);
