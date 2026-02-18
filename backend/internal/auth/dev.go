package auth

import (
	"context"
	"errors"
	"strings"
)

type DevProvider struct {
	DefaultPhone string
}

func (d DevProvider) Verify(_ context.Context, token string) (Claims, error) {
	if token == "" {
		return Claims{}, errors.New("missing token")
	}

	// Format: dev:<phone>:<role>
	if strings.HasPrefix(token, "dev:") {
		parts := strings.Split(token, ":")
		claims := Claims{
			UID:   "dev-user",
			Phone: d.DefaultPhone,
			Role:  "parent",
		}

		if len(parts) >= 2 && parts[1] != "" {
			claims.Phone = parts[1]
		}
		if len(parts) >= 3 && parts[2] != "" {
			claims.Role = parts[2]
		}
		return claims, nil
	}

	return Claims{}, errors.New("invalid dev token")
}
