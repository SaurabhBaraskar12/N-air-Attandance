# Attendance Log — Flutter mobile app

Employee attendance client for the Frappe **`attendance_log`** app: selfie
face-match + GPS geofencing, integrated with Frappe HR (`Attendance` /
`Employee Checkin`).

## Screens
1. **Login** — username + password → Frappe `/api/method/login`; the `sid`
   session cookie is stored with `flutter_secure_storage` and sent on every
   request. A collapsible "Server settings" field sets the base URL.
2. **Home** — today's status (check-in/out times, status badge) + big
   **Check In / Check Out** buttons (only the next valid action is enabled,
   driven by `get_today_status`).
3. **Punch** — front-camera selfie + current GPS (`geolocator`), preview,
   then `mark_attendance` (multipart). Shows the returned status
   (Present / Late / Outside Location / Face Mismatch / …).
4. **History** — last 30 days of punches with color-coded status badges.
5. **Notifications** — unread `JEW HRMS Notification` items.

## IMPORTANT — base URL for a real phone
`localhost` on the phone does **not** reach the PC running the bench. Set the
base URL to the bench machine's LAN IP, e.g. `http://192.168.1.50:8000`:

- Find it on the bench machine: `ip addr` (WSL) or `ipconfig` (Windows).
- The Frappe site here is `mysite.local`; Frappe resolves the site from the
  `Host` header. The dev server already responds on the machine IP:8000. If
  you get a "site not found", either (a) run the site as the bench's default
  site, or (b) add the app behind a host that maps to `mysite.local`.
- Defaults in `lib/api_service.dart`: `http://10.0.2.2:8000` (the Android
  **emulator's** alias for the host). Override it on the Login screen for a
  physical device.

## Permissions
`android/app/src/main/AndroidManifest.xml` must include (added by
`setup_android.sh` / manually):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```
For plain-HTTP (dev) also set `android:usesCleartextTraffic="true"` on
`<application>`. Camera & location are requested at runtime by the app.

## Build
```bash
flutter pub get
flutter build apk --debug      # debug APK for testing
flutter build apk --release    # release APK once verified
```
The APK is written to `build/app/outputs/flutter-apk/app-debug.apk`
(or `app-release.apk`).

## Files
```
lib/
  main.dart                 app entry + theme + auth gate
  api_service.dart          Frappe API client (login, sid cookie, endpoints)
  widgets.dart              StatusBadge + ErrorBanner
  screens/
    login_screen.dart
    home_screen.dart
    punch_screen.dart       camera + GPS + submit
    history_screen.dart
    notifications_screen.dart
```
