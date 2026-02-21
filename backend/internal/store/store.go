package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"

	"jnv/backend/internal/models"
)

type Store struct {
	db *sql.DB
}

func New(db *sql.DB) *Store {
	return &Store{db: db}
}

func (s *Store) Ping(ctx context.Context) error {
	return s.db.PingContext(ctx)
}

func (s *Store) FirstSchoolID(ctx context.Context) (string, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id::text FROM schools ORDER BY created_at ASC LIMIT 1`)
	var schoolID string
	if err := row.Scan(&schoolID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", nil
		}
		return "", err
	}
	return schoolID, nil
}

func (s *Store) GetSchoolByDistrict(ctx context.Context, district string) (*models.School, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id::text, name, state, district, created_at
		FROM schools
		WHERE lower(district) = lower($1)
		LIMIT 1
	`, district)

	var school models.School
	if err := row.Scan(&school.ID, &school.Name, &school.State, &school.District, &school.CreatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &school, nil
}

func (s *Store) ListDistricts(ctx context.Context) ([]string, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT DISTINCT district
		FROM schools
		ORDER BY district ASC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var districts []string
	for rows.Next() {
		var district string
		if err := rows.Scan(&district); err != nil {
			return nil, err
		}
		districts = append(districts, district)
	}
	return districts, rows.Err()
}

func (s *Store) GetUserByPhone(ctx context.Context, phone string) (*models.User, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id, school_id, role, full_name, phone, email, created_at
		FROM users
		WHERE phone = $1
	`, phone)

	var user models.User
	var schoolID sql.NullString
	if err := row.Scan(&user.ID, &schoolID, &user.Role, &user.FullName, &user.Phone, &user.Email, &user.CreatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	user.SchoolID = schoolID.String
	return &user, nil
}

func (s *Store) CreateUser(ctx context.Context, user models.User) (*models.User, error) {
	if user.ID == "" {
		user.ID = uuid.NewString()
	}
	if user.CreatedAt.IsZero() {
		user.CreatedAt = time.Now()
	}

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO users (id, school_id, role, full_name, phone, email, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, user.ID, nullString(user.SchoolID), user.Role, user.FullName, user.Phone, user.Email, user.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (s *Store) GetStudent(ctx context.Context, studentID string) (*models.Student, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id, school_id, full_name, class_label, roll_number, date_of_birth, house, parent_phone, admission_year, created_at
		FROM students
		WHERE id = $1
	`, studentID)

	var student models.Student
	if err := row.Scan(&student.ID, &student.SchoolID, &student.FullName, &student.ClassLabel, &student.RollNumber,
		&student.DateOfBirth, &student.House, &student.ParentPhone, &student.AdmissionYear, &student.CreatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &student, nil
}

func (s *Store) CreateStudent(ctx context.Context, student models.Student) (*models.Student, error) {
	if student.ID == "" {
		student.ID = uuid.NewString()
	}
	if student.CreatedAt.IsZero() {
		student.CreatedAt = time.Now()
	}

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO students (id, school_id, full_name, class_label, roll_number, date_of_birth, house, parent_phone, admission_year, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
	`, student.ID, student.SchoolID, student.FullName, student.ClassLabel, student.RollNumber,
		student.DateOfBirth, student.House, student.ParentPhone, student.AdmissionYear, student.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &student, nil
}

func (s *Store) ListStudentsBySchool(ctx context.Context, schoolID, classLabel string, limit int) ([]models.Student, error) {
	var (
		rows *sql.Rows
		err  error
	)
	if classLabel != "" {
		rows, err = s.db.QueryContext(ctx, `
			SELECT id, school_id, full_name, class_label, roll_number, date_of_birth, house, parent_phone, admission_year, created_at
			FROM students
			WHERE school_id = $1 AND class_label = $2
			ORDER BY class_label ASC, roll_number ASC
			LIMIT $3
		`, schoolID, classLabel, limit)
	} else {
		rows, err = s.db.QueryContext(ctx, `
			SELECT id, school_id, full_name, class_label, roll_number, date_of_birth, house, parent_phone, admission_year, created_at
			FROM students
			WHERE school_id = $1
			ORDER BY class_label ASC, roll_number ASC
			LIMIT $2
		`, schoolID, limit)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var students []models.Student
	for rows.Next() {
		var student models.Student
		if err := rows.Scan(&student.ID, &student.SchoolID, &student.FullName, &student.ClassLabel, &student.RollNumber,
			&student.DateOfBirth, &student.House, &student.ParentPhone, &student.AdmissionYear, &student.CreatedAt); err != nil {
			return nil, err
		}
		students = append(students, student)
	}
	return students, rows.Err()
}

func (s *Store) CreateParentLink(ctx context.Context, parentID, studentID string) (*models.ParentLink, error) {
	link := models.ParentLink{
		ID:        uuid.NewString(),
		ParentID:  parentID,
		StudentID: studentID,
		Status:    "pending",
		CreatedAt: time.Now(),
	}

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO parent_links (id, parent_id, student_id, status, created_at)
		VALUES ($1, $2, $3, $4, $5)
	`, link.ID, link.ParentID, link.StudentID, link.Status, link.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &link, nil
}

func (s *Store) FindParentLink(ctx context.Context, parentID, studentID string) (*models.ParentLink, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id, parent_id, student_id, status, created_at
		FROM parent_links
		WHERE parent_id = $1 AND student_id = $2
		ORDER BY created_at DESC
		LIMIT 1
	`, parentID, studentID)

	var link models.ParentLink
	if err := row.Scan(&link.ID, &link.ParentID, &link.StudentID, &link.Status, &link.CreatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &link, nil
}

func (s *Store) LatestParentLinkByParent(ctx context.Context, parentID string) (*models.ParentLink, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id, parent_id, student_id, status, created_at
		FROM parent_links
		WHERE parent_id = $1
		ORDER BY created_at DESC
		LIMIT 1
	`, parentID)

	var link models.ParentLink
	if err := row.Scan(&link.ID, &link.ParentID, &link.StudentID, &link.Status, &link.CreatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &link, nil
}

func (s *Store) IsParentLinkedToStudent(ctx context.Context, parentID, studentID string) (bool, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT 1
		FROM parent_links
		WHERE parent_id = $1 AND student_id = $2 AND status = 'approved'
		LIMIT 1
	`, parentID, studentID)

	var one int
	if err := row.Scan(&one); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

func (s *Store) ListPendingParentLinks(ctx context.Context, schoolID string) ([]models.ParentLink, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT pl.id, pl.parent_id, pl.student_id, pl.status, pl.created_at
		FROM parent_links pl
		JOIN students s ON s.id = pl.student_id
		WHERE pl.status = 'pending' AND s.school_id = $1
		ORDER BY pl.created_at DESC
	`, schoolID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var links []models.ParentLink
	for rows.Next() {
		var link models.ParentLink
		if err := rows.Scan(&link.ID, &link.ParentID, &link.StudentID, &link.Status, &link.CreatedAt); err != nil {
			return nil, err
		}
		links = append(links, link)
	}
	return links, rows.Err()
}

func (s *Store) ListPendingParentLinksDetailed(ctx context.Context, schoolID string) ([]models.ParentLinkApprovalItem, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT
			pl.id,
			pl.parent_id,
			COALESCE(u.full_name, ''),
			COALESCE(u.phone, ''),
			pl.student_id,
			COALESCE(st.full_name, ''),
			COALESCE(st.class_label, ''),
			COALESCE(st.roll_number, 0),
			pl.status,
			pl.created_at
		FROM parent_links pl
		JOIN students st ON st.id = pl.student_id
		LEFT JOIN users u ON u.id = pl.parent_id
		WHERE pl.status = 'pending' AND st.school_id = $1
		ORDER BY pl.created_at DESC
	`, schoolID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []models.ParentLinkApprovalItem
	for rows.Next() {
		var item models.ParentLinkApprovalItem
		if err := rows.Scan(
			&item.ID,
			&item.ParentID,
			&item.ParentName,
			&item.ParentPhone,
			&item.StudentID,
			&item.StudentName,
			&item.ClassLabel,
			&item.RollNumber,
			&item.Status,
			&item.CreatedAt,
		); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) ApproveParentLink(ctx context.Context, linkID, schoolID string) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE parent_links
		SET status = 'approved'
		WHERE id = $1
	`, linkID)
	if err != nil {
		return err
	}

	_, err = s.db.ExecContext(ctx, `
		UPDATE users
		SET school_id = $1
		WHERE id = (
			SELECT parent_id FROM parent_links WHERE id = $2
		)
	`, schoolID, linkID)
	return err
}

func (s *Store) CreateAnnouncement(ctx context.Context, announcement models.Announcement) (*models.Announcement, error) {
	if announcement.ID == "" {
		announcement.ID = uuid.NewString()
	}
	if announcement.CreatedAt.IsZero() {
		announcement.CreatedAt = time.Now()
	}

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO announcements (id, school_id, title, content, category, priority, published, created_by, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
	`, announcement.ID, announcement.SchoolID, announcement.Title, announcement.Content, announcement.Category,
		announcement.Priority, announcement.Published, announcement.CreatedBy, announcement.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &announcement, nil
}

func (s *Store) PublishAnnouncement(ctx context.Context, announcementID string) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE announcements
		SET published = true, published_at = now()
		WHERE id = $1
	`, announcementID)
	return err
}

func (s *Store) DeleteAnnouncement(ctx context.Context, announcementID, schoolID string) error {
	res, err := s.db.ExecContext(ctx, `
		DELETE FROM announcements
		WHERE id = $1 AND school_id = $2
	`, announcementID, schoolID)
	if err != nil {
		return err
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if affected == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func (s *Store) ListAnnouncements(ctx context.Context, schoolID string, includeUnpublished bool) ([]models.Announcement, error) {
	query := `
		SELECT id, school_id, title, content, category, priority, published, created_by, created_at
		FROM announcements
		WHERE school_id = $1
	`
	if !includeUnpublished {
		query += " AND published = true"
	}
	query += " ORDER BY created_at DESC"

	rows, err := s.db.QueryContext(ctx, query, schoolID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []models.Announcement
	for rows.Next() {
		var item models.Announcement
		if err := rows.Scan(&item.ID, &item.SchoolID, &item.Title, &item.Content, &item.Category,
			&item.Priority, &item.Published, &item.CreatedBy, &item.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) CreateEvent(ctx context.Context, event models.Event) (*models.Event, error) {
	if event.ID == "" {
		event.ID = uuid.NewString()
	}
	if event.CreatedAt.IsZero() {
		event.CreatedAt = time.Now()
	}
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO events (
			id, school_id, title, description, event_date, start_time, end_time,
			location, audience, category, published, created_by, created_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
	`, event.ID, event.SchoolID, event.Title, event.Description, event.EventDate, event.StartTime,
		event.EndTime, event.Location, event.Audience, event.Category, event.Published, event.CreatedBy, event.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &event, nil
}

func (s *Store) PublishEvent(ctx context.Context, eventID string) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE events
		SET published = true, published_at = now()
		WHERE id = $1
	`, eventID)
	return err
}

func (s *Store) DeleteEvent(ctx context.Context, eventID, schoolID string) error {
	res, err := s.db.ExecContext(ctx, `
		DELETE FROM events
		WHERE id = $1 AND school_id = $2
	`, eventID, schoolID)
	if err != nil {
		return err
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if affected == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func (s *Store) ListEvents(ctx context.Context, schoolID string, includeUnpublished bool) ([]models.Event, error) {
	query := `
		SELECT id, school_id, title, description, event_date, start_time, end_time,
		       location, audience, category, published, published_at, created_by, created_at
		FROM events
		WHERE school_id = $1
	`
	if !includeUnpublished {
		query += " AND published = true"
	}
	query += " ORDER BY event_date ASC, created_at DESC"
	rows, err := s.db.QueryContext(ctx, query, schoolID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []models.Event
	for rows.Next() {
		var item models.Event
		if err := rows.Scan(
			&item.ID, &item.SchoolID, &item.Title, &item.Description, &item.EventDate, &item.StartTime,
			&item.EndTime, &item.Location, &item.Audience, &item.Category, &item.Published,
			&item.PublishedAt, &item.CreatedBy, &item.CreatedAt,
		); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) GetAppConfig(ctx context.Context, schoolID string) (*models.AppConfig, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT school_id, feature_flags, dashboard_widgets, min_supported_version,
		       force_update_message, coalesce(updated_by::text, ''), updated_at
		FROM app_configs
		WHERE school_id = $1
	`, schoolID)
	var config models.AppConfig
	var featureFlagsRaw []byte
	var dashboardWidgetsRaw []byte
	if err := row.Scan(
		&config.SchoolID,
		&featureFlagsRaw,
		&dashboardWidgetsRaw,
		&config.MinSupportedVersion,
		&config.ForceUpdateMessage,
		&config.UpdatedBy,
		&config.UpdatedAt,
	); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return &models.AppConfig{
				SchoolID:         schoolID,
				FeatureFlags:     map[string]bool{},
				DashboardWidgets: []models.DashboardWidget{},
			}, nil
		}
		return nil, err
	}
	if len(featureFlagsRaw) > 0 {
		if err := json.Unmarshal(featureFlagsRaw, &config.FeatureFlags); err != nil {
			return nil, err
		}
	}
	if config.FeatureFlags == nil {
		config.FeatureFlags = map[string]bool{}
	}
	if len(dashboardWidgetsRaw) > 0 {
		if err := json.Unmarshal(dashboardWidgetsRaw, &config.DashboardWidgets); err != nil {
			return nil, err
		}
	}
	if config.DashboardWidgets == nil {
		config.DashboardWidgets = []models.DashboardWidget{}
	}
	return &config, nil
}

func (s *Store) UpsertAppConfig(ctx context.Context, config models.AppConfig) error {
	featureFlags, err := json.Marshal(config.FeatureFlags)
	if err != nil {
		return err
	}
	dashboardWidgets, err := json.Marshal(config.DashboardWidgets)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `
		INSERT INTO app_configs (
			school_id, feature_flags, dashboard_widgets, min_supported_version,
			force_update_message, updated_by, updated_at
		)
		VALUES ($1, $2::jsonb, $3::jsonb, $4, $5, $6, now())
		ON CONFLICT (school_id) DO UPDATE
		SET feature_flags = excluded.feature_flags,
		    dashboard_widgets = excluded.dashboard_widgets,
		    min_supported_version = excluded.min_supported_version,
		    force_update_message = excluded.force_update_message,
		    updated_by = excluded.updated_by,
		    updated_at = now()
	`, config.SchoolID, string(featureFlags), string(dashboardWidgets), config.MinSupportedVersion, config.ForceUpdateMessage, config.UpdatedBy)
	return err
}

func (s *Store) ListUsersBySchool(ctx context.Context, schoolID string) ([]models.User, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id::text, coalesce(school_id::text, ''), role, full_name, phone, email, created_at
		FROM users
		WHERE school_id = $1 OR role = 'super_admin'
		ORDER BY created_at DESC
	`, schoolID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := []models.User{}
	for rows.Next() {
		var user models.User
		if err := rows.Scan(&user.ID, &user.SchoolID, &user.Role, &user.FullName, &user.Phone, &user.Email, &user.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, user)
	}
	return items, rows.Err()
}

func (s *Store) UpdateUserRole(ctx context.Context, userID string, role models.Role) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE users
		SET role = $2
		WHERE id = $1
	`, userID, role)
	return err
}

func (s *Store) UpsertDeviceToken(ctx context.Context, userID, token, platform string) error {
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO device_tokens (id, user_id, token, platform, created_at)
		VALUES ($1, $2, $3, $4, now())
		ON CONFLICT (token) DO UPDATE
		SET user_id = excluded.user_id, platform = excluded.platform
	`, uuid.NewString(), userID, token, platform)
	return err
}

func (s *Store) ListDeviceTokensBySchoolRole(ctx context.Context, schoolID string, role models.Role) ([]string, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT dt.token
		FROM device_tokens dt
		JOIN users u ON u.id = dt.user_id
		WHERE u.school_id = $1 AND u.role = $2
	`, schoolID, role)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var tokens []string
	for rows.Next() {
		var token string
		if err := rows.Scan(&token); err != nil {
			return nil, err
		}
		tokens = append(tokens, token)
	}
	return tokens, rows.Err()
}

func (s *Store) CreateAuditEvent(ctx context.Context, event models.AuditEvent) error {
	if event.ID == "" {
		event.ID = uuid.NewString()
	}
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO audit_events (id, school_id, user_id, user_role, action, payload, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, now())
	`, event.ID, event.SchoolID, event.UserID, event.UserRole, event.Action, event.Payload)
	return err
}

func (s *Store) ListAuditEventsBySchool(ctx context.Context, schoolID string, limit int) ([]models.AuditEvent, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT id::text, coalesce(school_id::text,''), coalesce(user_id::text,''), user_role, action, payload, created_at
		FROM audit_events
		WHERE school_id = $1 OR school_id IS NULL
		ORDER BY created_at DESC
		LIMIT $2
	`, schoolID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []models.AuditEvent{}
	for rows.Next() {
		var item models.AuditEvent
		if err := rows.Scan(&item.ID, &item.SchoolID, &item.UserID, &item.UserRole, &item.Action, &item.Payload, &item.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) CreateExam(ctx context.Context, exam models.Exam) (*models.Exam, error) {
	if exam.ID == "" {
		exam.ID = uuid.NewString()
	}
	if exam.CreatedAt.IsZero() {
		exam.CreatedAt = time.Now()
	}

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO exams (id, school_id, class, title, term, exam_date, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, exam.ID, exam.SchoolID, exam.Class, exam.Title, exam.Term, exam.Date, exam.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &exam, nil
}

func (s *Store) GetExam(ctx context.Context, examID string) (*models.Exam, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id, school_id, class, title, term, exam_date, created_at
		FROM exams
		WHERE id = $1
	`, examID)

	var exam models.Exam
	if err := row.Scan(&exam.ID, &exam.SchoolID, &exam.Class, &exam.Title, &exam.Term, &exam.Date, &exam.CreatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &exam, nil
}

func (s *Store) AddScores(ctx context.Context, examID string, scores []models.Score) error {
	for _, score := range scores {
		if score.ID == "" {
			score.ID = uuid.NewString()
		}
		if score.CreatedAt.IsZero() {
			score.CreatedAt = time.Now()
		}
		_, err := s.db.ExecContext(ctx, `
			INSERT INTO scores (id, exam_id, student_id, subject, score, max_score, grade, created_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		`, score.ID, examID, score.StudentID, score.Subject, score.Score, score.MaxScore, score.Grade, score.CreatedAt)
		if err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) ListScoresByStudent(ctx context.Context, studentID string) ([]models.Score, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, exam_id, student_id, subject, score, max_score, grade, created_at
		FROM scores
		WHERE student_id = $1
		ORDER BY created_at DESC
	`, studentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []models.Score
	for rows.Next() {
		var score models.Score
		if err := rows.Scan(&score.ID, &score.ExamID, &score.StudentID, &score.Subject,
			&score.Score, &score.MaxScore, &score.Grade, &score.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, score)
	}
	return items, rows.Err()
}

func (s *Store) GetStudentByClassRoll(ctx context.Context, schoolID, classLabel string, rollNumber int) (*models.Student, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id, school_id, full_name, class_label, roll_number, date_of_birth, house, parent_phone, admission_year, created_at
		FROM students
		WHERE school_id = $1 AND class_label = $2 AND roll_number = $3
	`, schoolID, classLabel, rollNumber)

	var student models.Student
	if err := row.Scan(&student.ID, &student.SchoolID, &student.FullName, &student.ClassLabel, &student.RollNumber,
		&student.DateOfBirth, &student.House, &student.ParentPhone, &student.AdmissionYear, &student.CreatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &student, nil
}

func (s *Store) FindStudentByClassRollGlobal(ctx context.Context, classLabel string, rollNumber int) (*models.Student, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, school_id, full_name, class_label, roll_number, date_of_birth, house, parent_phone, admission_year, created_at
		FROM students
		WHERE class_label = $1 AND roll_number = $2
		LIMIT 2
	`, classLabel, rollNumber)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var students []models.Student
	for rows.Next() {
		var student models.Student
		if err := rows.Scan(&student.ID, &student.SchoolID, &student.FullName, &student.ClassLabel, &student.RollNumber,
			&student.DateOfBirth, &student.House, &student.ParentPhone, &student.AdmissionYear, &student.CreatedAt); err != nil {
			return nil, err
		}
		students = append(students, student)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(students) == 0 {
		return nil, nil
	}
	if len(students) > 1 {
		return nil, errors.New("multiple students matched; school disambiguation required")
	}
	return &students[0], nil
}

func nullString(value string) sql.NullString {
	if value == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: value, Valid: true}
}
