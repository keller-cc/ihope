-- 013: 用户上传的聊天背景图库（可复用 / 删除）

CREATE TABLE IF NOT EXISTS user_chat_backgrounds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  url TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS user_chat_backgrounds_user_created_idx
  ON user_chat_backgrounds (user_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS user_chat_backgrounds_user_url_uidx
  ON user_chat_backgrounds (user_id, url);
