// Package user 用户领域：数据模型、PostgreSQL 仓储、/api/users/me 接口。
//
// Repository 封装所有 users / user_devices / password_reset_tokens 表的 SQL。
package user

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrNotFound      = errors.New("user not found")
	ErrEmailTaken    = errors.New("email already registered")
	ErrUsernameTaken = errors.New("username already taken")
	ErrDisabled      = errors.New("user disabled")
)

// User 返回给客户端的用户信息（不含 password_hash）。
type User struct {
	ID                string     `json:"id"`
	Email             string     `json:"email"`
	Username          string     `json:"username"`
	AvatarURL         *string    `json:"avatar_url"`
	IdentityPublicKey string     `json:"identity_public_key"`
	EmailVerified     bool       `json:"email_verified"`
	CreatedAt         time.Time  `json:"created_at"`
	UpdatedAt         time.Time  `json:"updated_at"`
}

// AdminUser 管理后台用户列表项。
type AdminUser struct {
	ID          string     `json:"id"`
	Email       string     `json:"email"`
	Username    string     `json:"username"`
	IsAdmin     bool       `json:"is_admin"`
	DisabledAt  *time.Time `json:"disabled_at,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	DeviceCount int        `json:"device_count"`
}

// UserDevice 用户自助查看的登录设备。
type UserDevice struct {
	DeviceID     string    `json:"device_id"`
	DeviceName   *string   `json:"device_name,omitempty"`
	Platform     string    `json:"platform"`
	LastActiveAt time.Time `json:"last_active_at"`
	HasSession   bool      `json:"has_session"`
	IsCurrent    bool      `json:"is_current"`
}

// AdminDevice 管理后台设备项。
type AdminDevice struct {
	DeviceID     string    `json:"device_id"`
	DeviceName   *string   `json:"device_name,omitempty"`
	Platform     string    `json:"platform"`
	LastActiveAt time.Time `json:"last_active_at"`
	HasSession   bool      `json:"has_session"` // 库中仍有 refresh_token_hash
	Online       bool      `json:"online"`
	HasPush      bool      `json:"has_push"`
	SessionState string    `json:"session_state"` // online / logged_in / idle / none
}

// AdminUserDetail 用户详情（含设备）。
type AdminUserDetail struct {
	AdminUser
	Devices []AdminDevice `json:"devices"`
}

// PublicUser 用户列表/会话成员展示（不含邮箱）。
type PublicUser struct {
	ID                string  `json:"id"`
	Username          string  `json:"username"`
	AvatarURL         *string `json:"avatar_url"`
	IdentityPublicKey string  `json:"identity_public_key"`
}

// Repository 用户与设备、重置令牌的数据库访问层。
type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) Create(ctx context.Context, email, username, passwordHash, identityPublicKey string) (*User, error) {
	row := r.pool.QueryRow(ctx, `
		INSERT INTO users (email, username, password_hash, identity_public_key)
		VALUES ($1, $2, $3, $4)
		RETURNING id, email, username, avatar_url, identity_public_key, email_verified_at, created_at, updated_at`,
		email, username, passwordHash, identityPublicKey,
	)
	u, err := scanUser(row)
	if err != nil {
		if isUniqueViolation(err) {
			// distinguish email vs username by re-query is expensive; inspect constraint name if needed
			if containsConstraint(err, "users_email_key") {
				return nil, ErrEmailTaken
			}
			if containsConstraint(err, "users_username_key") {
				return nil, ErrUsernameTaken
			}
			return nil, ErrEmailTaken
		}
		return nil, err
	}
	return u, nil
}

func (r *Repository) GetByID(ctx context.Context, id string) (*User, error) {
	row := r.pool.QueryRow(ctx, `
		SELECT id, email, username, avatar_url, identity_public_key, email_verified_at, created_at, updated_at
		FROM users WHERE id = $1`, id)
	u, err := scanUser(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return u, err
}

func (r *Repository) ExistsByID(ctx context.Context, id string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)`, id).Scan(&exists)
	return exists, err
}

// AllExistByIDs 批量校验用户是否存在；返回不存在的 id 列表。
func (r *Repository) AllExistByIDs(ctx context.Context, ids []string) ([]string, error) {
	if len(ids) == 0 {
		return nil, nil
	}
	rows, err := r.pool.Query(ctx, `SELECT id FROM users WHERE id = ANY($1)`, ids)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	found := make(map[string]struct{}, len(ids))
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		found[id] = struct{}{}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	var missing []string
	for _, id := range ids {
		if _, ok := found[id]; !ok {
			missing = append(missing, id)
		}
	}
	return missing, nil
}

// PublicNamesByIDs 批量读取展示名。
func (r *Repository) PublicNamesByIDs(ctx context.Context, ids []string) (map[string]string, error) {
	if len(ids) == 0 {
		return map[string]string{}, nil
	}
	rows, err := r.pool.Query(ctx, `SELECT id, username FROM users WHERE id = ANY($1)`, ids)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make(map[string]string, len(ids))
	for rows.Next() {
		var id, name string
		if err := rows.Scan(&id, &name); err != nil {
			return nil, err
		}
		out[id] = name
	}
	return out, rows.Err()
}

func (r *Repository) ListPublic(ctx context.Context, excludeUserID, query string, limit int) ([]PublicUser, error) {
	query = strings.TrimSpace(query)
	var rows pgx.Rows
	var err error

	if query != "" {
		pattern := "%" + query + "%"
		prefix := query + "%"
		rows, err = r.pool.Query(ctx, `
			SELECT id, username, avatar_url, identity_public_key
			FROM users
			WHERE id <> $1 AND disabled_at IS NULL
			  AND (username ILIKE $2 OR email ILIKE $2)
			ORDER BY
			  CASE
			    WHEN lower(username) = lower($3) OR lower(email) = lower($3) THEN 0
			    WHEN username ILIKE $4 OR email ILIKE $4 THEN 1
			    ELSE 2
			  END,
			  username
			LIMIT $5`, excludeUserID, pattern, query, prefix, limit)
	} else {
		rows, err = r.pool.Query(ctx, `
			SELECT id, username, avatar_url, identity_public_key
			FROM users
			WHERE id <> $1 AND disabled_at IS NULL
			ORDER BY username
			LIMIT $2`, excludeUserID, limit)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []PublicUser
	for rows.Next() {
		var u PublicUser
		if err := rows.Scan(&u.ID, &u.Username, &u.AvatarURL, &u.IdentityPublicKey); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	if users == nil {
		users = []PublicUser{}
	}
	return users, rows.Err()
}

func (r *Repository) GetByEmail(ctx context.Context, email string) (*User, string, error) {
	row := r.pool.QueryRow(ctx, `
		SELECT id, email, username, avatar_url, identity_public_key, email_verified_at, created_at, updated_at, password_hash
		FROM users WHERE email = $1`, email)
	var passwordHash string
	u, err := scanUserWithPassword(row, &passwordHash)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, "", ErrNotFound
	}
	return u, passwordHash, err
}

func (r *Repository) GetPasswordHashByID(ctx context.Context, userID string) (string, error) {
	var hash string
	err := r.pool.QueryRow(ctx, `SELECT password_hash FROM users WHERE id = $1`, userID).Scan(&hash)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	return hash, err
}

func (r *Repository) GetTokenVersion(ctx context.Context, userID string) (int, error) {
	var version int
	err := r.pool.QueryRow(ctx, `SELECT token_version FROM users WHERE id = $1`, userID).Scan(&version)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, ErrNotFound
	}
	return version, err
}

func (r *Repository) UpdateUsername(ctx context.Context, userID, username string) (*User, error) {
	row := r.pool.QueryRow(ctx, `
		UPDATE users SET username = $2, updated_at = now()
		WHERE id = $1
		RETURNING id, email, username, avatar_url, identity_public_key, email_verified_at, created_at, updated_at`,
		userID, username,
	)
	u, err := scanUser(row)
	if err != nil {
		if isUniqueViolation(err) && containsConstraint(err, "users_username_key") {
			return nil, ErrUsernameTaken
		}
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return u, nil
}

func (r *Repository) UpdateAvatarURL(ctx context.Context, userID string, avatarURL string) (*User, error) {
	row := r.pool.QueryRow(ctx, `
		UPDATE users SET avatar_url = $2, updated_at = now()
		WHERE id = $1
		RETURNING id, email, username, avatar_url, identity_public_key, email_verified_at, created_at, updated_at`,
		userID, avatarURL,
	)
	u, err := scanUser(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return u, err
}

func (r *Repository) UpdateIdentityPublicKey(ctx context.Context, userID, identityPublicKey string) (*User, error) {
	row := r.pool.QueryRow(ctx, `
		UPDATE users SET identity_public_key = $2, updated_at = now()
		WHERE id = $1
		RETURNING id, email, username, avatar_url, identity_public_key, email_verified_at, created_at, updated_at`,
		userID, identityPublicKey,
	)
	u, err := scanUser(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return u, err
}

func (r *Repository) UpdatePassword(ctx context.Context, userID, passwordHash string) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE users SET password_hash = $2, updated_at = now() WHERE id = $1`,
		userID, passwordHash,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) ClearDeviceRefreshTokens(ctx context.Context, userID string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE user_devices SET refresh_token_hash = NULL WHERE user_id = $1`, userID)
	return err
}

// ChangePasswordAndRevokeSessions 更新密码、递增 token_version，并清除全部 refresh_token。
func (r *Repository) ChangePasswordAndRevokeSessions(ctx context.Context, userID, passwordHash string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	tag, err := tx.Exec(ctx, `
		UPDATE users
		SET password_hash = $2, token_version = token_version + 1, updated_at = now()
		WHERE id = $1`, userID, passwordHash)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}

	if _, err := tx.Exec(ctx, `
		UPDATE user_devices SET refresh_token_hash = NULL WHERE user_id = $1`, userID); err != nil {
		return err
	}

	return tx.Commit(ctx)
}

func (r *Repository) UpsertDevice(ctx context.Context, userID, deviceID, deviceName, refreshTokenHash string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO user_devices (user_id, device_id, device_name, refresh_token_hash, last_active_at)
		VALUES ($1, $2, $3, $4, now())
		ON CONFLICT (user_id, device_id) DO UPDATE SET
			device_name = COALESCE(EXCLUDED.device_name, user_devices.device_name),
			refresh_token_hash = EXCLUDED.refresh_token_hash,
			last_active_at = now()`,
		userID, deviceID, nullIfEmpty(deviceName), refreshTokenHash,
	)
	return err
}

func (r *Repository) GetDeviceRefreshHash(ctx context.Context, userID, deviceID string) (string, error) {
	var hash *string
	err := r.pool.QueryRow(ctx, `
		SELECT refresh_token_hash FROM user_devices
		WHERE user_id = $1 AND device_id = $2`, userID, deviceID).Scan(&hash)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	if err != nil {
		return "", err
	}
	if hash == nil || *hash == "" {
		return "", ErrNotFound
	}
	return *hash, nil
}

// DeviceSession 设备登录态（refresh + 最后活跃时间）。
type DeviceSession struct {
	RefreshHash  string
	LastActiveAt time.Time
}

func (r *Repository) GetDeviceSession(ctx context.Context, userID, deviceID string) (*DeviceSession, error) {
	var hash *string
	var lastActive time.Time
	err := r.pool.QueryRow(ctx, `
		SELECT refresh_token_hash, last_active_at FROM user_devices
		WHERE user_id = $1 AND device_id = $2`, userID, deviceID).Scan(&hash, &lastActive)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	if hash == nil || *hash == "" {
		return nil, ErrNotFound
	}
	return &DeviceSession{RefreshHash: *hash, LastActiveAt: lastActive}, nil
}

func (r *Repository) CreatePasswordResetToken(ctx context.Context, userID, tokenHash string, expiresAt time.Time) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
		VALUES ($1, $2, $3)`, userID, tokenHash, expiresAt)
	return err
}

func (r *Repository) ConsumePasswordResetToken(ctx context.Context, tokenHash string) (string, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var userID string
	err = tx.QueryRow(ctx, `
		SELECT user_id FROM password_reset_tokens
		WHERE token_hash = $1 AND used_at IS NULL AND expires_at > now()
		FOR UPDATE`, tokenHash).Scan(&userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", errors.New("invalid or expired token")
	}
	if err != nil {
		return "", err
	}

	if _, err := tx.Exec(ctx, `
		UPDATE password_reset_tokens SET used_at = now()
		WHERE token_hash = $1`, tokenHash); err != nil {
		return "", err
	}

	if err := tx.Commit(ctx); err != nil {
		return "", err
	}
	return userID, nil
}

func (r *Repository) CreateEmailVerificationToken(ctx context.Context, userID, tokenHash string, expiresAt time.Time) error {
	_, err := r.pool.Exec(ctx, `
		DELETE FROM email_verification_tokens
		WHERE user_id = $1 AND used_at IS NULL`, userID)
	if err != nil {
		return err
	}
	_, err = r.pool.Exec(ctx, `
		INSERT INTO email_verification_tokens (user_id, token_hash, expires_at)
		VALUES ($1, $2, $3)`, userID, tokenHash, expiresAt)
	return err
}

func (r *Repository) ConsumeEmailVerificationToken(ctx context.Context, tokenHash string) (string, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var userID string
	err = tx.QueryRow(ctx, `
		SELECT user_id FROM email_verification_tokens
		WHERE token_hash = $1 AND used_at IS NULL AND expires_at > now()
		FOR UPDATE`, tokenHash).Scan(&userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", errors.New("invalid or expired token")
	}
	if err != nil {
		return "", err
	}

	if _, err := tx.Exec(ctx, `
		UPDATE email_verification_tokens SET used_at = now()
		WHERE token_hash = $1`, tokenHash); err != nil {
		return "", err
	}
	if _, err := tx.Exec(ctx, `
		UPDATE users SET email_verified_at = now(), updated_at = now()
		WHERE id = $1 AND email_verified_at IS NULL`, userID); err != nil {
		return "", err
	}

	if err := tx.Commit(ctx); err != nil {
		return "", err
	}
	return userID, nil
}

func (r *Repository) IsEmailVerified(ctx context.Context, userID string) (bool, error) {
	var verifiedAt *time.Time
	err := r.pool.QueryRow(ctx, `
		SELECT email_verified_at FROM users WHERE id = $1`, userID).Scan(&verifiedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, ErrNotFound
	}
	if err != nil {
		return false, err
	}
	return verifiedAt != nil, nil
}

type scannable interface {
	Scan(dest ...any) error
}

func scanUser(row scannable) (*User, error) {
	var u User
	var verifiedAt *time.Time
	err := row.Scan(&u.ID, &u.Email, &u.Username, &u.AvatarURL, &u.IdentityPublicKey, &verifiedAt, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		return nil, err
	}
	u.EmailVerified = verifiedAt != nil
	return &u, nil
}

func scanUserWithPassword(row scannable, passwordHash *string) (*User, error) {
	var u User
	var verifiedAt *time.Time
	err := row.Scan(&u.ID, &u.Email, &u.Username, &u.AvatarURL, &u.IdentityPublicKey, &verifiedAt, &u.CreatedAt, &u.UpdatedAt, passwordHash)
	if err != nil {
		return nil, err
	}
	u.EmailVerified = verifiedAt != nil
	return &u, nil
}

func (r *Repository) FindUserIDByDeviceRefresh(ctx context.Context, deviceID, tokenHash string) (string, error) {
	var userID string
	err := r.pool.QueryRow(ctx, `
		SELECT user_id FROM user_devices
		WHERE device_id = $1 AND refresh_token_hash = $2`, deviceID, tokenHash).Scan(&userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	return userID, err
}

// PushTarget 带 push token 的设备。
type PushTarget struct {
	DeviceID  string
	PushToken string
	Platform  string
}

func (r *Repository) UpdatePushToken(
	ctx context.Context,
	userID, deviceID, pushToken, platform string,
) error {
	pushToken = strings.TrimSpace(pushToken)
	platform = strings.TrimSpace(platform)
	if deviceID == "" {
		return errors.New("device_id required")
	}
	if pushToken == "" {
		_, err := r.pool.Exec(ctx, `
			UPDATE user_devices
			SET push_token = NULL, platform = NULL, last_active_at = now()
			WHERE user_id = $1 AND device_id = $2`, userID, deviceID)
		return err
	}
	_, err := r.pool.Exec(ctx, `
		INSERT INTO user_devices (user_id, device_id, push_token, platform, last_active_at)
		VALUES ($1, $2, $3, $4, now())
		ON CONFLICT (user_id, device_id) DO UPDATE SET
			push_token = EXCLUDED.push_token,
			platform = COALESCE(EXCLUDED.platform, user_devices.platform),
			last_active_at = now()`,
		userID, deviceID, pushToken, nullIfEmpty(platform),
	)
	return err
}

func (r *Repository) ListPushTargets(ctx context.Context, userID string) ([]PushTarget, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT device_id, push_token, COALESCE(platform, '')
		FROM user_devices
		WHERE user_id = $1
		  AND push_token IS NOT NULL
		  AND push_token <> ''`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []PushTarget
	for rows.Next() {
		var t PushTarget
		if err := rows.Scan(&t.DeviceID, &t.PushToken, &t.Platform); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

func (r *Repository) IsAdmin(ctx context.Context, userID string) (bool, error) {
	var isAdmin bool
	err := r.pool.QueryRow(ctx, `SELECT is_admin FROM users WHERE id = $1`, userID).Scan(&isAdmin)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, ErrNotFound
	}
	return isAdmin, err
}

func (r *Repository) IsUserDisabled(ctx context.Context, userID string) (bool, error) {
	var disabledAt *time.Time
	err := r.pool.QueryRow(ctx, `SELECT disabled_at FROM users WHERE id = $1`, userID).Scan(&disabledAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, ErrNotFound
	}
	return disabledAt != nil, err
}

func (r *Repository) SyncAdminByEmail(ctx context.Context, userID, email string, adminEmails []string) error {
	want := false
	email = strings.ToLower(strings.TrimSpace(email))
	for _, e := range adminEmails {
		if email == strings.ToLower(strings.TrimSpace(e)) {
			want = true
			break
		}
	}
	_, err := r.pool.Exec(ctx, `UPDATE users SET is_admin = $2, updated_at = now() WHERE id = $1`, userID, want)
	return err
}

func (r *Repository) Ping(ctx context.Context) error {
	return r.pool.Ping(ctx)
}

func (r *Repository) AdminCounts(ctx context.Context) (total, disabled int, err error) {
	err = r.pool.QueryRow(ctx, `
		SELECT
			(SELECT COUNT(*) FROM users),
			(SELECT COUNT(*) FROM users WHERE disabled_at IS NOT NULL)`).Scan(&total, &disabled)
	return total, disabled, err
}

func (r *Repository) CountForAdmin(ctx context.Context, query string) (int, error) {
	query = strings.TrimSpace(query)
	var total int
	var err error
	if query == "" {
		err = r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM users`).Scan(&total)
	} else {
		pattern := "%" + query + "%"
		err = r.pool.QueryRow(ctx, `
			SELECT COUNT(*) FROM users
			WHERE email ILIKE $1 OR username ILIKE $1`, pattern).Scan(&total)
	}
	return total, err
}

func (r *Repository) ListForAdmin(ctx context.Context, query string, limit, offset int, sortBy, sortOrder string) ([]AdminUser, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}
	query = strings.TrimSpace(query)
	orderSQL := adminOrderClause(sortBy, sortOrder)
	var rows pgx.Rows
	var err error
	if query == "" {
		rows, err = r.pool.Query(ctx, `
			SELECT u.id, u.email, u.username, u.is_admin, u.disabled_at, u.created_at,
				COALESCE(d.cnt, 0)
			FROM users u
			LEFT JOIN (
				SELECT user_id, COUNT(*) AS cnt FROM user_devices GROUP BY user_id
			) d ON d.user_id = u.id
			`+orderSQL+`
			LIMIT $1 OFFSET $2`, limit, offset)
	} else {
		pattern := "%" + query + "%"
		rows, err = r.pool.Query(ctx, `
			SELECT u.id, u.email, u.username, u.is_admin, u.disabled_at, u.created_at,
				COALESCE(d.cnt, 0)
			FROM users u
			LEFT JOIN (
				SELECT user_id, COUNT(*) AS cnt FROM user_devices GROUP BY user_id
			) d ON d.user_id = u.id
			WHERE u.email ILIKE $1 OR u.username ILIKE $1
			`+orderSQL+`
			LIMIT $2 OFFSET $3`, pattern, limit, offset)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []AdminUser
	for rows.Next() {
		var u AdminUser
		if err := rows.Scan(&u.ID, &u.Email, &u.Username, &u.IsAdmin, &u.DisabledAt, &u.CreatedAt, &u.DeviceCount); err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

func adminOrderClause(sortBy, sortOrder string) string {
	col := "u.username"
	switch sortBy {
	case "email":
		col = "u.email"
	case "created_at":
		col = "u.created_at"
	case "device_count":
		col = "COALESCE(d.cnt, 0)"
	default:
		sortBy = "username"
	}
	dir := "ASC"
	if strings.EqualFold(strings.TrimSpace(sortOrder), "desc") {
		dir = "DESC"
	}
	tie := ", u.email ASC"
	if sortBy == "email" {
		tie = ", u.username ASC"
	} else if sortBy == "created_at" {
		tie = ", u.username ASC"
	} else if sortBy == "device_count" {
		tie = ", u.username ASC"
	}
	return "ORDER BY " + col + " " + dir + tie
}

func (r *Repository) GetForAdmin(ctx context.Context, userID string) (*AdminUserDetail, error) {
	var u AdminUser
	err := r.pool.QueryRow(ctx, `
		SELECT u.id, u.email, u.username, u.is_admin, u.disabled_at, u.created_at,
			COALESCE(d.cnt, 0)
		FROM users u
		LEFT JOIN (
			SELECT user_id, COUNT(*) AS cnt FROM user_devices GROUP BY user_id
		) d ON d.user_id = u.id
		WHERE u.id = $1`, userID).Scan(
		&u.ID, &u.Email, &u.Username, &u.IsAdmin, &u.DisabledAt, &u.CreatedAt, &u.DeviceCount,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	devices, err := r.ListDevicesForAdmin(ctx, userID)
	if err != nil {
		return nil, err
	}
	return &AdminUserDetail{AdminUser: u, Devices: devices}, nil
}

func (r *Repository) ListDevicesForUser(ctx context.Context, userID string) ([]UserDevice, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT device_id, device_name, COALESCE(platform, ''), last_active_at,
			(refresh_token_hash IS NOT NULL AND refresh_token_hash <> '')
		FROM user_devices
		WHERE user_id = $1
		ORDER BY last_active_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []UserDevice
	for rows.Next() {
		var d UserDevice
		if err := rows.Scan(&d.DeviceID, &d.DeviceName, &d.Platform, &d.LastActiveAt, &d.HasSession); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

func (r *Repository) ListDevicesForAdmin(ctx context.Context, userID string) ([]AdminDevice, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT device_id, device_name, COALESCE(platform, ''), last_active_at,
			(refresh_token_hash IS NOT NULL AND refresh_token_hash <> ''),
			(push_token IS NOT NULL AND push_token <> '')
		FROM user_devices
		WHERE user_id = $1
		ORDER BY last_active_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []AdminDevice
	for rows.Next() {
		var d AdminDevice
		if err := rows.Scan(&d.DeviceID, &d.DeviceName, &d.Platform, &d.LastActiveAt, &d.HasSession, &d.HasPush); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

func (r *Repository) KickDevice(ctx context.Context, userID, deviceID string) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE user_devices SET refresh_token_hash = NULL
		WHERE user_id = $1 AND device_id = $2`, userID, deviceID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) AdminPushStats(ctx context.Context) (int, map[string]int, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT COALESCE(NULLIF(platform, ''), 'unknown'), COUNT(*)
		FROM user_devices
		WHERE push_token IS NOT NULL AND push_token <> ''
		GROUP BY 1`)
	if err != nil {
		return 0, nil, err
	}
	defer rows.Close()
	byPlatform := make(map[string]int)
	total := 0
	for rows.Next() {
		var platform string
		var n int
		if err := rows.Scan(&platform, &n); err != nil {
			return 0, nil, err
		}
		byPlatform[platform] = n
		total += n
	}
	return total, byPlatform, rows.Err()
}

func (r *Repository) DisableUser(ctx context.Context, userID string) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE users
		SET disabled_at = now(), token_version = token_version + 1, updated_at = now()
		WHERE id = $1 AND disabled_at IS NULL`, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		var exists bool
		_ = r.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)`, userID).Scan(&exists)
		if !exists {
			return ErrNotFound
		}
	}
	_, err = r.pool.Exec(ctx, `UPDATE user_devices SET refresh_token_hash = NULL WHERE user_id = $1`, userID)
	return err
}

func (r *Repository) EnableUser(ctx context.Context, userID string) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE users SET disabled_at = NULL, updated_at = now()
		WHERE id = $1`, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.Code == "23505"
	}
	return false
}

func containsConstraint(err error, name string) bool {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.ConstraintName == name
	}
	return false
}

func nullIfEmpty(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
