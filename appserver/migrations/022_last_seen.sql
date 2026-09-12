ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

INSERT INTO schema_migrations (version) VALUES ('022_last_seen')
ON CONFLICT DO NOTHING;
