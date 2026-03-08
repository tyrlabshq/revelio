-- REV-10: Personalization + family profiles

-- Add personalization columns to user_profiles
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS goals TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Family members table
CREATE TABLE IF NOT EXISTS family_members (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  owner_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  is_child BOOLEAN DEFAULT FALSE,
  goals TEXT[] DEFAULT '{}',
  allergies TEXT[] DEFAULT '{}',
  avatar_color TEXT DEFAULT '#00B87C',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_family_members_owner ON family_members(owner_id);
