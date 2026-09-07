package games

import (
	"context"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

type ScoreRow struct {
	Rank      int    `json:"rank"`
	UserID    string `json:"userId"`
	Username  string `json:"username"`
	Score     int    `json:"score"`
	CreatedAt string `json:"createdAt"`
}

type Service struct {
	pool *pgxpool.Pool
}

func NewService(pool *pgxpool.Pool) *Service {
	return &Service{pool: pool}
}

const dinoGameID = "dino"

// SubmitDinoScore stores a run if it beats the user's previous best.
func (s *Service) SubmitDinoScore(ctx context.Context, userID string, score int) (best int, improved bool, err error) {
	if score < 0 {
		return 0, false, errors.New("invalid score")
	}
	if score > 1_000_000 {
		return 0, false, errors.New("score too high")
	}
	var prev int
	err = s.pool.QueryRow(ctx, `
		SELECT COALESCE(MAX(score), 0) FROM game_scores
		WHERE game_id = $1 AND user_id = $2
	`, dinoGameID, userID).Scan(&prev)
	if err != nil {
		return 0, false, err
	}
	if score <= prev {
		return prev, false, nil
	}
	_, err = s.pool.Exec(ctx, `
		INSERT INTO game_scores (game_id, user_id, score)
		VALUES ($1, $2, $3)
	`, dinoGameID, userID, score)
	if err != nil {
		return prev, false, err
	}
	return score, true, nil
}

// ListDinoLeaderboard returns top scores (best per user).
func (s *Service) ListDinoLeaderboard(ctx context.Context, limit int) ([]ScoreRow, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	rows, err := s.pool.Query(ctx, `
		SELECT u.id::text, u.username, b.score, b.created_at::text
		FROM (
			SELECT DISTINCT ON (user_id) user_id, score, created_at
			FROM game_scores
			WHERE game_id = $1
			ORDER BY user_id, score DESC, created_at ASC
		) b
		JOIN users u ON u.id = b.user_id
		ORDER BY b.score DESC, b.created_at ASC
		LIMIT $2
	`, dinoGameID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]ScoreRow, 0, limit)
	rank := 0
	for rows.Next() {
		rank++
		var r ScoreRow
		if err := rows.Scan(&r.UserID, &r.Username, &r.Score, &r.CreatedAt); err != nil {
			return nil, err
		}
		r.Rank = rank
		r.Username = strings.TrimSpace(r.Username)
		out = append(out, r)
	}
	return out, rows.Err()
}

// MyDinoBest returns the caller's best score (0 if none).
func (s *Service) MyDinoBest(ctx context.Context, userID string) (int, error) {
	var best int
	err := s.pool.QueryRow(ctx, `
		SELECT COALESCE(MAX(score), 0) FROM game_scores
		WHERE game_id = $1 AND user_id = $2
	`, dinoGameID, userID).Scan(&best)
	return best, err
}
