-- Per-member chat wallpaper (personal; only visible to self)

ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS chat_bg TEXT NOT NULL DEFAULT '';

INSERT INTO schema_migrations (version) VALUES ('009_chat_bg')
ON CONFLICT DO NOTHING;
