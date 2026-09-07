-- Soft-remove members (kick keeps session like QQ); active membership = removed_at IS NULL
ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS removed_at TIMESTAMPTZ;

ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS remove_reason TEXT;

INSERT INTO schema_migrations (version) VALUES ('016_member_soft_remove')
ON CONFLICT DO NOTHING;
