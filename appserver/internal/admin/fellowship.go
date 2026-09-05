package admin

import (
	"context"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5"
)

type DomainRow struct {
	ID              string `json:"id"`
	Name            string `json:"name"`
	CreatedAt       string `json:"createdAt"`
	FellowshipCount int    `json:"fellowshipCount"`
}

type FellowshipRow struct {
	ID         string `json:"id"`
	Code       string `json:"code"`
	Name       string `json:"name"`
	DomainID   string `json:"domainId"`
	DomainName string `json:"domainName"`
	CreatedAt  string `json:"createdAt"`
	UserCount  int    `json:"userCount"`
}

func (s *Service) ListDomains(ctx context.Context) ([]DomainRow, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT d.id::text, d.name, d.created_at::text,
			(SELECT COUNT(*)::int FROM fellowships f WHERE f.domain_id = d.id)
		FROM autonomous_domains d
		ORDER BY d.created_at ASC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []DomainRow{}
	for rows.Next() {
		var d DomainRow
		if err := rows.Scan(&d.ID, &d.Name, &d.CreatedAt, &d.FellowshipCount); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

func (s *Service) CreateDomain(ctx context.Context, name string) (*DomainRow, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil, errors.New("name required")
	}
	var d DomainRow
	err := s.pool.QueryRow(ctx, `
		INSERT INTO autonomous_domains (name) VALUES ($1)
		RETURNING id::text, name, created_at::text
	`, name).Scan(&d.ID, &d.Name, &d.CreatedAt)
	if err != nil {
		if strings.Contains(err.Error(), "autonomous_domains_name") {
			return nil, errors.New("domain name taken")
		}
		return nil, err
	}
	d.FellowshipCount = 0
	return &d, nil
}

func (s *Service) UpdateDomain(ctx context.Context, id, name string) (*DomainRow, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil, errors.New("name required")
	}
	var d DomainRow
	err := s.pool.QueryRow(ctx, `
		UPDATE autonomous_domains SET name = $2 WHERE id = $1::uuid
		RETURNING id::text, name, created_at::text
	`, id, name).Scan(&d.ID, &d.Name, &d.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, errors.New("domain not found")
	}
	if err != nil {
		if strings.Contains(err.Error(), "autonomous_domains_name") {
			return nil, errors.New("domain name taken")
		}
		return nil, err
	}
	_ = s.pool.QueryRow(ctx, `
		SELECT COUNT(*)::int FROM fellowships WHERE domain_id = $1::uuid
	`, id).Scan(&d.FellowshipCount)
	return &d, nil
}

func (s *Service) DeleteDomain(ctx context.Context, id string) error {
	var n int
	if err := s.pool.QueryRow(ctx, `
		SELECT COUNT(*)::int FROM fellowships WHERE domain_id = $1::uuid
	`, id).Scan(&n); err != nil {
		return err
	}
	if n > 0 {
		return errors.New("domain has fellowships")
	}
	tag, err := s.pool.Exec(ctx, `DELETE FROM autonomous_domains WHERE id = $1::uuid`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("domain not found")
	}
	return nil
}

func (s *Service) ListFellowships(ctx context.Context) ([]FellowshipRow, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT f.id::text, f.code, f.name, f.domain_id::text, d.name, f.created_at::text,
			(SELECT COUNT(*)::int FROM users u WHERE u.fellowship_id = f.id)
		FROM fellowships f
		JOIN autonomous_domains d ON d.id = f.domain_id
		ORDER BY f.created_at ASC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []FellowshipRow{}
	for rows.Next() {
		var f FellowshipRow
		if err := rows.Scan(&f.ID, &f.Code, &f.Name, &f.DomainID, &f.DomainName, &f.CreatedAt, &f.UserCount); err != nil {
			return nil, err
		}
		out = append(out, f)
	}
	return out, rows.Err()
}

func (s *Service) CreateFellowship(ctx context.Context, code, name, domainID string) (*FellowshipRow, error) {
	code = strings.TrimSpace(code)
	name = strings.TrimSpace(name)
	domainID = strings.TrimSpace(domainID)
	if code == "" {
		return nil, errors.New("code required")
	}
	if domainID == "" {
		return nil, errors.New("domain required")
	}
	if name == "" {
		name = code
	}
	var exists bool
	if err := s.pool.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM autonomous_domains WHERE id = $1::uuid)
	`, domainID).Scan(&exists); err != nil {
		return nil, err
	}
	if !exists {
		return nil, errors.New("domain not found")
	}
	var f FellowshipRow
	err := s.pool.QueryRow(ctx, `
		INSERT INTO fellowships (code, name, domain_id)
		VALUES ($1, $2, $3::uuid)
		RETURNING id::text, code, name, domain_id::text, created_at::text
	`, code, name, domainID).Scan(&f.ID, &f.Code, &f.Name, &f.DomainID, &f.CreatedAt)
	if err != nil {
		if strings.Contains(err.Error(), "fellowships_code") {
			return nil, errors.New("fellowship code taken")
		}
		return nil, err
	}
	_ = s.pool.QueryRow(ctx, `SELECT name FROM autonomous_domains WHERE id = $1::uuid`, domainID).Scan(&f.DomainName)
	f.UserCount = 0
	return &f, nil
}

func (s *Service) UpdateFellowship(ctx context.Context, id, code, name, domainID string) (*FellowshipRow, error) {
	id = strings.TrimSpace(id)
	code = strings.TrimSpace(code)
	name = strings.TrimSpace(name)
	domainID = strings.TrimSpace(domainID)
	if code == "" {
		return nil, errors.New("code required")
	}
	if domainID == "" {
		return nil, errors.New("domain required")
	}
	if name == "" {
		name = code
	}
	var exists bool
	if err := s.pool.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM autonomous_domains WHERE id = $1::uuid)
	`, domainID).Scan(&exists); err != nil {
		return nil, err
	}
	if !exists {
		return nil, errors.New("domain not found")
	}
	var f FellowshipRow
	err := s.pool.QueryRow(ctx, `
		UPDATE fellowships SET code = $2, name = $3, domain_id = $4::uuid
		WHERE id = $1::uuid
		RETURNING id::text, code, name, domain_id::text, created_at::text
	`, id, code, name, domainID).Scan(&f.ID, &f.Code, &f.Name, &f.DomainID, &f.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, errors.New("fellowship not found")
	}
	if err != nil {
		if strings.Contains(err.Error(), "fellowships_code") {
			return nil, errors.New("fellowship code taken")
		}
		return nil, err
	}
	_ = s.pool.QueryRow(ctx, `SELECT name FROM autonomous_domains WHERE id = $1::uuid`, domainID).Scan(&f.DomainName)
	_ = s.pool.QueryRow(ctx, `
		SELECT COUNT(*)::int FROM users WHERE fellowship_id = $1::uuid
	`, id).Scan(&f.UserCount)
	return &f, nil
}

func (s *Service) DeleteFellowship(ctx context.Context, id string) error {
	var n int
	if err := s.pool.QueryRow(ctx, `
		SELECT COUNT(*)::int FROM users WHERE fellowship_id = $1::uuid
	`, id).Scan(&n); err != nil {
		return err
	}
	if n > 0 {
		return errors.New("fellowship has users")
	}
	tag, err := s.pool.Exec(ctx, `DELETE FROM fellowships WHERE id = $1::uuid`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("fellowship not found")
	}
	return nil
}

func (s *Service) SetUserFellowship(ctx context.Context, userID, fellowshipID string) error {
	userID = strings.TrimSpace(userID)
	fellowshipID = strings.TrimSpace(fellowshipID)
	if fellowshipID == "" {
		return errors.New("fellowship required")
	}
	var exists bool
	if err := s.pool.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM fellowships WHERE id = $1::uuid)
	`, fellowshipID).Scan(&exists); err != nil {
		return err
	}
	if !exists {
		return errors.New("fellowship not found")
	}
	tag, err := s.pool.Exec(ctx, `
		UPDATE users SET fellowship_id = $2::uuid WHERE id = $1::uuid
	`, userID, fellowshipID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("user not found")
	}
	return nil
}
