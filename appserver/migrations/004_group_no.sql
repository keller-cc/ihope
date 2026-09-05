-- 004: QQ-style group number
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS group_no TEXT;
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS conversations_group_no_uidx
  ON conversations (group_no) WHERE group_no IS NOT NULL;
