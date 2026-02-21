package handlers

import (
	"net/http"
	"strings"

	"jnv/backend/internal/httpctx"
	"jnv/backend/internal/store"
)

type DevicesHandler struct {
	Store *store.Store
}

type registerDeviceTokenRequest struct {
	Token    string `json:"token"`
	Platform string `json:"platform"`
}

func (h DevicesHandler) RegisterToken(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req registerDeviceTokenRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request")
		return
	}
	req.Token = strings.TrimSpace(req.Token)
	req.Platform = strings.TrimSpace(req.Platform)
	if req.Token == "" {
		writeError(w, http.StatusBadRequest, "token is required")
		return
	}
	if req.Platform == "" {
		req.Platform = "android"
	}
	if err := h.Store.UpsertDeviceToken(r.Context(), user.ID, req.Token, req.Platform); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to register token")
		return
	}
	auditLog(r.Context(), "device.token.registered", user, map[string]interface{}{
		"platform": req.Platform,
	})
	writeJSON(w, http.StatusOK, map[string]string{"status": "registered"})
}
