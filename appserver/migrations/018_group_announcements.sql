-- QQ-style multi announcements + per-member ack
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

-- Migrate legacy single announcement column into first history row
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
