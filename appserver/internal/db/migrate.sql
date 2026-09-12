-- Web IM schema (independent of legacy ihope DB)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL UNIQUE,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  email_verified BOOLEAN NOT NULL DEFAULT FALSE,
  hope_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS hope_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS users_hope_id_uidx ON users (hope_id) WHERE hope_id IS NOT NULL;

ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO schema_migrations (version) VALUES ('001_init'), ('002_hope_id')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS email_verification_tokens (
  token_hash TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS email_verify_user_idx ON email_verification_tokens (user_id);

CREATE TABLE IF NOT EXISTS password_reset_tokens (
  token_hash TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS password_reset_user_idx ON password_reset_tokens (user_id);

INSERT INTO schema_migrations (version) VALUES ('021_password_reset')
ON CONFLICT DO NOTHING;

INSERT INTO schema_migrations (version) VALUES ('022_last_seen')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL CHECK (type IN ('dm', 'group')),
  title TEXT NOT NULL DEFAULT '',
  group_no TEXT,
  owner_id UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE conversations ADD COLUMN IF NOT EXISTS group_no TEXT;
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS conversations_group_no_uidx
  ON conversations (group_no) WHERE group_no IS NOT NULL;

INSERT INTO schema_migrations (version) VALUES ('004_group_no')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS conversation_members (
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);

CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES users(id),
  type TEXT NOT NULL DEFAULT 'text',
  body_sealed TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS messages_conv_created_idx
  ON messages (conversation_id, created_at DESC);

CREATE TABLE IF NOT EXISTS user_qq_bindings (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  qq_openid TEXT NOT NULL UNIQUE,
  doorbell_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  poetry_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  quotes_enabled BOOLEAN NOT NULL DEFAULT TRUE,
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

-- 联系人（双向各存一行）
CREATE TABLE IF NOT EXISTS friendships (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  friend_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, friend_id),
  CHECK (user_id <> friend_id)
);

ALTER TABLE conversation_members ADD COLUMN IF NOT EXISTS last_read_at TIMESTAMPTZ;
ALTER TABLE conversation_members ADD COLUMN IF NOT EXISTS pinned_at TIMESTAMPTZ;
ALTER TABLE conversation_members ADD COLUMN IF NOT EXISTS muted BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE conversation_members ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ;

INSERT INTO schema_migrations (version) VALUES ('003_last_read'), ('005_session_friends')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS friend_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
  message TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_at TIMESTAMPTZ,
  CHECK (from_user_id <> to_user_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS friend_requests_pending_uidx
  ON friend_requests (from_user_id, to_user_id)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS friend_requests_to_pending_idx
  ON friend_requests (to_user_id, created_at DESC)
  WHERE status = 'pending';

ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE friendships ADD COLUMN IF NOT EXISTS remark TEXT NOT NULL DEFAULT '';

INSERT INTO schema_migrations (version) VALUES ('006_avatars')
ON CONFLICT DO NOTHING;

ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'member';

UPDATE conversation_members
SET role = 'member'
WHERE role IS NULL OR role = '';

ALTER TABLE conversation_members DROP CONSTRAINT IF EXISTS conversation_members_role_check;
ALTER TABLE conversation_members
  ADD CONSTRAINT conversation_members_role_check
  CHECK (role IN ('member', 'admin'));

INSERT INTO schema_migrations (version) VALUES ('007_group_admin')
ON CONFLICT DO NOTHING;

ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS member_title TEXT NOT NULL DEFAULT '';

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS recalled_at TIMESTAMPTZ;

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS recalled_by UUID REFERENCES users(id) ON DELETE SET NULL;

INSERT INTO schema_migrations (version) VALUES ('008_title_recall')
ON CONFLICT DO NOTHING;

ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS chat_bg TEXT NOT NULL DEFAULT '';

INSERT INTO schema_migrations (version) VALUES ('009_chat_bg')
ON CONFLICT DO NOTHING;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS chat_bg TEXT NOT NULL DEFAULT '';

INSERT INTO schema_migrations (version) VALUES ('010_user_chat_bg')
ON CONFLICT DO NOTHING;

ALTER TABLE users DROP COLUMN IF EXISTS hope_id_changed_at;

INSERT INTO schema_migrations (version) VALUES ('011_drop_hope_id_changed_at')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS autonomous_domains (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS autonomous_domains_name_uidx
  ON autonomous_domains (name);

CREATE TABLE IF NOT EXISTS fellowships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  domain_id UUID NOT NULL REFERENCES autonomous_domains(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS fellowships_code_uidx ON fellowships (code);

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS fellowship_id UUID REFERENCES fellowships(id);

INSERT INTO autonomous_domains (id, name)
VALUES ('00000000-0000-4000-8000-000000000001'::uuid, '默认自治域')
ON CONFLICT (id) DO NOTHING;

INSERT INTO fellowships (id, code, name, domain_id)
SELECT
  '00000000-0000-4000-8000-000000000002'::uuid,
  '盼望之地',
  '默认团契',
  '00000000-0000-4000-8000-000000000001'::uuid
WHERE NOT EXISTS (SELECT 1 FROM fellowships WHERE code = '盼望之地')
ON CONFLICT (id) DO NOTHING;

UPDATE users
SET fellowship_id = COALESCE(
  (SELECT id FROM fellowships WHERE code = '盼望之地' LIMIT 1),
  (SELECT id FROM fellowships ORDER BY created_at ASC LIMIT 1)
)
WHERE fellowship_id IS NULL
  AND EXISTS (SELECT 1 FROM fellowships);

INSERT INTO schema_migrations (version) VALUES ('012_fellowships_domains')
ON CONFLICT DO NOTHING;

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

INSERT INTO schema_migrations (version) VALUES ('013_user_chat_backgrounds')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS group_join_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  from_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'rejected')),
  message TEXT NOT NULL DEFAULT '',
  decided_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS group_join_requests_pending_uidx
  ON group_join_requests (conversation_id, from_user_id)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS group_join_requests_conv_pending_idx
  ON group_join_requests (conversation_id, created_at DESC)
  WHERE status = 'pending';

INSERT INTO schema_migrations (version) VALUES ('014_group_join_requests')
ON CONFLICT DO NOTHING;

ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS invite_requires_approval BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS announcement TEXT NOT NULL DEFAULT '';

ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS announcement_updated_at TIMESTAMPTZ;

ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS announcement_updated_by UUID REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE group_join_requests
  ADD COLUMN IF NOT EXISTS invited_by UUID REFERENCES users(id) ON DELETE SET NULL;

INSERT INTO schema_migrations (version) VALUES ('015_group_invite_announcement')
ON CONFLICT DO NOTHING;

ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS removed_at TIMESTAMPTZ;

ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS remove_reason TEXT;

INSERT INTO schema_migrations (version) VALUES ('016_member_soft_remove')
ON CONFLICT DO NOTHING;

ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS join_mode TEXT NOT NULL DEFAULT 'verify';

UPDATE conversations
SET join_mode = CASE
  WHEN COALESCE(invite_requires_approval, FALSE) THEN 'verify'
  ELSE 'anyone'
END
WHERE join_mode = 'verify'
  AND COALESCE(invite_requires_approval, FALSE) = FALSE;

UPDATE conversations
SET invite_requires_approval = (join_mode = 'verify');

INSERT INTO schema_migrations (version) VALUES ('017_group_join_mode')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS group_announcements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  require_confirm BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS group_announcements_conv_created_idx
  ON group_announcements (conversation_id, created_at DESC);

CREATE TABLE IF NOT EXISTS group_announcement_acks (
  announcement_id UUID NOT NULL REFERENCES group_announcements(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  acked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (announcement_id, user_id)
);

CREATE INDEX IF NOT EXISTS group_announcement_acks_user_idx
  ON group_announcement_acks (user_id, announcement_id);

INSERT INTO group_announcements (conversation_id, author_id, body, require_confirm, created_at, updated_at)
SELECT c.id,
       COALESCE(c.announcement_updated_by, c.owner_id),
       trim(c.announcement),
       TRUE,
       COALESCE(c.announcement_updated_at, c.created_at),
       COALESCE(c.announcement_updated_at, c.created_at)
FROM conversations c
WHERE c.type = 'group'
  AND trim(c.announcement) <> ''
  AND COALESCE(c.announcement_updated_by, c.owner_id) IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM group_announcements a WHERE a.conversation_id = c.id
  );

INSERT INTO schema_migrations (version) VALUES ('018_group_announcements')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS game_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id TEXT NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  score INT NOT NULL CHECK (score >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS game_scores_game_score_idx
  ON game_scores (game_id, score DESC, created_at ASC);

CREATE INDEX IF NOT EXISTS game_scores_user_game_idx
  ON game_scores (user_id, game_id, score DESC);

INSERT INTO schema_migrations (version) VALUES ('019_game_scores')
ON CONFLICT DO NOTHING;

-- Manila: light room metadata + end-of-match summaries (no step-by-step state)

CREATE TABLE IF NOT EXISTS manila_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  host_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'open', -- open | playing | closed
  max_players INT NOT NULL DEFAULT 5 CHECK (max_players BETWEEN 3 AND 5),
  is_private BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS manila_rooms_status_idx ON manila_rooms (status, updated_at DESC);

CREATE TABLE IF NOT EXISTS manila_match_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID REFERENCES manila_rooms(id) ON DELETE SET NULL,
  room_code TEXT,
  finished_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS manila_match_result_players (
  match_id UUID NOT NULL REFERENCES manila_match_results(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  username TEXT NOT NULL,
  rank INT NOT NULL CHECK (rank >= 1),
  fortune INT NOT NULL,
  PRIMARY KEY (match_id, user_id)
);

CREATE INDEX IF NOT EXISTS manila_match_results_finished_idx
  ON manila_match_results (finished_at DESC);

INSERT INTO schema_migrations (version) VALUES ('020_manila')
ON CONFLICT DO NOTHING;
