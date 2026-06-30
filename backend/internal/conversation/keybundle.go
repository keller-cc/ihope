package conversation

import (
	"context"
	"strings"

	"github.com/jackc/pgx/v5"
)

type KeyBundle struct {
	Epoch      int    `json:"epoch"`
	SenderID   string `json:"sender_id"`
	Ciphertext string `json:"ciphertext"`
}

type KeyBundleInput struct {
	Epoch           int
	RecipientUserID string
	Ciphertext      string
}

func (r *Repository) UpsertKeyBundle(
	ctx context.Context,
	conversationID, senderID, recipientID string,
	epoch int,
	ciphertext string,
) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO group_key_bundles
			(conversation_id, epoch, recipient_user_id, sender_user_id, ciphertext)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (conversation_id, epoch, recipient_user_id)
		DO UPDATE SET
			sender_user_id = EXCLUDED.sender_user_id,
			ciphertext = EXCLUDED.ciphertext,
			created_at = now()`,
		conversationID, epoch, recipientID, senderID, ciphertext,
	)
	return err
}

func (r *Repository) ListKeyBundlesForRecipient(
	ctx context.Context,
	conversationID, recipientID string,
	epochs []int,
) ([]KeyBundle, error) {
	var rows pgx.Rows
	var err error

	if len(epochs) > 0 {
		rows, err = r.pool.Query(ctx, `
			SELECT epoch, sender_user_id, ciphertext
			FROM group_key_bundles
			WHERE conversation_id = $1
			  AND recipient_user_id = $2
			  AND epoch = ANY($3)
			ORDER BY epoch`,
			conversationID, recipientID, epochs,
		)
	} else {
		rows, err = r.pool.Query(ctx, `
			SELECT epoch, sender_user_id, ciphertext
			FROM group_key_bundles
			WHERE conversation_id = $1 AND recipient_user_id = $2
			ORDER BY epoch`,
			conversationID, recipientID,
		)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var bundles []KeyBundle
	for rows.Next() {
		var b KeyBundle
		if err := rows.Scan(&b.Epoch, &b.SenderID, &b.Ciphertext); err != nil {
			return nil, err
		}
		bundles = append(bundles, b)
	}
	if bundles == nil {
		bundles = []KeyBundle{}
	}
	return bundles, rows.Err()
}

func validWelcomeCiphertext(s string) bool {
	s = strings.TrimSpace(s)
	return strings.HasPrefix(s, "e2ee:gw:v1:")
}
