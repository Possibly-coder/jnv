# JNV Parent Portal

Production-ready monorepo for the JNV parent mobile app and staff web portal.

## Structure

- `backend/` Go API (scores, announcements, auth, uploads)
- `web/` React + Vite admin/staff portal
- `mobile/` Flutter parent app

## Quick start (later)

- Backend: `cd backend && go run ./cmd/api`
- Web: `cd web && npm install && npm run dev`
- Mobile: `cd mobile && flutter run`

## Notes

- Auth: Phone OTP (Firebase), server-issued role tokens
- Uploads: Excel/CSV to S3-compatible storage
- DB: Postgres

## Backend setup (dev)

1. Create the database and run the SQL in `backend/migrations/001_init.sql`.
2. Set env vars:
   - `DATABASE_URL`
   - `AUTH_MODE=dev`
   - `DEV_AUTH_PHONE=+919999999999`
3. Run: `cd backend && go run ./cmd/api`

Auth mode `dev` expects `Authorization: Bearer dev:<phone>:<role>`.
