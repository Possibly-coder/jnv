//go:build firebase
// +build firebase

package auth

import (
	"context"
	"errors"
	"strings"

	firebase "firebase.google.com/go/v4"
	firebaseauth "firebase.google.com/go/v4/auth"
	"google.golang.org/api/option"
)

type FirebaseProvider struct {
	client *firebaseauth.Client
}

func NewFirebaseProvider(ctx context.Context, credentialsFile string) (Provider, error) {
	if strings.TrimSpace(credentialsFile) == "" {
		return nil, errors.New("firebase credentials file is required")
	}

	app, err := firebase.NewApp(ctx, nil, option.WithCredentialsFile(credentialsFile))
	if err != nil {
		return nil, err
	}

	client, err := app.Auth(ctx)
	if err != nil {
		return nil, err
	}

	return &FirebaseProvider{client: client}, nil
}

func (p *FirebaseProvider) Verify(ctx context.Context, token string) (Claims, error) {
	verified, err := p.client.VerifyIDToken(ctx, token)
	if err != nil {
		return Claims{}, err
	}

	claims := Claims{
		UID: verified.UID,
	}

	if phone, ok := verified.Claims["phone_number"].(string); ok {
		claims.Phone = phone
	}
	if email, ok := verified.Claims["email"].(string); ok {
		claims.Email = email
	}
	if name, ok := verified.Claims["name"].(string); ok {
		claims.Name = name
	}
	if role, ok := verified.Claims["role"].(string); ok {
		claims.Role = role
	}

	return claims, nil
}
