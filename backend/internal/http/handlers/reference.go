package handlers

import (
	"net/http"

	"jnv/backend/internal/store"
)

type ReferenceHandler struct {
	Store *store.Store
}

func (h ReferenceHandler) Districts(w http.ResponseWriter, r *http.Request) {
	items, err := h.Store.ListDistricts(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load districts")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"districts": items})
}
