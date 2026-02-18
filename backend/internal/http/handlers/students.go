package handlers

import (
	"net/http"
	"strconv"
	"time"

	"jnv/backend/internal/httpctx"
	"jnv/backend/internal/models"
	"jnv/backend/internal/store"
)

type StudentsHandler struct {
	Store *store.Store
}

type createStudentRequest struct {
	FullName      string `json:"full_name"`
	ClassLabel    string `json:"class_label"`
	RollNumber    int    `json:"roll_number"`
	DateOfBirth   string `json:"date_of_birth"`
	House         string `json:"house"`
	ParentPhone   string `json:"parent_phone"`
	AdmissionYear int    `json:"admission_year"`
}

func (h StudentsHandler) Create(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !hasRole(user, models.RoleAdmin, models.RoleStaff) {
		writeError(w, http.StatusForbidden, "insufficient permissions")
		return
	}
	if user.SchoolID == "" {
		writeError(w, http.StatusBadRequest, "user is not mapped to a school")
		return
	}

	var req createStudentRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request")
		return
	}
	if req.FullName == "" || req.ClassLabel == "" || req.RollNumber <= 0 || req.DateOfBirth == "" {
		writeError(w, http.StatusBadRequest, "missing required fields")
		return
	}

	dateOfBirth, err := time.Parse("2006-01-02", req.DateOfBirth)
	if err != nil {
		writeError(w, http.StatusBadRequest, "date_of_birth must be YYYY-MM-DD")
		return
	}
	if req.AdmissionYear <= 0 {
		req.AdmissionYear = time.Now().Year()
	}

	student, err := h.Store.CreateStudent(r.Context(), models.Student{
		SchoolID:      user.SchoolID,
		FullName:      req.FullName,
		ClassLabel:    req.ClassLabel,
		RollNumber:    req.RollNumber,
		DateOfBirth:   dateOfBirth,
		House:         req.House,
		ParentPhone:   req.ParentPhone,
		AdmissionYear: req.AdmissionYear,
	})
	if err != nil {
		writeError(w, http.StatusBadRequest, "failed to create student (possible duplicate roll number)")
		return
	}
	writeJSON(w, http.StatusCreated, student)
}

func (h StudentsHandler) List(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !hasRole(user, models.RoleAdmin, models.RoleStaff, models.RoleTeacher) {
		writeError(w, http.StatusForbidden, "insufficient permissions")
		return
	}
	if user.SchoolID == "" {
		writeJSON(w, http.StatusOK, []models.Student{})
		return
	}

	classLabel := r.URL.Query().Get("class")
	items, err := h.Store.ListStudentsBySchool(r.Context(), user.SchoolID, classLabel, 500)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list students")
		return
	}
	writeJSON(w, http.StatusOK, items)
}

func (h StudentsHandler) Lookup(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	classLabel := r.URL.Query().Get("class")
	rollStr := r.URL.Query().Get("roll")
	if classLabel == "" || rollStr == "" {
		writeError(w, http.StatusBadRequest, "class and roll required")
		return
	}

	roll, err := strconv.Atoi(rollStr)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid roll")
		return
	}

	student, err := h.Store.GetStudentByClassRoll(r.Context(), user.SchoolID, classLabel, roll)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to lookup student")
		return
	}
	if student == nil {
		writeError(w, http.StatusNotFound, "student not found")
		return
	}
	writeJSON(w, http.StatusOK, student)
}
