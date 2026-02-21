//go:build !firebase
// +build !firebase

package notify

import (
	"context"

	"jnv/backend/internal/store"
)

func NewFirebaseSender(_ context.Context, _ string, _ *store.Store) (Sender, error) {
	return NoopSender{}, nil
}
