-- 成员在群时段：支持多次退群/再入群时分别计算可见历史
CREATE TABLE IF NOT EXISTS conversation_member_periods (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    left_at         TIMESTAMPTZ,
    joined_epoch    INT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_member_periods_lookup
    ON conversation_member_periods (conversation_id, user_id, joined_at);

INSERT INTO conversation_member_periods (conversation_id, user_id, joined_at, left_at, joined_epoch)
SELECT conversation_id, user_id, joined_at, left_at, joined_epoch
FROM conversation_members;
