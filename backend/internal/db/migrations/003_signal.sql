-- Signal Protocol KDS：单聊 X3DH

CREATE TABLE device_signal_state (
    user_id              UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id            TEXT NOT NULL,
    signal_device_id     INT NOT NULL DEFAULT 1,
    registration_id      INT NOT NULL,
    identity_key_pub     BYTEA NOT NULL,
    signed_pre_key_id    INT NOT NULL,
    signed_pre_key_pub   BYTEA NOT NULL,
    signed_pre_key_sig   BYTEA NOT NULL,
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, device_id)
);

CREATE INDEX idx_device_signal_state_user ON device_signal_state(user_id);

CREATE TABLE one_time_prekeys (
    id           BIGSERIAL PRIMARY KEY,
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id    TEXT NOT NULL,
    pre_key_id   INT NOT NULL,
    public_key   BYTEA NOT NULL,
    consumed_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, device_id, pre_key_id),
    FOREIGN KEY (user_id, device_id)
        REFERENCES device_signal_state(user_id, device_id) ON DELETE CASCADE
);

CREATE INDEX idx_one_time_prekeys_available ON one_time_prekeys(user_id, device_id)
    WHERE consumed_at IS NULL;
