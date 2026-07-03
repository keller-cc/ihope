-- 会话、成员、消息、群密钥、加密文件

CREATE TABLE conversations (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type       TEXT NOT NULL CHECK (type IN ('private', 'group')),
    name       TEXT,
    avatar_url TEXT,
    epoch      INT NOT NULL DEFAULT 0,
    owner_id   UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE conversation_members (
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    left_at         TIMESTAMPTZ,
    joined_epoch    INT NOT NULL DEFAULT 0,
    role            TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX idx_conversation_members_user_active ON conversation_members(user_id)
    WHERE left_at IS NULL;
CREATE INDEX idx_conversation_members_conv_active ON conversation_members(conversation_id)
    WHERE left_at IS NULL;

-- 多次退群/再入群时的可见历史时段（消息列表过滤用）
CREATE TABLE conversation_member_periods (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    left_at         TIMESTAMPTZ,
    joined_epoch    INT NOT NULL DEFAULT 0
);

CREATE INDEX idx_member_periods_active ON conversation_member_periods(conversation_id, user_id)
    WHERE left_at IS NULL;
CREATE INDEX idx_member_periods_lookup ON conversation_member_periods(conversation_id, user_id, joined_at);
CREATE INDEX idx_member_periods_user ON conversation_member_periods(user_id, conversation_id);

CREATE TABLE encrypted_files (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    uploader_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    storage_path    TEXT NOT NULL,
    byte_size       BIGINT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_encrypted_files_conversation ON encrypted_files(conversation_id);

CREATE TABLE messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type            TEXT NOT NULL CHECK (type IN ('text', 'image', 'file', 'audio', 'announcement', 'system')),
    ciphertext      TEXT NOT NULL,
    epoch           INT NOT NULL DEFAULT 0,
    file_id         UUID REFERENCES encrypted_files(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_messages_conversation_created ON messages(conversation_id, created_at DESC);
CREATE INDEX idx_messages_conversation_epoch_created ON messages(conversation_id, epoch, created_at DESC);

CREATE TABLE group_key_bundles (
    conversation_id   UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    epoch             INT NOT NULL,
    recipient_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sender_user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    ciphertext        TEXT NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (conversation_id, epoch, recipient_user_id)
);

CREATE INDEX idx_group_key_bundles_recipient ON group_key_bundles(conversation_id, recipient_user_id);
