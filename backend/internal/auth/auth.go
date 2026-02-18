package auth

import "context"

type Claims struct {
	UID   string
	Phone string
	Email string
	Name  string
	Role  string
}

type Provider interface {
	Verify(ctx context.Context, token string) (Claims, error)
}
