//go:build firebase
// +build firebase

package notify

import (
	"context"
	"strings"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"

	"jnv/backend/internal/models"
	"jnv/backend/internal/store"
)

type FirebaseSender struct {
	store  *store.Store
	client *messaging.Client
}

func NewFirebaseSender(ctx context.Context, credentialsFile string, s *store.Store) (Sender, error) {
	if strings.TrimSpace(credentialsFile) == "" {
		return NoopSender{}, nil
	}
	app, err := firebase.NewApp(ctx, nil, option.WithCredentialsFile(credentialsFile))
	if err != nil {
		return nil, err
	}
	client, err := app.Messaging(ctx)
	if err != nil {
		return nil, err
	}
	return &FirebaseSender{store: s, client: client}, nil
}

func (s *FirebaseSender) SendToSchoolParents(ctx context.Context, schoolID, title, body string, data map[string]string) error {
	if s == nil || s.client == nil || s.store == nil {
		return nil
	}
	tokens, err := s.store.ListDeviceTokensBySchoolRole(ctx, schoolID, models.RoleParent)
	if err != nil {
		return err
	}
	if len(tokens) == 0 {
		return nil
	}
	msg := &messaging.MulticastMessage{
		Tokens: tokens,
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data: data,
	}
	var lastErr error
	backoff := 300 * time.Millisecond
	for attempt := 1; attempt <= 3; attempt++ {
		_, err = s.client.SendEachForMulticast(ctx, msg)
		if err == nil {
			return nil
		}
		lastErr = err
		if attempt < 3 {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(backoff):
			}
			backoff *= 2
		}
	}
	return lastErr
}
