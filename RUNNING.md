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
CORS_ALLOWED_ORIGINS=http://localhost:5173,http://localhost:3000
```

### Run migration
```bash
psql -U YOUR_DB_USER -d jnv -f backend/migrations/001_init.sql
psql -U YOUR_DB_USER -d jnv -f backend/migrations/002_seed_district_schools.sql
# Optional but recommended for UI testing/demo data:
psql -U YOUR_DB_USER -d jnv -f backend/migrations/003_seed_demo_data.sql
psql -U YOUR_DB_USER -d jnv -f backend/migrations/004_add_events_and_app_config.sql
psql -U YOUR_DB_USER -d jnv -f backend/migrations/005_seed_events_and_app_config.sql
psql -U YOUR_DB_USER -d jnv -f backend/migrations/006_security_notifications_versioning.sql
psql -U YOUR_DB_USER -d jnv -f backend/migrations/007_add_audit_events.sql
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
# optional: copy env and set local backend
cp .env.example .env
npm run dev
```

Web runs on: `http://localhost:5173`

When deployed, share this staff portal URL with schools.

### In the web UI header
- Token: `dev:+919999999999:admin`

API base can be configured via `web/.env`:
`VITE_API_BASE_URL=http://localhost:8080`

If not set, default fallback is:
`https://jnv-web.onrender.com`

Firebase web login env vars (`web/.env`):
- `VITE_FIREBASE_API_KEY`
- `VITE_FIREBASE_AUTH_DOMAIN`
- `VITE_FIREBASE_PROJECT_ID`
- `VITE_FIREBASE_APP_ID`

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

To use local backend while testing:
```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.8:8080
```

If `API_BASE_URL` is not provided, fallback is:
`https://jnv-web.onrender.com`

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

## Bootstrap first admin user

If you login via Firebase Web Google auth, the backend may store identity in `users.phone` as:

- `email:<your-email>`

If you login via Firebase Phone auth, it stores:

- `+91XXXXXXXXXX` (or normalized phone format)

Use SQL to promote first admin:

```sql
UPDATE users
SET role = 'admin'
WHERE phone = 'email:your-google-email@example.com';
```

Or for phone login:

```sql
UPDATE users
SET role = 'admin'
WHERE phone = '+919999999999';
```

Optional check:

```sql
SELECT id, full_name, phone, email, role
FROM users
ORDER BY created_at DESC;
```

## Student bulk upload template

Use this sample file for student master bulk import:

- `examples/student_upload_template.csv`

Upload via web portal section: `Student Master Data` -> `Upload students`.
