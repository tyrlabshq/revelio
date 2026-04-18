-- REV: Invite-a-friend — both inviter and new user get a 7-day Pro grant on redeem.
-- pro_grants is a generic grant window so we can reuse it for family plans / promos.

CREATE TABLE IF NOT EXISTS friend_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inviter_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  code VARCHAR(16) UNIQUE NOT NULL,
  invited_user_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  redeemed_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_friend_invites_inviter ON friend_invites(inviter_id);

-- Extends user_profiles with a grant window; skipping a migration to user_profiles keeps things clean.
CREATE TABLE IF NOT EXISTS pro_grants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  reason VARCHAR(32) NOT NULL,                   -- 'friend_invite' | 'family_plan' | 'promo'
  starts_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ends_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_pro_grants_user ON pro_grants(user_id, ends_at);
