-- Group @ mentions + per-user visit / home-tip state.
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS mention_all BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS message_mentions (
  message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (message_id, user_id)
);

CREATE INDEX IF NOT EXISTS message_mentions_user_idx
  ON message_mentions (user_id, message_id);

CREATE TABLE IF NOT EXISTS message_mention_visits (
  message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  visited_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)
);

ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS mention_home_tip BOOLEAN NOT NULL DEFAULT FALSE;

INSERT INTO schema_migrations (version) VALUES ('027_message_mentions')
ON CONFLICT DO NOTHING;
