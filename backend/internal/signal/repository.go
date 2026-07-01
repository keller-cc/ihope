package signal

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrNoDevice       = errors.New("signal device not found")
	ErrNoPreKey       = errors.New("no one-time prekey available")
	ErrInvalidPayload = errors.New("invalid signal key payload")
)

type DeviceState struct {
	UserID            string
	DeviceID          string
	SignalDeviceID    int
	RegistrationID    int
	IdentityKeyPub    []byte
	SignedPreKeyID    int
	SignedPreKeyPub   []byte
	SignedPreKeySig   []byte
	UpdatedAt         time.Time
}

type OneTimePreKey struct {
	PreKeyID  int
	PublicKey []byte
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) UpsertDeviceState(ctx context.Context, s DeviceState) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO device_signal_state (
			user_id, device_id, signal_device_id, registration_id,
			identity_key_pub, signed_pre_key_id, signed_pre_key_pub, signed_pre_key_sig,
			updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,now())
		ON CONFLICT (user_id, device_id) DO UPDATE SET
			signal_device_id = EXCLUDED.signal_device_id,
			registration_id = EXCLUDED.registration_id,
			identity_key_pub = EXCLUDED.identity_key_pub,
			signed_pre_key_id = EXCLUDED.signed_pre_key_id,
			signed_pre_key_pub = EXCLUDED.signed_pre_key_pub,
			signed_pre_key_sig = EXCLUDED.signed_pre_key_sig,
			updated_at = now()`,
		s.UserID, s.DeviceID, s.SignalDeviceID, s.RegistrationID,
		s.IdentityKeyPub, s.SignedPreKeyID, s.SignedPreKeyPub, s.SignedPreKeySig,
	)
	return err
}

func (r *Repository) ReplaceOneTimePreKeys(
	ctx context.Context,
	userID, deviceID string,
	keys []OneTimePreKey,
) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, `
		DELETE FROM one_time_prekeys
		WHERE user_id = $1 AND device_id = $2 AND consumed_at IS NULL`,
		userID, deviceID); err != nil {
		return err
	}

	for _, k := range keys {
		if _, err := tx.Exec(ctx, `
			INSERT INTO one_time_prekeys (user_id, device_id, pre_key_id, public_key)
			VALUES ($1,$2,$3,$4)
			ON CONFLICT (user_id, device_id, pre_key_id) DO UPDATE SET
				public_key = EXCLUDED.public_key,
				consumed_at = NULL,
				created_at = now()`,
			userID, deviceID, k.PreKeyID, k.PublicKey); err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

func (r *Repository) ListDevices(ctx context.Context, userID string) ([]DeviceState, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT user_id, device_id, signal_device_id, registration_id,
		       identity_key_pub, signed_pre_key_id, signed_pre_key_pub, signed_pre_key_sig,
		       updated_at
		FROM device_signal_state
		WHERE user_id = $1
		ORDER BY updated_at DESC`,
		userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []DeviceState
	for rows.Next() {
		var s DeviceState
		if err := rows.Scan(
			&s.UserID, &s.DeviceID, &s.SignalDeviceID, &s.RegistrationID,
			&s.IdentityKeyPub, &s.SignedPreKeyID, &s.SignedPreKeyPub, &s.SignedPreKeySig,
			&s.UpdatedAt,
		); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	if out == nil {
		out = []DeviceState{}
	}
	return out, rows.Err()
}

func (r *Repository) GetDevice(ctx context.Context, userID, deviceID string) (*DeviceState, error) {
	var s DeviceState
	err := r.pool.QueryRow(ctx, `
		SELECT user_id, device_id, signal_device_id, registration_id,
		       identity_key_pub, signed_pre_key_id, signed_pre_key_pub, signed_pre_key_sig,
		       updated_at
		FROM device_signal_state
		WHERE user_id = $1 AND device_id = $2`,
		userID, deviceID).Scan(
		&s.UserID, &s.DeviceID, &s.SignalDeviceID, &s.RegistrationID,
		&s.IdentityKeyPub, &s.SignedPreKeyID, &s.SignedPreKeyPub, &s.SignedPreKeySig,
		&s.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNoDevice
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}

func (r *Repository) ConsumeOneTimePreKey(
	ctx context.Context,
	userID, deviceID string,
) (*OneTimePreKey, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var preKeyID int
	var pub []byte
	err = tx.QueryRow(ctx, `
		SELECT pre_key_id, public_key
		FROM one_time_prekeys
		WHERE user_id = $1 AND device_id = $2 AND consumed_at IS NULL
		ORDER BY pre_key_id
		FOR UPDATE SKIP LOCKED
		LIMIT 1`,
		userID, deviceID).Scan(&preKeyID, &pub)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNoPreKey
	}
	if err != nil {
		return nil, err
	}

	if _, err := tx.Exec(ctx, `
		UPDATE one_time_prekeys SET consumed_at = now()
		WHERE user_id = $1 AND device_id = $2 AND pre_key_id = $3`,
		userID, deviceID, preKeyID); err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &OneTimePreKey{PreKeyID: preKeyID, PublicKey: pub}, nil
}

func (r *Repository) CountAvailablePreKeys(ctx context.Context, userID, deviceID string) (int, error) {
	var n int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*)::int FROM one_time_prekeys
		WHERE user_id = $1 AND device_id = $2 AND consumed_at IS NULL`,
		userID, deviceID).Scan(&n)
	return n, err
}
