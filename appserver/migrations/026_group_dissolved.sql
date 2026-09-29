-- Soft-dissolve groups: keep row + messages; members soft-removed with reason dissolved.
ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS dissolved_at TIMESTAMPTZ;

INSERT INTO schema_migrations (version) VALUES ('026_group_dissolved')
ON CONFLICT DO NOTHING;
