package handlers

import (
	"net/http"

	"jnv/backend/internal/httpctx"
	"jnv/backend/internal/models"
	"jnv/backend/internal/store"
)

type ParentsHandler struct {
	Store *store.Store
}

type parentOverviewResponse struct {
	Status  string          `json:"status"`
	Student *models.Student `json:"student,omitempty"`
	Scores  []models.Score  `json:"scores,omitempty"`
}

func (h ParentsHandler) Overview(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !hasRole(user, models.RoleParent) {
		writeError(w, http.StatusForbidden, "parent role required")
		return
	}

	link, err := h.Store.LatestParentLinkByParent(r.Context(), user.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load parent link")
		return
	}
	if link == nil {
		writeJSON(w, http.StatusOK, parentOverviewResponse{Status: "not_linked"})
		return
	}
	if link.Status != "approved" {
		writeJSON(w, http.StatusOK, parentOverviewResponse{Status: "pending"})
		return
	}

	student, err := h.Store.GetStudent(r.Context(), link.StudentID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load student")
		return
	}
	if student == nil {
		writeJSON(w, http.StatusOK, parentOverviewResponse{Status: "pending"})
		return
	}

	scores, err := h.Store.ListScoresByStudent(r.Context(), student.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load scores")
		return
	}

	writeJSON(w, http.StatusOK, parentOverviewResponse{
		Status:  "approved",
		Student: student,
		Scores:  scores,
	})
}
