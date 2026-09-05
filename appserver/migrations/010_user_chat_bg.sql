-- Account-wide chat wallpaper (not per conversation)

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS chat_bg TEXT NOT NULL DEFAULT '';

INSERT INTO schema_migrations (version) VALUES ('010_user_chat_bg')
ON CONFLICT DO NOTHING;
