package handlers

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/csv"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"jnv/backend/internal/httpctx"
	"jnv/backend/internal/models"
	"jnv/backend/internal/notify"
	"jnv/backend/internal/store"
)

type ScoresHandler struct {
	Store    *store.Store
	Notifier notify.Sender
}

type createScoresRequest struct {
	Scores []struct {
		StudentID string  `json:"student_id"`
		Subject   string  `json:"subject"`
		Score     float32 `json:"score"`
		MaxScore  float32 `json:"max_score"`
		Grade     string  `json:"grade"`
	} `json:"scores"`
}

func (h ScoresHandler) AddForExam(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !hasRole(user, models.RoleAdmin, models.RoleStaff) {
		writeError(w, http.StatusForbidden, "insufficient permissions")
		return
	}

	examID := r.PathValue("id")
	if examID == "" {
		writeError(w, http.StatusBadRequest, "missing exam id")
		return
	}

	var req createScoresRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request")
		return
	}

	if len(req.Scores) == 0 {
		writeError(w, http.StatusBadRequest, "no scores")
		return
	}

	var scores []models.Score
	for _, item := range req.Scores {
		scores = append(scores, models.Score{
			ExamID:    examID,
			StudentID: item.StudentID,
			Subject:   item.Subject,
			Score:     item.Score,
			MaxScore:  item.MaxScore,
			Grade:     item.Grade,
		})
	}

	if err := h.Store.AddScores(r.Context(), examID, scores); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to add scores")
		return
	}
	_ = h.Notifier.SendToSchoolParents(r.Context(), user.SchoolID, "Scores updated", "New exam scores were uploaded.", map[string]string{
		"type":    "score_upload",
		"exam_id": examID,
	})
	auditLog(r.Context(), "scores.created.manual", user, map[string]interface{}{
		"exam_id": examID,
		"count":   len(scores),
	})
	writeJSON(w, http.StatusCreated, map[string]string{"status": "uploaded"})
}

type csvUploadResponse struct {
	Inserted int      `json:"inserted"`
	Errors   []string `json:"errors"`
}

func (h ScoresHandler) UploadCSV(w http.ResponseWriter, r *http.Request) {
	h.UploadFile(w, r)
}

func (h ScoresHandler) UploadFile(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !hasRole(user, models.RoleAdmin, models.RoleStaff) {
		writeError(w, http.StatusForbidden, "insufficient permissions")
		return
	}

	examID := r.PathValue("id")
	if examID == "" {
		writeError(w, http.StatusBadRequest, "missing exam id")
		return
	}

	exam, err := h.Store.GetExam(r.Context(), examID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load exam")
		return
	}
	if exam == nil {
		writeError(w, http.StatusNotFound, "exam not found")
		return
	}

	if err := r.ParseMultipartForm(10 << 20); err != nil {
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
	var (
		headers []string
		rows    [][]string
	)

	switch ext {
	case ".csv":
		reader := csv.NewReader(file)
		reader.TrimLeadingSpace = true
		allRows, parseErr := reader.ReadAll()
		if parseErr != nil {
			writeError(w, http.StatusBadRequest, "failed to parse csv file")
			return
		}
		if len(allRows) == 0 {
			writeError(w, http.StatusBadRequest, "file is empty")
			return
		}
		headers = allRows[0]
		if len(allRows) > 1 {
			rows = allRows[1:]
		}
	case ".xlsx":
		rowsData, parseErr := parseXLSXRows(file)
		if parseErr != nil {
			writeError(w, http.StatusBadRequest, "failed to parse xlsx file")
			return
		}
		if len(rowsData) == 0 {
			writeError(w, http.StatusBadRequest, "file is empty")
			return
		}
		headers = rowsData[0]
		if len(rowsData) > 1 {
			rows = rowsData[1:]
		}
	default:
		writeError(w, http.StatusBadRequest, "supported file types: .csv, .xlsx")
		return
	}

	scores, errorsList := h.buildScoresFromRows(r.Context(), examID, exam, headers, rows)

	if len(errorsList) > 0 {
		writeJSON(w, http.StatusBadRequest, csvUploadResponse{Inserted: 0, Errors: errorsList})
		return
	}

	if err := h.Store.AddScores(r.Context(), examID, scores); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to add scores")
		return
	}
	_ = h.Notifier.SendToSchoolParents(r.Context(), user.SchoolID, "Scores uploaded", "Bulk scores have been published by school staff.", map[string]string{
		"type":    "score_upload",
		"exam_id": examID,
	})
	auditLog(r.Context(), "scores.created.bulk", user, map[string]interface{}{
		"exam_id": examID,
		"count":   len(scores),
	})

	writeJSON(w, http.StatusCreated, csvUploadResponse{Inserted: len(scores), Errors: nil})
}

func (h ScoresHandler) buildScoresFromRows(
	ctx context.Context,
	examID string,
	exam *models.Exam,
	headers []string,
	rows [][]string,
) ([]models.Score, []string) {
	headerIndex := map[string]int{}
	for i, value := range headers {
		headerIndex[normalizeHeader(value)] = i
	}

	if !hasHeader(headerIndex, "roll") {
		return nil, []string{"missing required column: roll"}
	}

	isRowBased := hasHeader(headerIndex, "subject")
	if isRowBased && !hasHeader(headerIndex, "score") {
		return nil, []string{"missing required column: score"}
	}

	errorsList := []string{}
	var scores []models.Score

	for idx, record := range rows {
		rowNumber := idx + 2 // header is row 1
		if len(record) == 0 {
			continue
		}

		roll := getCell(record, headerIndex, "roll")
		if roll == "" {
			errorsList = append(errorsList, "row "+strconv.Itoa(rowNumber)+": missing roll")
			continue
		}

		rollNumberValue, err := strconv.Atoi(roll)
		if err != nil {
			errorsList = append(errorsList, "row "+strconv.Itoa(rowNumber)+": invalid roll")
			continue
		}

		student, err := h.Store.GetStudentByClassRoll(ctx, exam.SchoolID, exam.Class, rollNumberValue)
		if err != nil {
			errorsList = append(errorsList, "row "+strconv.Itoa(rowNumber)+": student lookup failed")
			continue
		}
		if student == nil {
			errorsList = append(errorsList, "row "+strconv.Itoa(rowNumber)+": student not found")
			continue
		}

		if isRowBased {
			subject := getCell(record, headerIndex, "subject")
			scoreValue := getCell(record, headerIndex, "score")
			maxValue := getCell(record, headerIndex, "max_score")
			grade := getCell(record, headerIndex, "grade")

			if subject == "" || scoreValue == "" {
				errorsList = append(errorsList, "row "+strconv.Itoa(rowNumber)+": subject and score required")
				continue
			}

			scoreFloat, err := strconv.ParseFloat(scoreValue, 32)
			if err != nil {
				errorsList = append(errorsList, "row "+strconv.Itoa(rowNumber)+": invalid score")
				continue
			}

			maxFloat := float32(100)
			if maxValue != "" {
				maxParsed, err := strconv.ParseFloat(maxValue, 32)
				if err != nil {
					errorsList = append(errorsList, "row "+strconv.Itoa(rowNumber)+": invalid max_score")
					continue
				}
				maxFloat = float32(maxParsed)
			}

			scores = append(scores, models.Score{
				ExamID:    examID,
				StudentID: student.ID,
				Subject:   subject,
				Score:     float32(scoreFloat),
				MaxScore:  maxFloat,
				Grade:     grade,
			})
			continue
		}

		for headerName, colIdx := range headerIndex {
			if headerName == "roll" || headerName == "studentname" {
				continue
			}
			value := getCell(record, headerIndex, headerName)
			if value == "" {
				continue
			}
			scoreFloat, err := strconv.ParseFloat(value, 32)
			if err != nil {
				errorsList = append(errorsList, "row "+strconv.Itoa(rowNumber)+": invalid score for "+headerName)
				continue
			}
			scores = append(scores, models.Score{
				ExamID:    examID,
				StudentID: student.ID,
				Subject:   headers[colIdx],
				Score:     float32(scoreFloat),
				MaxScore:  100,
				Grade:     "",
			})
		}
	}

	return scores, errorsList
}

func getCell(record []string, headerIndex map[string]int, key string) string {
	idx, ok := headerIndex[normalizeHeader(key)]
	if !ok || idx >= len(record) {
		return ""
	}
	return strings.TrimSpace(record[idx])
}

func normalizeHeader(value string) string {
	normalized := strings.ToLower(strings.TrimSpace(value))
	normalized = strings.ReplaceAll(normalized, " ", "")
	normalized = strings.ReplaceAll(normalized, "_", "")
	return normalized
}

func hasHeader(headers map[string]int, key string) bool {
	_, ok := headers[normalizeHeader(key)]
	return ok
}

func parseXLSXRows(reader io.Reader) ([][]string, error) {
	data, err := io.ReadAll(reader)
	if err != nil {
		return nil, err
	}

	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return nil, err
	}

	files := map[string]*zip.File{}
	for _, f := range zr.File {
		files[f.Name] = f
	}

	sharedStrings, _ := readSharedStrings(files["xl/sharedStrings.xml"])

	sheetPath := ""
	if _, ok := files["xl/worksheets/sheet1.xml"]; ok {
		sheetPath = "xl/worksheets/sheet1.xml"
	} else {
		var candidates []string
		for name := range files {
			if strings.HasPrefix(name, "xl/worksheets/") && strings.HasSuffix(name, ".xml") {
				candidates = append(candidates, name)
			}
		}
		sort.Strings(candidates)
		if len(candidates) == 0 {
			return nil, fmt.Errorf("xlsx has no worksheets")
		}
		sheetPath = candidates[0]
	}

	return readSheetRows(files[sheetPath], sharedStrings)
}

func readSharedStrings(file *zip.File) ([]string, error) {
	if file == nil {
		return nil, nil
	}
	rc, err := file.Open()
	if err != nil {
		return nil, err
	}
	defer rc.Close()

	type richRun struct {
		T string `xml:"t"`
	}
	type si struct {
		T string    `xml:"t"`
		R []richRun `xml:"r"`
	}
	var doc struct {
		Items []si `xml:"si"`
	}
	if err := xml.NewDecoder(rc).Decode(&doc); err != nil {
		return nil, err
	}

	out := make([]string, 0, len(doc.Items))
	for _, item := range doc.Items {
		if item.T != "" {
			out = append(out, item.T)
			continue
		}
		var b strings.Builder
		for _, run := range item.R {
			b.WriteString(run.T)
		}
		out = append(out, b.String())
	}
	return out, nil
}

func readSheetRows(file *zip.File, sharedStrings []string) ([][]string, error) {
	if file == nil {
		return nil, fmt.Errorf("worksheet file missing")
	}
	rc, err := file.Open()
	if err != nil {
		return nil, err
	}
	defer rc.Close()

	type inlineStr struct {
		T string `xml:"t"`
	}
	type cell struct {
		R  string     `xml:"r,attr"`
		T  string     `xml:"t,attr"`
		V  string     `xml:"v"`
		IS *inlineStr `xml:"is"`
	}
	type row struct {
		Cells []cell `xml:"c"`
	}
	var ws struct {
		Rows []row `xml:"sheetData>row"`
	}
	if err := xml.NewDecoder(rc).Decode(&ws); err != nil {
		return nil, err
	}

	var result [][]string
	for _, r := range ws.Rows {
		maxCol := -1
		values := map[int]string{}
		for _, c := range r.Cells {
			col := cellColumnIndex(c.R)
			if col > maxCol {
				maxCol = col
			}
			switch c.T {
			case "s":
				idx, parseErr := strconv.Atoi(strings.TrimSpace(c.V))
				if parseErr == nil && idx >= 0 && idx < len(sharedStrings) {
					values[col] = sharedStrings[idx]
				} else {
					values[col] = c.V
				}
			case "inlineStr":
				if c.IS != nil {
					values[col] = c.IS.T
				}
			default:
				values[col] = c.V
			}
		}
		if maxCol < 0 {
			result = append(result, []string{})
			continue
		}
		rowValues := make([]string, maxCol+1)
		for idx, val := range values {
			rowValues[idx] = strings.TrimSpace(val)
		}
		result = append(result, rowValues)
	}
	return result, nil
}

func cellColumnIndex(ref string) int {
	if ref == "" {
		return 0
	}
	col := 0
	for _, ch := range ref {
		if ch >= '0' && ch <= '9' {
			break
		}
		if ch >= 'a' && ch <= 'z' {
			ch = ch - 'a' + 'A'
		}
		if ch < 'A' || ch > 'Z' {
			continue
		}
		col = col*26 + int(ch-'A'+1)
	}
	if col == 0 {
		return 0
	}
	return col - 1
}

func (h ScoresHandler) ListByStudent(w http.ResponseWriter, r *http.Request) {
	user := httpctx.UserFromContext(r.Context())
	if user == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	studentID := r.PathValue("id")
	if studentID == "" {
		writeError(w, http.StatusBadRequest, "missing student id")
		return
	}

	if hasRole(user, models.RoleParent) {
		allowed, err := h.Store.IsParentLinkedToStudent(r.Context(), user.ID, studentID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "failed to validate access")
			return
		}
		if !allowed {
			writeError(w, http.StatusForbidden, "not linked to this student")
			return
		}
	}

	items, err := h.Store.ListScoresByStudent(r.Context(), studentID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list scores")
		return
	}
	writeJSON(w, http.StatusOK, items)
}
