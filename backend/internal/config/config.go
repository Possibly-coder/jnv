package config

import (
	"bufio"
	"bytes"
	"os"
	"strings"
)

type Config struct {
	Env         string
	HTTPAddr    string
	DatabaseURL string
	AuthMode    string
	DevAuthPhone string
	FirebaseProjectID string
	FirebaseCredentialsFile string
}

func Load() Config {
	loadDotEnv()
	return Config{
		Env:         getEnv("APP_ENV", "development"),
		HTTPAddr:    getEnv("HTTP_ADDR", ":8080"),
		DatabaseURL: getEnv("DATABASE_URL", ""),
		AuthMode:    getEnv("AUTH_MODE", "dev"),
		DevAuthPhone: getEnv("DEV_AUTH_PHONE", "+919999999999"),
		FirebaseProjectID: getEnv("FIREBASE_PROJECT_ID", ""),
		FirebaseCredentialsFile: getEnv("FIREBASE_CREDENTIALS_FILE", ""),
	}
}

func getEnv(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}

func loadDotEnv() {
	path := ".env"
	content, err := os.ReadFile(path)
	if err != nil {
		return
	}

	scanner := bufio.NewScanner(bytes.NewReader(content))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		val := strings.Trim(strings.TrimSpace(parts[1]), `"'`)
		if key == "" {
			continue
		}
		if os.Getenv(key) == "" {
			_ = os.Setenv(key, val)
		}
	}
}
