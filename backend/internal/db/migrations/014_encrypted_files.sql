-- 阶段 6：加密文件 blob 存储（客户端 AES 加密后上传）
CREATE TABLE IF NOT EXISTS encrypted_files (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    uploader_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    storage_path    TEXT NOT NULL,
    byte_size       BIGINT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_encrypted_files_conversation ON encrypted_files(conversation_id);
