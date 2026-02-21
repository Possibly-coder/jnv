package handlers

import (
	"net/http"
	"strconv"

	"jnv/backend/internal/httpctx"
	"jnv/backend/internal/models"
	"jnv/backend/internal/store"
)

type AuditLogsHandler struct {
	Store *store.Store
}

func (h AuditLogsHandler) List(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !hasRole(user, models.RoleAdmin, models.RoleSuperAdmin) {
		writeError(w, http.StatusForbidden, "admin required")
		return
	}
	limit := 100
	if raw := r.URL.Query().Get("limit"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil {
			limit = parsed
		}
	}
	items, err := h.Store.ListAuditEventsBySchool(r.Context(), user.SchoolID, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load audit logs")
		return
	}
	writeJSON(w, http.StatusOK, items)
}
