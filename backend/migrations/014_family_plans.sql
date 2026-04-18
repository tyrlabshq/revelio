-- REV: Family plan sharing — owner holds Pro entitlement, members inherit via family_plan_members.

CREATE TABLE IF NOT EXISTS family_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  max_members INTEGER NOT NULL DEFAULT 6,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_family_owner ON family_plans(owner_id);

CREATE TABLE IF NOT EXISTS family_plan_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id UUID NOT NULL REFERENCES family_plans(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  role VARCHAR(16) NOT NULL DEFAULT 'member',    -- 'owner' | 'member'
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (plan_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_fpm_user ON family_plan_members(user_id);

CREATE TABLE IF NOT EXISTS family_plan_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id UUID NOT NULL REFERENCES family_plans(id) ON DELETE CASCADE,
  code VARCHAR(16) UNIQUE NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_by UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
