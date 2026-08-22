-- 金句（自定义文案库）每日推送开关
ALTER TABLE user_qq_bindings
    ADD COLUMN IF NOT EXISTS quotes_enabled BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_qq_bindings_quotes
    ON user_qq_bindings (quotes_enabled) WHERE quotes_enabled;
