package handlers

import (
	"log"
	"net/http"
	"strings"

	"jnv/backend/internal/auth"
	"jnv/backend/internal/models"
	"jnv/backend/internal/store"
)

type AuthHandler struct {
	Store        *store.Store
	AuthProvider auth.Provider
}

type authSessionResponse struct {
	User models.User `json:"user"`
}

func (h AuthHandler) Session(w http.ResponseWriter, r *http.Request) {
	token := bearerToken(r.Header.Get("Authorization"))
	if token == "" {
		writeError(w, http.StatusUnauthorized, "missing token")
		return
	}

	claims, err := h.AuthProvider.Verify(r.Context(), token)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "invalid token")
		return
	}
	principal := sessionPrincipalFromClaims(claims)
	log.Printf("[session] token verified principal=%s role=%s", principal, claims.Role)
	if principal == "" {
		writeError(w, http.StatusBadRequest, "identity missing in token")
		return
	}

	user, err := h.Store.GetUserByPhone(r.Context(), principal)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to fetch user")
		return
	}

	if user == nil {
		role := claimsRoleOrParent(claims.Role)
		fullName := strings.TrimSpace(claims.Name)
		if fullName == "" {
			fullName = "User"
		}

		created, err := h.Store.CreateUser(r.Context(), models.User{
			Role:     role,
			FullName: fullName,
			Phone:    principal,
			Email:    claims.Email,
		})
		if err != nil {
			writeError(w, http.StatusInternalServerError, "failed to create user")
			return
		}
		log.Printf("[session] created user id=%s role=%s principal=%s", created.ID, created.Role, created.Phone)
		auditLog(r.Context(), "auth.session.created_user", created, map[string]interface{}{})
		writeJSON(w, http.StatusOK, authSessionResponse{User: *created})
		return
	}

	auditLog(r.Context(), "auth.session.login", user, map[string]interface{}{})
	writeJSON(w, http.StatusOK, authSessionResponse{User: *user})
}

func bearerToken(value string) string {
	const prefix = "Bearer "
	if len(value) <= len(prefix) || value[:len(prefix)] != prefix {
		return ""
	}
	return value[len(prefix):]
}

func claimsRoleOrParent(value string) models.Role {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case string(models.RoleSuperAdmin):
		return models.RoleSuperAdmin
	case string(models.RoleAdmin):
		return models.RoleAdmin
	case string(models.RoleStaff):
		return models.RoleStaff
	case string(models.RoleTeacher):
		return models.RoleTeacher
	default:
		return models.RoleParent
	}
}

func sessionPrincipalFromClaims(claims auth.Claims) string {
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
