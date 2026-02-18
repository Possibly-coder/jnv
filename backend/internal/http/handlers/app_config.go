package handlers

import (
	"net/http"

	"jnv/backend/internal/httpctx"
	"jnv/backend/internal/models"
	"jnv/backend/internal/store"
)

type AppConfigHandler struct {
	Store *store.Store
}

type upsertAppConfigRequest struct {
	FeatureFlags     map[string]bool          `json:"feature_flags"`
	DashboardWidgets []models.DashboardWidget `json:"dashboard_widgets"`
}

func (h AppConfigHandler) Get(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	config, err := h.Store.GetAppConfig(r.Context(), user.SchoolID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load config")
		return
	}
	writeJSON(w, http.StatusOK, config)
}

func (h AppConfigHandler) Upsert(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !hasRole(user, models.RoleAdmin, models.RoleStaff) {
		writeError(w, http.StatusForbidden, "insufficient permissions")
		return
	}
	var req upsertAppConfigRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request")
		return
	}
	if req.FeatureFlags == nil {
		req.FeatureFlags = map[string]bool{}
	}
	if req.DashboardWidgets == nil {
		req.DashboardWidgets = []models.DashboardWidget{}
	}
	if err := h.Store.UpsertAppConfig(r.Context(), models.AppConfig{
		SchoolID:         user.SchoolID,
		FeatureFlags:     req.FeatureFlags,
		DashboardWidgets: req.DashboardWidgets,
		UpdatedBy:        user.ID,
	}); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to save config")
		return
	}
	config, err := h.Store.GetAppConfig(r.Context(), user.SchoolID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "saved but failed to reload config")
		return
	}
	writeJSON(w, http.StatusOK, config)
}
