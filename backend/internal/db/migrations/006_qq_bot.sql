-- QQ 机器人门铃 / 金句 / 60s 读世界绑定

CREATE TABLE IF NOT EXISTS user_qq_bindings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    qq_openid TEXT NOT NULL UNIQUE,
    doorbell_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    poetry_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    news_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    last_doorbell_at TIMESTAMPTZ,
    bound_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS qq_bind_codes (
    code TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_qq_bind_codes_user ON qq_bind_codes (user_id);
CREATE INDEX IF NOT EXISTS idx_qq_bindings_poetry ON user_qq_bindings (poetry_enabled) WHERE poetry_enabled;
CREATE INDEX IF NOT EXISTS idx_qq_bindings_news ON user_qq_bindings (news_enabled) WHERE news_enabled;
