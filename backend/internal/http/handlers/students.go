package handlers

import (
	"encoding/csv"
	"fmt"
	"net/http"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
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

type studentUploadResponse struct {
	Inserted int      `json:"inserted"`
	Failed   int      `json:"failed"`
	Errors   []string `json:"errors"`
}

var phoneDigitsRegex = regexp.MustCompile(`^[0-9]+$`)

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

	normalizedPhone, err := normalizeParentPhone(req.ParentPhone)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
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
		ParentPhone:   normalizedPhone,
		AdmissionYear: req.AdmissionYear,
	})
	if err != nil {
		writeError(w, http.StatusBadRequest, "failed to create student (possible duplicate roll number)")
		return
	}
	writeJSON(w, http.StatusCreated, student)
}

func (h StudentsHandler) Upload(w http.ResponseWriter, r *http.Request) {
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
	if err := r.ParseMultipartForm(20 << 20); err != nil {
		writeError(w, http.StatusBadRequest, "invalid multipart form")
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "file is required")
		return
	}
	defer file.Close()

	ext := strings.ToLower(filepath.Ext(header.Filename))
	var rowsData [][]string
	switch ext {
	case ".csv":
		reader := csv.NewReader(file)
		reader.TrimLeadingSpace = true
		rowsData, err = reader.ReadAll()
		if err != nil {
			writeError(w, http.StatusBadRequest, "failed to parse csv file")
			return
		}
	case ".xlsx":
		rowsData, err = parseXLSXRows(file)
		if err != nil {
			writeError(w, http.StatusBadRequest, "failed to parse xlsx file")
			return
		}
	default:
		writeError(w, http.StatusBadRequest, "supported file types: .csv, .xlsx")
		return
	}
	if len(rowsData) == 0 {
		writeError(w, http.StatusBadRequest, "file is empty")
		return
	}

	headerIdx := buildStudentHeaderIndex(rowsData[0])
	required := []string{"full_name", "class_label", "roll_number", "date_of_birth"}
	for _, key := range required {
		if _, ok := headerIdx[key]; !ok {
			writeError(w, http.StatusBadRequest, fmt.Sprintf("missing required column: %s", key))
			return
		}
	}

	inserted := 0
	errorsList := []string{}
	for i, row := range rowsData[1:] {
		rowNum := i + 2
		fullName := strings.TrimSpace(getStudentCell(row, headerIdx, "full_name"))
		classLabel := strings.TrimSpace(getStudentCell(row, headerIdx, "class_label"))
		rollRaw := strings.TrimSpace(getStudentCell(row, headerIdx, "roll_number"))
		dobRaw := strings.TrimSpace(getStudentCell(row, headerIdx, "date_of_birth"))
		house := strings.TrimSpace(getStudentCell(row, headerIdx, "house"))
		parentPhoneRaw := strings.TrimSpace(getStudentCell(row, headerIdx, "parent_phone"))
		admissionYearRaw := strings.TrimSpace(getStudentCell(row, headerIdx, "admission_year"))

		if fullName == "" && classLabel == "" && rollRaw == "" && dobRaw == "" {
			continue
		}
		roll, err := strconv.Atoi(rollRaw)
		if err != nil || roll <= 0 {
			errorsList = append(errorsList, fmt.Sprintf("row %d: invalid roll_number", rowNum))
			continue
		}
		dateOfBirth, err := time.Parse("2006-01-02", dobRaw)
		if err != nil {
			errorsList = append(errorsList, fmt.Sprintf("row %d: date_of_birth must be YYYY-MM-DD", rowNum))
			continue
		}
		parentPhone, err := normalizeParentPhone(parentPhoneRaw)
		if err != nil {
			errorsList = append(errorsList, fmt.Sprintf("row %d: %s", rowNum, err.Error()))
			continue
		}
		admissionYear := time.Now().Year()
		if admissionYearRaw != "" {
			parsedYear, parseErr := strconv.Atoi(admissionYearRaw)
			if parseErr != nil || parsedYear <= 0 {
				errorsList = append(errorsList, fmt.Sprintf("row %d: invalid admission_year", rowNum))
				continue
			}
			admissionYear = parsedYear
		}
		existing, err := h.Store.GetStudentByClassRoll(r.Context(), user.SchoolID, classLabel, roll)
		if err != nil {
			errorsList = append(errorsList, fmt.Sprintf("row %d: failed to validate duplicate", rowNum))
			continue
		}
		if existing != nil {
			errorsList = append(errorsList, fmt.Sprintf("row %d: duplicate class+roll already exists", rowNum))
			continue
		}
		_, err = h.Store.CreateStudent(r.Context(), models.Student{
			SchoolID:      user.SchoolID,
			FullName:      fullName,
			ClassLabel:    classLabel,
			RollNumber:    roll,
			DateOfBirth:   dateOfBirth,
			House:         house,
			ParentPhone:   parentPhone,
			AdmissionYear: admissionYear,
		})
		if err != nil {
			errorsList = append(errorsList, fmt.Sprintf("row %d: failed to create student", rowNum))
			continue
		}
		inserted++
	}

	auditLog(r.Context(), "students.bulk_upload", user, map[string]interface{}{
		"inserted": inserted,
		"failed":   len(errorsList),
	})
	writeJSON(w, http.StatusOK, studentUploadResponse{
		Inserted: inserted,
		Failed:   len(errorsList),
		Errors:   errorsList,
	})
}

func normalizeParentPhone(value string) (string, error) {
	input := strings.TrimSpace(value)
	if input == "" {
		return "", nil
	}

	if strings.HasPrefix(input, "+91") {
		digits := strings.TrimPrefix(input, "+91")
		if len(digits) != 10 || !phoneDigitsRegex.MatchString(digits) {
			return "", errInvalidPhoneFormat()
		}
		return "+91" + digits, nil
	}

	if len(input) == 12 && strings.HasPrefix(input, "91") && phoneDigitsRegex.MatchString(input) {
		return "+" + input, nil
	}

	if len(input) == 10 && phoneDigitsRegex.MatchString(input) {
		return input, nil
	}

	return "", errInvalidPhoneFormat()
}

func errInvalidPhoneFormat() error {
	return &validationError{message: "parent_phone must be 10 digits, 91XXXXXXXXXX, or +91XXXXXXXXXX"}
}

func buildStudentHeaderIndex(headers []string) map[string]int {
	idx := map[string]int{}
	for i, raw := range headers {
		key := strings.ToLower(strings.TrimSpace(raw))
		switch key {
		case "full_name", "name", "student_name":
			idx["full_name"] = i
		case "class_label", "class":
			idx["class_label"] = i
		case "roll_number", "roll", "roll_no":
			idx["roll_number"] = i
		case "date_of_birth", "dob":
			idx["date_of_birth"] = i
		case "house":
			idx["house"] = i
		case "parent_phone", "phone", "parent_mobile":
			idx["parent_phone"] = i
		case "admission_year":
			idx["admission_year"] = i
		}
	}
	return idx
}

func getStudentCell(row []string, idx map[string]int, key string) string {
	col, ok := idx[key]
	if !ok || col < 0 || col >= len(row) {
		return ""
	}
	return strings.TrimSpace(row[col])
}

type validationError struct {
	message string
}

func (e *validationError) Error() string {
	return e.message
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
