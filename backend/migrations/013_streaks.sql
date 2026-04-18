-- REV-STREAKS: user scan streaks + weekly goal for gamification
CREATE TABLE IF NOT EXISTS user_streaks (
  user_id UUID PRIMARY KEY REFERENCES user_profiles(id) ON DELETE CASCADE,
  current_streak_days INTEGER NOT NULL DEFAULT 0,
  longest_streak_days INTEGER NOT NULL DEFAULT 0,
  last_scan_date DATE,
  weekly_goal INTEGER NOT NULL DEFAULT 10,       -- target scans per week
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
