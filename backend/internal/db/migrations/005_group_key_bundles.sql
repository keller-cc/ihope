-- 群 welcome 密文包持久化（服务端不解密，成员离线可 REST 拉取）
CREATE TABLE IF NOT EXISTS group_key_bundles (
    conversation_id   UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    epoch             INT NOT NULL,
    recipient_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sender_user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    ciphertext        TEXT NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (conversation_id, epoch, recipient_user_id)
);

CREATE INDEX IF NOT EXISTS idx_group_key_bundles_recipient
    ON group_key_bundles (conversation_id, recipient_user_id);
