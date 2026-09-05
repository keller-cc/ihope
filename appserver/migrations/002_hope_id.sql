-- 002: IHope 数字号
ALTER TABLE users ADD COLUMN IF NOT EXISTS hope_id TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS users_hope_id_uidx ON users (hope_id) WHERE hope_id IS NOT NULL;
