CREATE TABLE IF NOT EXISTS device_link_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    initiator_device_id TEXT NOT NULL,
    ciphertext TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    expires_at TIMESTAMPTZ NOT NULL,
    completed_device_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_device_link_user_id ON device_link_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_device_link_expires ON device_link_sessions(expires_at);
