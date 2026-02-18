# Running the Project

This guide explains how to run the backend and frontend locally.

See also: `FIREBASE_SETUP.md` for real OTP setup.

## 1) Backend (Go API)

### Prerequisites
- Go installed
- PostgreSQL running
- Database `jnv` created

### Configure environment
Create `backend/.env` with:

```env
DATABASE_URL=postgres://YOUR_DB_USER:YOUR_DB_PASSWORD@localhost:5432/jnv
AUTH_MODE=dev
DEV_AUTH_PHONE=+919999999999
HTTP_ADDR=:8080
```

### Run migration
```bash
psql -U YOUR_DB_USER -d jnv -f backend/migrations/001_init.sql
psql -U YOUR_DB_USER -d jnv -f backend/migrations/002_seed_district_schools.sql
```

### Start backend
```bash
cd backend
go run ./cmd/api
```

Backend runs on: `http://localhost:8080`

### Firebase auth mode (production path)

Set:

```env
AUTH_MODE=firebase
FIREBASE_CREDENTIALS_FILE=/absolute/path/to/firebase-service-account.json
```

Run backend with firebase build tag:

```bash
cd backend
go run -tags firebase ./cmd/api
```

---

## 2) Frontend - Staff Portal (React + Vite)

### Start web app
```bash
cd web
npm install
npm run dev
```

Web runs on: `http://localhost:5173`

When deployed, share this staff portal URL with schools.

### In the web UI header
- API base: `http://localhost:8080`
- Token: `dev:+919999999999:admin`

Token format:
`dev:<phone>:<role>`
Examples:
- `dev:+919999999999:admin`
- `dev:+919999999999:staff`

---

## 3) Frontend - Parent Mobile App (Flutter)

### Start mobile app
```bash
cd mobile
flutter pub get
flutter run
```

For Firebase OTP, add your Firebase app configs:
- Android: `mobile/android/app/google-services.json`
- iOS: `mobile/ios/Runner/GoogleService-Info.plist`

If platform folders are missing:
```bash
flutter create .
flutter run
```

---

## Quick health check

```bash
curl http://localhost:8080/healthz
```

Expected:
```json
{"status":"ok"}
```
