package handlers

import (
	"net/http"
	"time"

	"jnv/backend/internal/httpctx"
	"jnv/backend/internal/models"
	"jnv/backend/internal/store"
)

type ExamHandler struct {
	Store *store.Store
}

type createExamRequest struct {
	Class    string `json:"class"`
	Title    string `json:"title"`
	Term     string `json:"term"`
	Date     string `json:"date"`
}

func (h ExamHandler) Create(w http.ResponseWriter, r *http.Request) {
	var req createExamRequest
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
	if req.Date == "" {
		writeError(w, http.StatusBadRequest, "date required")
		return
	}

	examDate, err := time.Parse("2006-01-02", req.Date)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid date")
		return
	}

	exam, err := h.Store.CreateExam(r.Context(), models.Exam{
		SchoolID: user.SchoolID,
		Class:    req.Class,
		Title:    req.Title,
		Term:     req.Term,
		Date:     examDate,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create exam")
		return
	}
	writeJSON(w, http.StatusCreated, exam)
}
