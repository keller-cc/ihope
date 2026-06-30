-- 阶段 4：群成员入群 epoch（无历史消息过滤）
ALTER TABLE conversation_members
    ADD COLUMN IF NOT EXISTS joined_epoch INT NOT NULL DEFAULT 0;
