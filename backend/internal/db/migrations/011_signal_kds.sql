-- Signal Protocol KDS：设备级身份密钥与预密钥（单聊 X3DH）

CREATE TABLE IF NOT EXISTS device_signal_state (
    user_id              UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id            TEXT NOT NULL,
    signal_device_id     INT NOT NULL DEFAULT 1,
    registration_id      INT NOT NULL,
    identity_key_pub     BYTEA NOT NULL,
    signed_pre_key_id    INT NOT NULL,
    signed_pre_key_pub   BYTEA NOT NULL,
    signed_pre_key_sig   BYTEA NOT NULL,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_device_signal_state_user
    ON device_signal_state (user_id);

CREATE TABLE IF NOT EXISTS one_time_prekeys (
    id           BIGSERIAL PRIMARY KEY,
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id    TEXT NOT NULL,
    pre_key_id   INT NOT NULL,
    public_key   BYTEA NOT NULL,
    consumed_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, device_id, pre_key_id),
    FOREIGN KEY (user_id, device_id)
        REFERENCES device_signal_state (user_id, device_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_one_time_prekeys_available
    ON one_time_prekeys (user_id, device_id)
    WHERE consumed_at IS NULL;

-- Megolm 群密钥 bundle：记录上传者与版本，便于补传检测
ALTER TABLE group_key_bundles
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
