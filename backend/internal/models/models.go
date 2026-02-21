package models

import "time"

type Role string

const (
	RoleSuperAdmin Role = "super_admin"
	RoleAdmin      Role = "admin"
	RoleStaff      Role = "staff"
	RoleTeacher    Role = "teacher"
	RoleParent     Role = "parent"
)

type School struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	State     string    `json:"state"`
	District  string    `json:"district"`
	CreatedAt time.Time `json:"created_at"`
}

type User struct {
	ID        string    `json:"id"`
	SchoolID  string    `json:"school_id"`
	Role      Role      `json:"role"`
	FullName  string    `json:"full_name"`
	Phone     string    `json:"phone"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"created_at"`
}

type Student struct {
	ID            string    `json:"id"`
	SchoolID      string    `json:"school_id"`
	FullName      string    `json:"full_name"`
	ClassLabel    string    `json:"class_label"`
	RollNumber    int       `json:"roll_number"`
	DateOfBirth   time.Time `json:"date_of_birth"`
	House         string    `json:"house"`
	ParentPhone   string    `json:"parent_phone"`
	AdmissionYear int       `json:"admission_year"`
	CreatedAt     time.Time `json:"created_at"`
}

type ParentLink struct {
	ID        string    `json:"id"`
	ParentID  string    `json:"parent_id"`
	StudentID string    `json:"student_id"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

type ParentLinkApprovalItem struct {
	ID          string    `json:"id"`
	ParentID    string    `json:"parent_id"`
	ParentName  string    `json:"parent_name"`
	ParentPhone string    `json:"parent_phone"`
	StudentID   string    `json:"student_id"`
	StudentName string    `json:"student_name"`
	ClassLabel  string    `json:"class_label"`
	RollNumber  int       `json:"roll_number"`
	Status      string    `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
}

type Subject struct {
	ID        string    `json:"id"`
	SchoolID  string    `json:"school_id"`
	Class     string    `json:"class"`
	Name      string    `json:"name"`
	Locked    bool      `json:"locked"`
	CreatedAt time.Time `json:"created_at"`
}

type Exam struct {
	ID        string    `json:"id"`
	SchoolID  string    `json:"school_id"`
	Class     string    `json:"class"`
	Title     string    `json:"title"`
	Term      string    `json:"term"`
	Date      time.Time `json:"date"`
	CreatedAt time.Time `json:"created_at"`
}

type Score struct {
	ID        string    `json:"id"`
	ExamID    string    `json:"exam_id"`
	StudentID string    `json:"student_id"`
	Subject   string    `json:"subject"`
	Score     float32   `json:"score"`
	MaxScore  float32   `json:"max_score"`
	Grade     string    `json:"grade"`
	CreatedAt time.Time `json:"created_at"`
}

type Announcement struct {
	ID        string    `json:"id"`
	SchoolID  string    `json:"school_id"`
	Title     string    `json:"title"`
	Content   string    `json:"content"`
	Category  string    `json:"category"`
	Priority  string    `json:"priority"`
	Published bool      `json:"published"`
	CreatedBy string    `json:"created_by"`
	CreatedAt time.Time `json:"created_at"`
}

type Event struct {
	ID          string     `json:"id"`
	SchoolID    string     `json:"school_id"`
	Title       string     `json:"title"`
	Description string     `json:"description"`
	EventDate   time.Time  `json:"event_date"`
	StartTime   string     `json:"start_time"`
	EndTime     string     `json:"end_time"`
	Location    string     `json:"location"`
	Audience    string     `json:"audience"`
	Category    string     `json:"category"`
	Published   bool       `json:"published"`
	PublishedAt *time.Time `json:"published_at,omitempty"`
	CreatedBy   string     `json:"created_by"`
	CreatedAt   time.Time  `json:"created_at"`
}

type DashboardWidget struct {
	Key   string `json:"key"`
	Label string `json:"label"`
	Value string `json:"value"`
	Hint  string `json:"hint"`
	Icon  string `json:"icon"`
}

type AppConfig struct {
	SchoolID            string            `json:"school_id"`
	FeatureFlags        map[string]bool   `json:"feature_flags"`
	DashboardWidgets    []DashboardWidget `json:"dashboard_widgets"`
	MinSupportedVersion string            `json:"min_supported_version"`
	ForceUpdateMessage  string            `json:"force_update_message"`
	UpdatedBy           string            `json:"updated_by"`
	UpdatedAt           time.Time         `json:"updated_at"`
}

type DeviceToken struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	Token     string    `json:"token"`
	Platform  string    `json:"platform"`
	CreatedAt time.Time `json:"created_at"`
}

type AuditEvent struct {
	ID        string    `json:"id"`
	SchoolID  string    `json:"school_id"`
	UserID    string    `json:"user_id"`
	UserRole  string    `json:"user_role"`
	Action    string    `json:"action"`
	Payload   string    `json:"payload"`
	CreatedAt time.Time `json:"created_at"`
}
