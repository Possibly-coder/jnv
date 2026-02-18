package handlers

import (
	"net/http"

	"jnv/backend/internal/httpctx"
)

func Me(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	writeJSON(w, http.StatusOK, user)
}
