-- QQ-style group join policy: anyone | verify | deny
ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS join_mode TEXT NOT NULL DEFAULT 'verify';

UPDATE conversations
SET join_mode = CASE
  WHEN COALESCE(invite_requires_approval, FALSE) THEN 'verify'
  ELSE 'anyone'
END
WHERE join_mode = 'verify'
  AND COALESCE(invite_requires_approval, FALSE) = FALSE;

-- Keep invite_requires_approval in sync for older readers
UPDATE conversations
SET invite_requires_approval = (join_mode = 'verify');

INSERT INTO schema_migrations (version) VALUES ('017_group_join_mode')
ON CONFLICT DO NOTHING;
