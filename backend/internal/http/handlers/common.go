package handlers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"jnv/backend/internal/models"
	"jnv/backend/internal/store"
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

var (
	auditStoreMu sync.RWMutex
	auditStore   *store.Store
)

func SetAuditStore(s *store.Store) {
	auditStoreMu.Lock()
	defer auditStoreMu.Unlock()
	auditStore = s
}

func auditLog(ctx context.Context, action string, user *models.User, fields map[string]interface{}) {
	payload := map[string]interface{}{
		"at":     time.Now().UTC().Format(time.RFC3339),
		"action": action,
	}
	if user != nil {
		payload["user_id"] = user.ID
		payload["user_role"] = user.Role
		payload["school_id"] = user.SchoolID
	}
	for key, value := range fields {
		payload[key] = value
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		log.Printf(`{"action":"%s","error":"audit_marshal_failed"}`, action)
		return
	}
	log.Printf("%s", raw)

	auditStoreMu.RLock()
	s := auditStore
	auditStoreMu.RUnlock()
	if s == nil {
		return
	}
	event := models.AuditEvent{
		Action:  action,
		Payload: string(raw),
	}
	if user != nil {
		event.SchoolID = user.SchoolID
		event.UserID = user.ID
		event.UserRole = string(user.Role)
	}
	_ = s.CreateAuditEvent(ctx, event)
}
