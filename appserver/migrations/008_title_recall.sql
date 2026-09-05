-- Custom member title + message recall
ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS member_title TEXT NOT NULL DEFAULT '';

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS recalled_at TIMESTAMPTZ;

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS recalled_by UUID REFERENCES users(id) ON DELETE SET NULL;

INSERT INTO schema_migrations (version) VALUES ('008_title_recall')
ON CONFLICT DO NOTHING;
