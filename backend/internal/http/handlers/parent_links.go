package handlers

import (
	"net/http"

	"github.com/google/uuid"

	"jnv/backend/internal/httpctx"
	"jnv/backend/internal/models"
	"jnv/backend/internal/store"
)

type ParentLinkHandler struct {
	Store *store.Store
}

type createParentLinkRequest struct {
	StudentID string `json:"student_id"`
}

type createParentLinkByClassRollRequest struct {
	District   string `json:"district"`
	ClassLabel string `json:"class_label"`
	RollNumber int    `json:"roll_number"`
}

func (h ParentLinkHandler) Create(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !hasRole(user, models.RoleParent) {
		writeError(w, http.StatusForbidden, "parent role required")
		return
	}

	var req createParentLinkRequest
	if err := decodeJSON(r, &req); err != nil || req.StudentID == "" {
		writeError(w, http.StatusBadRequest, "invalid request")
		return
	}
	if _, err := uuid.Parse(req.StudentID); err != nil {
		writeError(w, http.StatusBadRequest, "student_id must be a valid UUID")
		return
	}

	student, err := h.Store.GetStudent(r.Context(), req.StudentID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load student")
		return
	}
	if student == nil {
		writeError(w, http.StatusNotFound, "student not found")
		return
	}

	existing, err := h.Store.FindParentLink(r.Context(), user.ID, req.StudentID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to check existing link")
		return
	}
	if existing != nil {
		if existing.Status == "pending" {
			writeError(w, http.StatusConflict, "link request already pending")
			return
		}
		if existing.Status == "approved" {
			writeJSON(w, http.StatusOK, existing)
			return
		}
	}

	link, err := h.Store.CreateParentLink(r.Context(), user.ID, req.StudentID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create link")
		return
	}
	auditLog(r.Context(), "parent_link.requested", user, map[string]interface{}{
		"student_id": req.StudentID,
	})
	writeJSON(w, http.StatusCreated, link)
}

func (h ParentLinkHandler) CreateByClassRoll(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !hasRole(user, models.RoleParent) {
		writeError(w, http.StatusForbidden, "parent role required")
		return
	}

	var req createParentLinkByClassRollRequest
	if err := decodeJSON(r, &req); err != nil || req.District == "" || req.ClassLabel == "" || req.RollNumber <= 0 {
		writeError(w, http.StatusBadRequest, "district, class_label and roll_number are required")
		return
	}

	var (
		student *models.Student
		err     error
	)
	school, err := h.Store.GetSchoolByDistrict(r.Context(), req.District)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to resolve district")
		return
	}
	if school == nil {
		writeError(w, http.StatusNotFound, "district school not found")
		return
	}

	student, err = h.Store.GetStudentByClassRoll(r.Context(), school.ID, req.ClassLabel, req.RollNumber)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if student == nil {
		writeError(w, http.StatusNotFound, "student not found for class and roll")
		return
	}

	existing, err := h.Store.FindParentLink(r.Context(), user.ID, student.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to check existing link")
		return
	}
	if existing != nil {
		if existing.Status == "pending" {
			writeError(w, http.StatusConflict, "link request already pending")
			return
		}
		if existing.Status == "approved" {
			writeJSON(w, http.StatusOK, existing)
			return
		}
	}

	link, err := h.Store.CreateParentLink(r.Context(), user.ID, student.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create link")
		return
	}
	auditLog(r.Context(), "parent_link.requested", user, map[string]interface{}{
		"student_id": student.ID,
		"district":   req.District,
	})
	writeJSON(w, http.StatusCreated, link)
}

func (h ParentLinkHandler) ListPending(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !hasRole(user, models.RoleAdmin) {
		writeError(w, http.StatusForbidden, "admin required")
		return
	}

	links, err := h.Store.ListPendingParentLinksDetailed(r.Context(), user.SchoolID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list links")
		return
	}
	writeJSON(w, http.StatusOK, links)
}

func (h ParentLinkHandler) Approve(w http.ResponseWriter, r *http.Request) {
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

	if err := h.Store.ApproveParentLink(r.Context(), id, user.SchoolID); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to approve")
		return
	}
	auditLog(r.Context(), "parent_link.approved", user, map[string]interface{}{
		"parent_link_id": id,
	})
	writeJSON(w, http.StatusOK, map[string]string{"status": "approved"})
}
