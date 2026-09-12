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
