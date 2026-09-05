-- 012: 团契（组织码）+ 自治域；同域内才可互查

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

-- 种子：默认自治域 + 默认团契（与 FELLOWSHIP_CODE 默认值一致）
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
