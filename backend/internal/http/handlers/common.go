package handlers

import (
	"encoding/json"
	"net/http"

	"jnv/backend/internal/models"
)

func writeJSON(w http.ResponseWriter, status int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func decodeJSON(r *http.Request, dst interface{}) error {
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	return decoder.Decode(dst)
}

func hasRole(user *models.User, roles ...models.Role) bool {
	if user == nil {
		return false
	}
	for _, role := range roles {
		if user.Role == role {
			return true
		}
	}
	return false
}
