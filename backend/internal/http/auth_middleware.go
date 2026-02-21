package httpapi

import (
	"context"
	"log"
	"net/http"
	"strings"

	"jnv/backend/internal/auth"
	"jnv/backend/internal/httpctx"
	"jnv/backend/internal/models"
	"jnv/backend/internal/store"
)

func RequireAuth(authProvider auth.Provider, store *store.Store) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			log.Printf("[auth] %s %s", r.Method, r.URL.Path)
			token := bearerToken(r.Header.Get("Authorization"))
			if token == "" {
				log.Printf("[auth] missing bearer token")
				http.Error(w, "missing token", http.StatusUnauthorized)
				return
			}

			claims, err := authProvider.Verify(r.Context(), token)
			if err != nil {
				log.Printf("[auth] token verify failed: %v", err)
				http.Error(w, "invalid token", http.StatusUnauthorized)
				return
			}

			principal := principalFromClaims(claims)
			if principal == "" {
				log.Printf("[auth] token missing principal")
				http.Error(w, "missing identity", http.StatusUnauthorized)
				return
			}
			log.Printf("[auth] claims principal=%s role=%s", principal, claims.Role)

			user, err := store.GetUserByPhone(r.Context(), principal)
			if err != nil {
				log.Printf("[auth] user lookup failed for principal=%s err=%v", principal, err)
				http.Error(w, "failed to load user", http.StatusInternalServerError)
				return
			}
			if user == nil {
				role := toRole(claims.Role)
				if role == "" {
					role = models.RoleParent
				}
				fullName := strings.TrimSpace(claims.Name)
				if fullName == "" {
					fullName = "User"
				}

				schoolID, schoolErr := store.FirstSchoolID(r.Context())
				if schoolErr != nil {
					log.Printf("[auth] first school lookup failed: %v", schoolErr)
					http.Error(w, "failed to bootstrap user", http.StatusInternalServerError)
					return
				}

				created, createErr := store.CreateUser(r.Context(), models.User{
					Role:     role,
					FullName: fullName,
					Phone:    principal,
					Email:    claims.Email,
					SchoolID: schoolID,
				})
				if createErr != nil {
					log.Printf("[auth] user auto-create failed for principal=%s err=%v", principal, createErr)
					http.Error(w, "failed to create user", http.StatusInternalServerError)
					return
				}
				user = created
				log.Printf("[auth] auto-created user id=%s role=%s school_id=%s", user.ID, user.Role, user.SchoolID)
			}

			ctx := httpctx.WithUser(r.Context(), user)
			ctx = httpctx.WithClaims(ctx, claims)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func toRole(value string) models.Role {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case string(models.RoleSuperAdmin):
		return models.RoleSuperAdmin
	case string(models.RoleAdmin):
		return models.RoleAdmin
	case string(models.RoleStaff):
		return models.RoleStaff
	case string(models.RoleTeacher):
		return models.RoleTeacher
	case string(models.RoleParent):
		return models.RoleParent
	default:
		return ""
	}
}

func UserFromContext(ctx context.Context) *models.User {
	return httpctx.UserFromContext(ctx)
}

func ClaimsFromContext(ctx context.Context) *auth.Claims {
	return httpctx.ClaimsFromContext(ctx)
}

func bearerToken(value string) string {
	const prefix = "Bearer "
	if len(value) <= len(prefix) || value[:len(prefix)] != prefix {
		return ""
	}
	return value[len(prefix):]
}

func principalFromClaims(claims auth.Claims) string {
	if phone := strings.TrimSpace(claims.Phone); phone != "" {
		return phone
	}
	if email := strings.ToLower(strings.TrimSpace(claims.Email)); email != "" {
		return "email:" + email
	}
	if uid := strings.TrimSpace(claims.UID); uid != "" {
		return "uid:" + uid
	}
	return ""
}
