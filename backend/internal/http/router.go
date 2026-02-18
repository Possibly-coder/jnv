package httpapi

import (
	"net/http"

	"jnv/backend/internal/auth"
	"jnv/backend/internal/http/handlers"
	"jnv/backend/internal/store"
)

type API struct {
	Store        *store.Store
	AuthProvider auth.Provider
}

func (a API) Router() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", handlers.Health)

	authHandler := handlers.AuthHandler{Store: a.Store, AuthProvider: a.AuthProvider}
	mux.HandleFunc("POST /api/v1/auth/session", authHandler.Session)

	protected := RequireAuth(a.AuthProvider, a.Store)

	mux.Handle("GET /api/v1/me", protected(http.HandlerFunc(handlers.Me)))

	announcementHandler := handlers.AnnouncementHandler{Store: a.Store}
	mux.Handle("GET /api/v1/announcements", protected(http.HandlerFunc(announcementHandler.List)))
	mux.Handle("POST /api/v1/announcements", protected(http.HandlerFunc(announcementHandler.Create)))
	mux.Handle("POST /api/v1/announcements/{id}/publish", protected(http.HandlerFunc(announcementHandler.Publish)))

	parentLinkHandler := handlers.ParentLinkHandler{Store: a.Store}
	mux.Handle("POST /api/v1/parent-links", protected(http.HandlerFunc(parentLinkHandler.Create)))
	mux.Handle("POST /api/v1/parent-links/request", protected(http.HandlerFunc(parentLinkHandler.CreateByClassRoll)))
	mux.Handle("GET /api/v1/parent-links/pending", protected(http.HandlerFunc(parentLinkHandler.ListPending)))
	mux.Handle("POST /api/v1/parent-links/{id}/approve", protected(http.HandlerFunc(parentLinkHandler.Approve)))

	parentsHandler := handlers.ParentsHandler{Store: a.Store}
	mux.Handle("GET /api/v1/parents/me/overview", protected(http.HandlerFunc(parentsHandler.Overview)))

	examHandler := handlers.ExamHandler{Store: a.Store}
	mux.Handle("POST /api/v1/exams", protected(http.HandlerFunc(examHandler.Create)))

	scoresHandler := handlers.ScoresHandler{Store: a.Store}
	mux.Handle("POST /api/v1/exams/{id}/scores", protected(http.HandlerFunc(scoresHandler.AddForExam)))
	mux.Handle("POST /api/v1/exams/{id}/scores/csv", protected(http.HandlerFunc(scoresHandler.UploadCSV)))
	mux.Handle("POST /api/v1/exams/{id}/scores/upload", protected(http.HandlerFunc(scoresHandler.UploadFile)))
	mux.Handle("GET /api/v1/students/{id}/scores", protected(http.HandlerFunc(scoresHandler.ListByStudent)))

	studentsHandler := handlers.StudentsHandler{Store: a.Store}
	mux.Handle("GET /api/v1/students", protected(http.HandlerFunc(studentsHandler.List)))
	mux.Handle("POST /api/v1/students", protected(http.HandlerFunc(studentsHandler.Create)))
	mux.Handle("GET /api/v1/students/lookup", protected(http.HandlerFunc(studentsHandler.Lookup)))

	referenceHandler := handlers.ReferenceHandler{Store: a.Store}
	mux.Handle("GET /api/v1/reference/districts", protected(http.HandlerFunc(referenceHandler.Districts)))

	return withCORS(mux)
}
