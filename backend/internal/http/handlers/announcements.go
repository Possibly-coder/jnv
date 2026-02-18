package handlers

import (
	"net/http"

	"jnv/backend/internal/httpctx"
	"jnv/backend/internal/models"
	"jnv/backend/internal/store"
)

type AnnouncementHandler struct {
	Store *store.Store
}

type createAnnouncementRequest struct {
	SchoolID string `json:"school_id"`
	Title    string `json:"title"`
	Content  string `json:"content"`
	Category string `json:"category"`
	Priority string `json:"priority"`
}

func (h AnnouncementHandler) Create(w http.ResponseWriter, r *http.Request) {
	var req createAnnouncementRequest
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

	if req.SchoolID == "" {
		req.SchoolID = user.SchoolID
	}

	announcement, err := h.Store.CreateAnnouncement(r.Context(), models.Announcement{
		SchoolID:  req.SchoolID,
		Title:     req.Title,
		Content:   req.Content,
		Category:  req.Category,
		Priority:  req.Priority,
		Published: false,
		CreatedBy: user.ID,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create")
		return
	}
	writeJSON(w, http.StatusCreated, announcement)
}

func (h AnnouncementHandler) Publish(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "missing id")
		return
	}

	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !hasRole(user, models.RoleAdmin) {
		writeError(w, http.StatusForbidden, "admin required")
		return
	}

	if err := h.Store.PublishAnnouncement(r.Context(), id); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to publish")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "published"})
}

func (h AnnouncementHandler) List(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	includeUnpublished := user.Role == models.RoleAdmin || user.Role == models.RoleStaff
	items, err := h.Store.ListAnnouncements(r.Context(), user.SchoolID, includeUnpublished)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list")
		return
	}
	writeJSON(w, http.StatusOK, items)
}
