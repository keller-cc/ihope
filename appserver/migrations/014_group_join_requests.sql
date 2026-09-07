-- Group join requires owner/admin approval
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
