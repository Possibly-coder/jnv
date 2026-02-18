package httpctx

import (
	"context"

	"jnv/backend/internal/auth"
	"jnv/backend/internal/models"
)

type ctxKey string

const (
	userKey   ctxKey = "user"
	claimsKey ctxKey = "claims"
)

func WithUser(ctx context.Context, user *models.User) context.Context {
	return context.WithValue(ctx, userKey, user)
}

func WithClaims(ctx context.Context, claims auth.Claims) context.Context {
	return context.WithValue(ctx, claimsKey, claims)
}

func UserFromContext(ctx context.Context) *models.User {
	if val := ctx.Value(userKey); val != nil {
		if user, ok := val.(*models.User); ok {
			return user
		}
	}
	return nil
}

func ClaimsFromContext(ctx context.Context) *auth.Claims {
	if val := ctx.Value(claimsKey); val != nil {
		if claims, ok := val.(auth.Claims); ok {
			return &claims
		}
	}
	return nil
}
