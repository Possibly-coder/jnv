package handlers

import (
	"database/sql"
	"errors"
	"net/http"
	"strings"
	"time"

	"jnv/backend/internal/httpctx"
	"jnv/backend/internal/models"
	"jnv/backend/internal/notify"
	"jnv/backend/internal/store"
)

type EventsHandler struct {
	Store    *store.Store
	Notifier notify.Sender
}

type createEventRequest struct {
	SchoolID    string `json:"school_id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	EventDate   string `json:"event_date"`
	StartTime   string `json:"start_time"`
	EndTime     string `json:"end_time"`
	Location    string `json:"location"`
	Audience    string `json:"audience"`
	Category    string `json:"category"`
}

func (h EventsHandler) Create(w http.ResponseWriter, r *http.Request) {
	var req createEventRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request")
		return
	}
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !hasRole(user, models.RoleAdmin, models.RoleStaff) {
		writeError(w, http.StatusForbidden, "insufficient permissions")
		return
	}
	req.Title = strings.TrimSpace(req.Title)
	if req.Title == "" || strings.TrimSpace(req.EventDate) == "" {
		writeError(w, http.StatusBadRequest, "title and event_date are required")
		return
	}
	eventDate, err := time.Parse("2006-01-02", req.EventDate)
	if err != nil {
		writeError(w, http.StatusBadRequest, "event_date must be YYYY-MM-DD")
		return
	}
	if req.SchoolID == "" {
		req.SchoolID = user.SchoolID
	}
	event, err := h.Store.CreateEvent(r.Context(), models.Event{
		SchoolID:    req.SchoolID,
		Title:       req.Title,
		Description: strings.TrimSpace(req.Description),
		EventDate:   eventDate,
		StartTime:   strings.TrimSpace(req.StartTime),
		EndTime:     strings.TrimSpace(req.EndTime),
		Location:    strings.TrimSpace(req.Location),
		Audience:    strings.TrimSpace(req.Audience),
		Category:    strings.TrimSpace(req.Category),
		Published:   false,
		CreatedBy:   user.ID,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create event")
		return
	}
	auditLog(r.Context(), "event.created", user, map[string]interface{}{
		"event_id": event.ID,
		"title":    event.Title,
	})
	writeJSON(w, http.StatusCreated, event)
}

func (h EventsHandler) Publish(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !hasRole(user, models.RoleAdmin) {
		writeError(w, http.StatusForbidden, "admin required")
		return
	}
	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "missing id")
		return
	}
	if err := h.Store.PublishEvent(r.Context(), id); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to publish")
		return
	}
	_ = h.Notifier.SendToSchoolParents(r.Context(), user.SchoolID, "New event published", "Check the latest event details in your app.", map[string]string{
		"type":     "event",
		"event_id": id,
	})
	auditLog(r.Context(), "event.published", user, map[string]interface{}{
		"event_id": id,
	})
	writeJSON(w, http.StatusOK, map[string]string{"status": "published"})
}

func (h EventsHandler) List(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	includeUnpublished := user.Role == models.RoleAdmin || user.Role == models.RoleStaff
	items, err := h.Store.ListEvents(r.Context(), user.SchoolID, includeUnpublished)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list events")
		return
	}
	writeJSON(w, http.StatusOK, items)
}

func (h EventsHandler) Delete(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !hasRole(user, models.RoleAdmin) {
		writeError(w, http.StatusForbidden, "admin required")
		return
	}
	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "missing id")
		return
	}
	if err := h.Store.DeleteEvent(r.Context(), id, user.SchoolID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, "event not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to delete event")
		return
	}
	auditLog(r.Context(), "event.deleted", user, map[string]interface{}{
		"event_id": id,
	})
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
