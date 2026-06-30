-- 记录成员最近一次退群时间，再入群时可拉取退群前的历史消息
ALTER TABLE conversation_members
    ADD COLUMN IF NOT EXISTS last_left_at TIMESTAMPTZ;

UPDATE conversation_members
SET last_left_at = left_at
WHERE left_at IS NOT NULL AND last_left_at IS NULL;
