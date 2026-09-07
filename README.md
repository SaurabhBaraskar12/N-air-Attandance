# N-Air Attendance (JEW HRMS Mobile)

Employee attendance with **selfie face-match + GPS geofencing**, integrated with
Frappe HR (`Attendance` / `Employee Checkin`).

## Repository layout
- **`attendance_log/`** — the Frappe app (module *JEW HRMS Mobile*): doctypes,
  business logic (`attendance_logic.py`), whitelisted REST API (`api.py`),
  pluggable face matching (`face_match.py`), Desk workspace.
- **`mobile/`** — the Flutter mobile client (Login / Home / Punch / History /
  Notifications). See `mobile/README.md` for build + LAN base-URL setup.

## Install the app on your phone
Download the APK from the [**Releases**](../../releases) page and open it on
your Android phone. In the app's Login screen → *Server settings*, set the
Server URL to the bench machine's **LAN IP + `:8000`** (not `localhost`).

## Frappe app install (server side)
```bash
bench get-app <this-repo-url>
bench --site <site> install-app attendance_log
bench --site <site> migrate
```
Requires Frappe HR (`hrms`) installed on the site.
