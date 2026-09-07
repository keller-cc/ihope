-- Per-user game high scores (dino leaderboard)
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
