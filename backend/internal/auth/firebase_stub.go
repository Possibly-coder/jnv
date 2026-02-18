//go:build !firebase
// +build !firebase

package auth

import (
	"context"
	"errors"
)

func NewFirebaseProvider(_ context.Context, _ string) (Provider, error) {
	return nil, errors.New("firebase provider unavailable in this build; compile backend with -tags firebase")
}
