package main

import (
	"context"
	"log"
	"net/http"
	"time"

	"jnv/backend/internal/auth"
	"jnv/backend/internal/config"
	"jnv/backend/internal/db"
	"jnv/backend/internal/http"
	"jnv/backend/internal/store"
)

func main() {
	cfg := config.Load()

	if cfg.DatabaseURL == "" {
		log.Fatal("DATABASE_URL is required")
	}

	dbConn, err := db.Open(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("failed to open db: %v", err)
	}

	store := store.New(dbConn)

	var authProvider auth.Provider
	switch cfg.AuthMode {
	case "dev":
		authProvider = auth.DevProvider{DefaultPhone: cfg.DevAuthPhone}
	case "firebase":
		firebaseProvider, providerErr := auth.NewFirebaseProvider(
			context.Background(),
			cfg.FirebaseCredentialsFile,
		)
		if providerErr != nil {
			log.Fatalf("failed to initialize firebase auth provider: %v", providerErr)
		}
		authProvider = firebaseProvider
	default:
		log.Fatalf("unsupported AUTH_MODE: %s", cfg.AuthMode)
	}

	server := &http.Server{
		Addr:         cfg.HTTPAddr,
		Handler:      httpapi.API{Store: store, AuthProvider: authProvider}.Router(),
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  30 * time.Second,
	}

	log.Printf("jnv api listening on %s", cfg.HTTPAddr)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("server error: %v", err)
	}
}
