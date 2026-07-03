package filestore

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("file not found")

type File struct {
	ID             string    `json:"id"`
	ConversationID string    `json:"conversation_id"`
	UploaderID     string    `json:"uploader_id"`
	StoragePath    string    `json:"-"`
	ByteSize       int64     `json:"byte_size"`
	CreatedAt      time.Time `json:"created_at"`
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) Create(
	ctx context.Context,
	conversationID, uploaderID, storagePath string,
	byteSize int64,
) (*File, error) {
	row := r.pool.QueryRow(ctx, `
		INSERT INTO encrypted_files (conversation_id, uploader_id, storage_path, byte_size)
		VALUES ($1, $2, $3, $4)
		RETURNING id, conversation_id, uploader_id, storage_path, byte_size, created_at`,
		conversationID, uploaderID, storagePath, byteSize,
	)
	return scanFile(row)
}

func (r *Repository) GetByID(ctx context.Context, id string) (*File, error) {
	row := r.pool.QueryRow(ctx, `
		SELECT id, conversation_id, uploader_id, storage_path, byte_size, created_at
		FROM encrypted_files WHERE id = $1`, id)
	f, err := scanFile(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return f, err
}

type scannable interface {
	Scan(dest ...any) error
}

func scanFile(row scannable) (*File, error) {
	var f File
	err := row.Scan(&f.ID, &f.ConversationID, &f.UploaderID, &f.StoragePath, &f.ByteSize, &f.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &f, nil
}
