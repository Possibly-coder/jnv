package handlers

import (
	"net/http"
	"strings"

	"jnv/backend/internal/httpctx"
	"jnv/backend/internal/models"
	"jnv/backend/internal/store"
)

type UsersHandler struct {
	Store *store.Store
}

type updateUserRoleRequest struct {
	Role string `json:"role"`
}

func (h UsersHandler) List(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !hasRole(user, models.RoleAdmin, models.RoleSuperAdmin) {
		writeError(w, http.StatusForbidden, "admin required")
		return
	}
	items, err := h.Store.ListUsersBySchool(r.Context(), user.SchoolID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load users")
		return
	}
	writeJSON(w, http.StatusOK, items)
}

func (h UsersHandler) UpdateRole(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !hasRole(user, models.RoleAdmin, models.RoleSuperAdmin) {
		writeError(w, http.StatusForbidden, "admin required")
		return
	}
	targetUserID := r.PathValue("id")
	if strings.TrimSpace(targetUserID) == "" {
		writeError(w, http.StatusBadRequest, "missing id")
		return
	}
	var req updateUserRoleRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request")
		return
	}
	role := models.Role(strings.ToLower(strings.TrimSpace(req.Role)))
	switch role {
	case models.RoleParent, models.RoleTeacher, models.RoleStaff, models.RoleAdmin:
	default:
		writeError(w, http.StatusBadRequest, "unsupported role")
		return
	}
	if err := h.Store.UpdateUserRole(r.Context(), targetUserID, role); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to update role")
		return
	}
	auditLog(r.Context(), "user.role.updated", user, map[string]interface{}{
		"target_user_id": targetUserID,
		"new_role":       role,
	})
	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}
