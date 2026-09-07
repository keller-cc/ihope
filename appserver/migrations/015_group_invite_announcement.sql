-- Member invite policy + group announcement
ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS invite_requires_approval BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS announcement TEXT NOT NULL DEFAULT '';

ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS announcement_updated_at TIMESTAMPTZ;

ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS announcement_updated_by UUID REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE group_join_requests
  ADD COLUMN IF NOT EXISTS invited_by UUID REFERENCES users(id) ON DELETE SET NULL;

INSERT INTO schema_migrations (version) VALUES ('015_group_invite_announcement')
ON CONFLICT DO NOTHING;
