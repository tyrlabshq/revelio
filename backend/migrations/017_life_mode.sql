-- REV-17: Life mode column on user_profiles and family_members.
--
-- A profile can be in at most one life mode at a time (pregnancy | teen |
-- senior | menstrual_cycle). NULL = no life mode. The scoring engine reads
-- this value via personalizeScore() to apply LIFE_MODE_FLAG_MULTIPLIER.
--
-- Enum constraint is enforced at the route handler (routes/profiles.ts) to
-- keep the column permissive for future additions without a new migration.

ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS life_mode VARCHAR(20);
ALTER TABLE family_members ADD COLUMN IF NOT EXISTS life_mode VARCHAR(20);
