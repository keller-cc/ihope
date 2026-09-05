-- 011: remove unused hope_id_changed_at (no cooldown)
ALTER TABLE users DROP COLUMN IF EXISTS hope_id_changed_at;
