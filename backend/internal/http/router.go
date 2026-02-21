package httpapi

import (
	"net/http"
	"time"

	"jnv/backend/internal/auth"
	"jnv/backend/internal/http/handlers"
	"jnv/backend/internal/notify"
	"jnv/backend/internal/store"
)

type API struct {
	Store         *store.Store
	AuthProvider  auth.Provider
	Notifier      notify.Sender
	CORSAllowList []string
}

func (a API) Router() http.Handler {
	mux := http.NewServeMux()
	handlers.SetAuditStore(a.Store)

	mux.HandleFunc("GET /healthz", handlers.Health)

	authHandler := handlers.AuthHandler{Store: a.Store, AuthProvider: a.AuthProvider}
	authLimiter := newAuthRateLimiter(30, time.Minute)
	mux.Handle("POST /api/v1/auth/session", withAuthRateLimit(http.HandlerFunc(authHandler.Session), authLimiter))

	protected := RequireAuth(a.AuthProvider, a.Store)

	mux.Handle("GET /api/v1/me", protected(http.HandlerFunc(handlers.Me)))

	announcementHandler := handlers.AnnouncementHandler{Store: a.Store, Notifier: a.Notifier}
	mux.Handle("GET /api/v1/announcements", protected(http.HandlerFunc(announcementHandler.List)))
	mux.Handle("POST /api/v1/announcements", protected(http.HandlerFunc(announcementHandler.Create)))
	mux.Handle("POST /api/v1/announcements/{id}/publish", protected(http.HandlerFunc(announcementHandler.Publish)))
	mux.Handle("DELETE /api/v1/announcements/{id}", protected(http.HandlerFunc(announcementHandler.Delete)))

	eventsHandler := handlers.EventsHandler{Store: a.Store, Notifier: a.Notifier}
	mux.Handle("GET /api/v1/events", protected(http.HandlerFunc(eventsHandler.List)))
	mux.Handle("POST /api/v1/events", protected(http.HandlerFunc(eventsHandler.Create)))
	mux.Handle("POST /api/v1/events/{id}/publish", protected(http.HandlerFunc(eventsHandler.Publish)))
	mux.Handle("DELETE /api/v1/events/{id}", protected(http.HandlerFunc(eventsHandler.Delete)))

	appConfigHandler := handlers.AppConfigHandler{Store: a.Store}
	mux.Handle("GET /api/v1/app-config", protected(http.HandlerFunc(appConfigHandler.Get)))
	mux.Handle("POST /api/v1/app-config", protected(http.HandlerFunc(appConfigHandler.Upsert)))

	parentLinkHandler := handlers.ParentLinkHandler{Store: a.Store}
	mux.Handle("POST /api/v1/parent-links", protected(http.HandlerFunc(parentLinkHandler.Create)))
	mux.Handle("POST /api/v1/parent-links/request", protected(http.HandlerFunc(parentLinkHandler.CreateByClassRoll)))
	mux.Handle("GET /api/v1/parent-links/pending", protected(http.HandlerFunc(parentLinkHandler.ListPending)))
	mux.Handle("POST /api/v1/parent-links/{id}/approve", protected(http.HandlerFunc(parentLinkHandler.Approve)))

	parentsHandler := handlers.ParentsHandler{Store: a.Store}
	mux.Handle("GET /api/v1/parents/me/overview", protected(http.HandlerFunc(parentsHandler.Overview)))

	examHandler := handlers.ExamHandler{Store: a.Store}
	mux.Handle("POST /api/v1/exams", protected(http.HandlerFunc(examHandler.Create)))

	scoresHandler := handlers.ScoresHandler{Store: a.Store, Notifier: a.Notifier}
	mux.Handle("POST /api/v1/exams/{id}/scores", protected(http.HandlerFunc(scoresHandler.AddForExam)))
	mux.Handle("POST /api/v1/exams/{id}/scores/csv", protected(http.HandlerFunc(scoresHandler.UploadCSV)))
	mux.Handle("POST /api/v1/exams/{id}/scores/upload", protected(http.HandlerFunc(scoresHandler.UploadFile)))
	mux.Handle("GET /api/v1/students/{id}/scores", protected(http.HandlerFunc(scoresHandler.ListByStudent)))

	studentsHandler := handlers.StudentsHandler{Store: a.Store}
	mux.Handle("GET /api/v1/students", protected(http.HandlerFunc(studentsHandler.List)))
	mux.Handle("POST /api/v1/students", protected(http.HandlerFunc(studentsHandler.Create)))
	mux.Handle("POST /api/v1/students/upload", protected(http.HandlerFunc(studentsHandler.Upload)))
	mux.Handle("GET /api/v1/students/lookup", protected(http.HandlerFunc(studentsHandler.Lookup)))

	referenceHandler := handlers.ReferenceHandler{Store: a.Store}
	mux.Handle("GET /api/v1/reference/districts", protected(http.HandlerFunc(referenceHandler.Districts)))

	usersHandler := handlers.UsersHandler{Store: a.Store}
	mux.Handle("GET /api/v1/users", protected(http.HandlerFunc(usersHandler.List)))
	mux.Handle("POST /api/v1/users/{id}/role", protected(http.HandlerFunc(usersHandler.UpdateRole)))

	devicesHandler := handlers.DevicesHandler{Store: a.Store}
	mux.Handle("POST /api/v1/devices/token", protected(http.HandlerFunc(devicesHandler.RegisterToken)))

	auditLogsHandler := handlers.AuditLogsHandler{Store: a.Store}
	mux.Handle("GET /api/v1/audit-logs", protected(http.HandlerFunc(auditLogsHandler.List)))

	return withCORS(mux, a.CORSAllowList)
}
