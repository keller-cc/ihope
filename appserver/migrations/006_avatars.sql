-- Avatars + friend remarks

ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE friendships ADD COLUMN IF NOT EXISTS remark TEXT NOT NULL DEFAULT '';

INSERT INTO schema_migrations (version) VALUES ('006_avatars')
ON CONFLICT DO NOTHING;
