package auth

import (
	"context"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5"
)

// EnsureFellowshipsBootstrapped creates the env FELLOWSHIP_CODE fellowship if missing,
// and assigns any users without a fellowship to that (or the first) fellowship.
func (s *Service) EnsureFellowshipsBootstrapped(ctx context.Context) error {
	code := strings.TrimSpace(s.opt.FellowshipCode)
	if code == "" {
		code = "盼望之地"
	}

	var domainID string
	err := s.pool.QueryRow(ctx, `
		SELECT id::text FROM autonomous_domains ORDER BY created_at ASC LIMIT 1
	`).Scan(&domainID)
	if errors.Is(err, pgx.ErrNoRows) {
		err = s.pool.QueryRow(ctx, `
			INSERT INTO autonomous_domains (name) VALUES ('默认自治域')
			RETURNING id::text
		`).Scan(&domainID)
	}
	if err != nil {
		return err
	}

	var fellowshipID string
	err = s.pool.QueryRow(ctx, `
		SELECT id::text FROM fellowships WHERE code = $1
	`, code).Scan(&fellowshipID)
	if errors.Is(err, pgx.ErrNoRows) {
		err = s.pool.QueryRow(ctx, `
			INSERT INTO fellowships (code, name, domain_id)
			VALUES ($1, $2, $3::uuid)
			RETURNING id::text
		`, code, "默认团契", domainID).Scan(&fellowshipID)
	}
	if err != nil {
		return err
	}

	_, err = s.pool.Exec(ctx, `
		UPDATE users SET fellowship_id = $1::uuid WHERE fellowship_id IS NULL
	`, fellowshipID)
	return err
}

func (s *Service) lookupFellowshipID(ctx context.Context, code string) (string, error) {
	code = strings.TrimSpace(code)
	if code == "" {
		return "", ErrInvalidFellowshipCode
	}
	var id string
	err := s.pool.QueryRow(ctx, `
		SELECT id::text FROM fellowships WHERE code = $1
	`, code).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrInvalidFellowshipCode
	}
	if err != nil {
		return "", err
	}
	return id, nil
}
