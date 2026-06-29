-- Migration 001：账号体系基础表（阶段 1）
-- 由 internal/db/db.go 在启动时自动执行

-- 用户表：注册信息 + E2EE 身份公钥（明文密码仅存 password_hash）
CREATE TABLE IF NOT EXISTS users (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email               TEXT NOT NULL UNIQUE,
    username            TEXT NOT NULL UNIQUE,
    password_hash       TEXT NOT NULL,
    avatar_url          TEXT,
    identity_public_key TEXT NOT NULL,
    email_verified_at   TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 设备表：多设备登录；refresh_token 仅存 SHA256 哈希
CREATE TABLE IF NOT EXISTS user_devices (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id          TEXT NOT NULL,
    device_name        TEXT,
    refresh_token_hash TEXT,
    push_token         TEXT,
    platform           TEXT,
    last_active_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_user_devices_user_id ON user_devices(user_id);

-- 密码重置令牌：仅存 token 哈希，30 分钟有效，用后标记 used_at
CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at    TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_password_reset_token_hash ON password_reset_tokens(token_hash);
