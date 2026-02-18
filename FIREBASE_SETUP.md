# Firebase OTP Setup

This document explains how to run JNV with real Firebase phone OTP.

## 1) Create Firebase project

1. Open Firebase Console.
2. Create a project (or use existing).
3. Enable **Authentication -> Sign-in method -> Phone**.
4. Add your Android app package (from Flutter project).

## 2) Mobile app config (Flutter)

Place Firebase config files:

- Android: `mobile/android/app/google-services.json`
- iOS: `mobile/ios/Runner/GoogleService-Info.plist` (if iOS needed)

Then run:

```bash
cd mobile
flutter pub get
flutter run
```

If Firebase is configured correctly, OTP flow uses real SMS verification.
If not configured, app falls back to demo OTP (`123456`) for development only.

## 3) Backend Firebase token verification

Backend already supports Firebase auth mode.

Set in `backend/.env`:

```env
AUTH_MODE=firebase
FIREBASE_CREDENTIALS_FILE=/absolute/path/to/firebase-service-account.json
DATABASE_URL=postgres://...
HTTP_ADDR=:8080
```

Run backend with firebase build tag:

```bash
cd backend
go run -tags firebase ./cmd/api
```

## 4) Role mapping

- Firebase ID token is verified by backend.
- If user does not exist, backend auto-creates user.
- Role can be set using custom claims (optional). Default role is parent.

## 5) Staff portal URL to share with schools

For schools to upload student info and marks, share the deployed web portal URL.

Example:

- `https://staff.jnv-app.in`

The portal should point to your backend API URL and use secure HTTPS.

## 6) Recommended production checklist

- Use Firebase App Check (optional but recommended).
- Restrict API CORS origin from `*` to your frontend domains.
- Use HTTPS for both app API and staff portal.
- Add monitoring/logging for OTP and auth failures.
