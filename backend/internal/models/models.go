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
	ID             string    `json:"id"`
	SchoolID       string    `json:"school_id"`
	FullName       string    `json:"full_name"`
	ClassLabel     string    `json:"class_label"`
	RollNumber     int       `json:"roll_number"`
	DateOfBirth    time.Time `json:"date_of_birth"`
	House          string    `json:"house"`
	ParentPhone    string    `json:"parent_phone"`
	AdmissionYear  int       `json:"admission_year"`
	CreatedAt      time.Time `json:"created_at"`
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
	ID         string    `json:"id"`
	ExamID     string    `json:"exam_id"`
	StudentID  string    `json:"student_id"`
	Subject    string    `json:"subject"`
	Score      float32   `json:"score"`
	MaxScore   float32   `json:"max_score"`
	Grade      string    `json:"grade"`
	CreatedAt  time.Time `json:"created_at"`
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
