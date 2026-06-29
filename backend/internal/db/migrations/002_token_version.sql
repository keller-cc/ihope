-- 改密/重置密码时递增 token_version，使已签发的 access_token 立即失效
ALTER TABLE users ADD COLUMN IF NOT EXISTS token_version INT NOT NULL DEFAULT 0;
