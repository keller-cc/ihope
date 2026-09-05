-- Group member roles: member | admin (owner remains conversations.owner_id)
ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'member';

UPDATE conversation_members
SET role = 'member'
WHERE role IS NULL OR role = '';

ALTER TABLE conversation_members DROP CONSTRAINT IF EXISTS conversation_members_role_check;
ALTER TABLE conversation_members
  ADD CONSTRAINT conversation_members_role_check
  CHECK (role IN ('member', 'admin'));

INSERT INTO schema_migrations (version) VALUES ('007_group_admin')
ON CONFLICT DO NOTHING;
