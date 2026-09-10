"""
attendance_log.api
==================

Whitelisted REST endpoints consumed by the Flutter mobile app.

Login: use Frappe's built-in POST /api/method/login (usr, pwd). It sets the
`sid` session cookie which the client stores and sends on every request below.
No custom login code is needed here.

All endpoints reject Guest and resolve the Employee from frappe.session.user
(never trust a client-supplied employee id).
"""

import json
import frappe
from frappe import _
from frappe.utils import today, getdate, now_datetime, add_days, cint, flt, get_datetime

from attendance_log import face_match
from attendance_log.attendance_logic import process_punch


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def _require_employee():
    if frappe.session.user == "Guest":
        frappe.throw(_("Not authenticated"), frappe.AuthenticationError)
    emp = frappe.db.get_value(
        "Employee", {"user_id": frappe.session.user},
        ["name", "employee_name", "company"], as_dict=True)
    if not emp:
        frappe.throw(
            _("No Employee is linked to user {0}").format(frappe.session.user))
    return emp


def _save_selfie(employee, prefix="selfie"):
    """Save the uploaded file (request.files['selfie_image'] or 'file') and
    return its file_url. Returns None if no file was uploaded."""
    files = getattr(frappe.request, "files", None)
    if not files:
        return None
    fobj = files.get("selfie_image") or files.get("file")
    if not fobj:
        return None
    content = fobj.stream.read()
    fname = f"{prefix}_{employee}_{frappe.generate_hash(length=8)}.jpg"
    saved = frappe.get_doc({
        "doctype": "File",
        "file_name": fname,
        "is_private": 1,
        "content": content,
    })
    saved.insert(ignore_permissions=True)
    return saved.file_url


# ---------------------------------------------------------------------------
# 4.1 mark_attendance  (POST, multipart/form-data)
# ---------------------------------------------------------------------------
@frappe.whitelist()
def mark_attendance(punch_type=None, latitude=None, longitude=None,
                    device_info=None):
    emp = _require_employee()

    if punch_type not in ("Check In", "Check Out"):
        frappe.throw(_("punch_type must be 'Check In' or 'Check Out'"))
    if latitude in (None, "") or longitude in (None, ""):
        frappe.throw(_("latitude and longitude are required"))

    selfie_url = _save_selfie(emp["name"])
    if not selfie_url:
        frappe.throw(_("selfie_image file is required"))

    doc = frappe.get_doc({
        "doctype": "NHS Attendance Punch",
        "employee": emp["name"],
        "attendance_date": today(),
        "punch_type": punch_type,
        "punch_datetime": now_datetime(),
        "selfie_image": selfie_url,
        "latitude": float(latitude),
        "longitude": float(longitude),
        "device_info": device_info,
        "source": "Mobile App",
    })
    doc.insert(ignore_permissions=True)  # controller after_insert runs pipeline
    doc.reload()

    return {
        "punch": doc.name,
        "status": doc.status,
        "face_match_status": doc.face_match_status,
        "face_match_score": doc.face_match_score,
        "within_geofence": bool(doc.within_geofence),
        "distance_from_location_meter": doc.distance_from_location_meter,
        "is_late": bool(doc.is_late),
        "late_by_minutes": doc.late_by_minutes,
        "is_early": bool(doc.is_early),
        "early_by_minutes": doc.early_by_minutes,
        "message": _result_message(doc),
    }


def _result_message(doc):
    if doc.status == "Present":
        return "Attendance marked: Present."
    if doc.status == "Late":
        return f"Marked Present but late by {doc.late_by_minutes or 0} minutes."
    if doc.status == "Early Leaving":
        return f"Early leaving by {doc.early_by_minutes or 0} minutes."
    if doc.status == "Outside Location":
        return "You are outside the allowed location. A regularization has been raised."
    if doc.status == "Face Mismatch":
        return "Face did not match. Pending HR review."
    if doc.status == "Pending Review":
        return "Attendance recorded and pending HR review."
    return doc.status or "Attendance recorded."


# ---------------------------------------------------------------------------
# 4.2 get_today_status  (GET)
# ---------------------------------------------------------------------------
@frappe.whitelist()
def get_today_status():
    emp = _require_employee()
    punches = frappe.get_all(
        "NHS Attendance Punch",
        filters={"employee": emp["name"], "attendance_date": today()},
        fields=["name", "punch_type", "punch_datetime", "status",
                "within_geofence", "face_match_status"],
        order_by="punch_datetime asc")

    check_in = next((p for p in punches if p.punch_type == "Check In"), None)
    check_out = next((p for p in reversed(punches)
                      if p.punch_type == "Check Out"), None)

    if not check_in:
        next_action = "Check In"
    elif not check_out:
        next_action = "Check Out"
    else:
        next_action = None  # both done

    return {
        "employee": emp["name"],
        "employee_name": emp["employee_name"],
        "date": today(),
        "checked_in": bool(check_in),
        "checked_out": bool(check_out),
        "check_in_time": check_in.punch_datetime if check_in else None,
        "check_out_time": check_out.punch_datetime if check_out else None,
        "current_status": (check_out or check_in).status if punches else "Not Marked",
        "next_action": next_action,
        "punches": punches,
    }


# ---------------------------------------------------------------------------
# 4.3 get_attendance_history  (GET)
# ---------------------------------------------------------------------------
@frappe.whitelist()
def get_attendance_history(from_date=None, to_date=None):
    emp = _require_employee()
    to_date = to_date or today()
    from_date = from_date or add_days(to_date, -30)

    punches = frappe.get_all(
        "NHS Attendance Punch",
        filters={
            "employee": emp["name"],
            "attendance_date": ["between", [from_date, to_date]],
        },
        fields=["name", "attendance_date", "punch_type", "punch_datetime",
                "status", "within_geofence", "face_match_status",
                "distance_from_location_meter", "linked_attendance"],
        order_by="punch_datetime desc")

    # attach the linked core Attendance status where present
    for p in punches:
        if p.get("linked_attendance"):
            p["attendance_status"] = frappe.db.get_value(
                "Attendance", p["linked_attendance"], "status")
    return {"from_date": from_date, "to_date": to_date, "records": punches}


# ---------------------------------------------------------------------------
# 4.4 get_my_notifications  (GET)
# ---------------------------------------------------------------------------
@frappe.whitelist()
def get_my_notifications(only_unread=1):
    emp = _require_employee()
    filters = {"employee": emp["name"]}
    if int(only_unread or 0):
        filters["is_read"] = 0
    notes = frappe.get_all(
        "JEW HRMS Notification", filters=filters,
        fields=["name", "notification_type", "title", "message", "is_read",
                "creation", "reference_doctype", "reference_name"],
        order_by="creation desc", limit_page_length=50)
    return {"count": len(notes), "notifications": notes}


@frappe.whitelist()
def mark_notification_read(name):
    emp = _require_employee()
    note = frappe.get_doc("JEW HRMS Notification", name)
    if note.employee != emp["name"]:
        frappe.throw(_("Not permitted"), frappe.PermissionError)
    note.db_set("is_read", 1)
    return {"ok": True}


# ---------------------------------------------------------------------------
# helper endpoint: register / update the caller's face reference (testing aid)
# ---------------------------------------------------------------------------
@frappe.whitelist()
def register_my_face():
    emp = _require_employee()
    selfie_url = _save_selfie(emp["name"], prefix="face")
    if not selfie_url:
        frappe.throw(_("face image file is required"))
    fobj = frappe.get_doc("File", {"file_url": selfie_url})
    with open(fobj.get_full_path(), "rb") as fh:
        encoding = face_match.encode_image(fh.read())

    existing = frappe.db.get_value(
        "JEW Employee Face", {"employee": emp["name"]}, "name")
    if existing:
        face = frappe.get_doc("JEW Employee Face", existing)
    else:
        face = frappe.new_doc("JEW Employee Face")
        face.employee = emp["name"]
        face.registered_by = frappe.session.user
        face.registered_on = now_datetime()
    face.user = frappe.session.user
    face.face_image = selfie_url
    face.face_encoding = encoding
    face.is_active = 1
    face.last_updated_on = now_datetime()
    face.save(ignore_permissions=True)
    return {"employee": emp["name"], "backend": face_match.backend_name(),
            "face": face.name}


# ===========================================================================
# Leave (Frappe HR) + Late/Early (JEW Late Early Application) endpoints
# ===========================================================================
def _resolve_leave_type(requested):
    """Map a UI leave-type label to a real Leave Type record on this site.
    Exact match first, then case-insensitive, then keyword/substring, then a
    LWP fallback for 'loss of pay'-style requests. Logs non-exact resolutions."""
    if not requested:
        frappe.throw(_("leave_type is required"))
    if frappe.db.exists("Leave Type", requested):
        return requested
    all_types = frappe.get_all("Leave Type", pluck="name")
    if not all_types:
        frappe.throw(_("No Leave Type is configured on this site."))
    req = requested.strip().lower()
    for t in all_types:                       # case-insensitive exact
        if t.lower() == req:
            return t
    for t in all_types:                       # substring either way
        if req and (req in t.lower() or t.lower() in req):
            frappe.logger("attendance_log").info(
                f"leave_type '{requested}' -> closest '{t}'")
            return t
    if any(k in req for k in ("loss", "lwp", "unpaid")):
        for t in all_types:
            if frappe.db.get_value("Leave Type", t, "is_lwp"):
                frappe.logger("attendance_log").info(
                    f"leave_type '{requested}' -> LWP '{t}'")
                return t
    frappe.logger("attendance_log").info(
        f"leave_type '{requested}' not matched; using '{all_types[0]}'")
    return all_types[0]


@frappe.whitelist()
def apply_leave(leave_type=None, from_date=None, to_date=None,
                half_day=0, reason=None):
    emp = _require_employee()
    if not from_date or not to_date:
        frappe.throw(_("from_date and to_date are required"))
    if getdate(from_date) > getdate(to_date):
        frappe.throw(_("from_date must be on or before to_date"))
    lt = _resolve_leave_type(leave_type)

    doc = frappe.get_doc({
        "doctype": "Leave Application",
        "employee": emp["name"],
        "leave_type": lt,
        "from_date": from_date,
        "to_date": to_date,
        "half_day": 1 if cint(half_day) else 0,
        "posting_date": today(),
        "status": "Open",
        "company": emp["company"],
        "description": reason or "",
    })
    # Self-service: create as a draft (status "Open"). The approver approves +
    # submits it from Desk (Leave Application is submittable on this site).
    # Do NOT swallow Frappe HR's validation errors — let them reach the client.
    doc.insert(ignore_permissions=True)
    return {"name": doc.name, "status": doc.status, "leave_type": lt,
            "total_leave_days": doc.total_leave_days}


@frappe.whitelist()
def get_my_leave_requests(limit=20):
    emp = _require_employee()
    rows = frappe.get_all(
        "Leave Application",
        filters={"employee": emp["name"]},
        fields=["name", "leave_type", "from_date", "to_date", "half_day",
                "status", "description", "total_leave_days"],
        order_by="creation desc", limit_page_length=cint(limit) or 20)
    return {"count": len(rows), "requests": rows}


@frappe.whitelist()
def get_leave_balance():
    """Remaining balance per leave type the employee has an allocation for,
    computed with Frappe HR's own get_leave_balance_on (handles allocations /
    carry-forward correctly)."""
    emp = _require_employee()
    from hrms.hr.doctype.leave_application.leave_application import (
        get_leave_balance_on,
    )
    allocated = frappe.get_all(
        "Leave Allocation",
        filters={"employee": emp["name"], "docstatus": 1},
        distinct=True, pluck="leave_type")
    balances = {}
    for lt in allocated:
        try:
            balances[lt] = flt(get_leave_balance_on(emp["name"], lt, today()))
        except Exception:
            frappe.logger("attendance_log").info(
                f"leave balance failed for {emp['name']} / {lt}")
    return {"balances": balances, "total": sum(balances.values())}


@frappe.whitelist()
def apply_late_early(application_type=None, application_date=None,
                     expected_time=None, reason=None):
    emp = _require_employee()
    if application_type not in ("Late Coming", "Early Going"):
        frappe.throw(_("application_type must be 'Late Coming' or 'Early Going'"))
    if not application_date:
        frappe.throw(_("application_date is required"))
    if not expected_time:
        frappe.throw(_("expected_time is required"))
    if not reason:
        frappe.throw(_("reason is required"))

    # resolve shift with the SAME mapping used by NHS Attendance Punch
    from attendance_log.attendance_logic import resolve_shift_policy
    shift_name = None
    try:
        policy = resolve_shift_policy(
            frappe._dict({"employee": emp["name"], "shift": None}))
        shift_name = policy.name if policy else None
    except Exception:
        shift_name = None

    doc = frappe.get_doc({
        "doctype": "JEW Late Early Application",
        "employee": emp["name"],
        "employee_name": emp["employee_name"],
        "application_type": application_type,
        "application_date": application_date,
        "expected_time": expected_time,
        "shift": shift_name,
        "reason": reason,
        "status": "Pending",
    })
    doc.insert(ignore_permissions=True)
    return {"name": doc.name, "status": doc.status}


@frappe.whitelist()
def get_my_late_early_requests(limit=20):
    emp = _require_employee()
    rows = frappe.get_all(
        "JEW Late Early Application",
        filters={"employee": emp["name"]},
        fields=["name", "application_type", "application_date", "expected_time",
                "reason", "status"],
        order_by="creation desc", limit_page_length=cint(limit) or 20)
    return {"count": len(rows), "requests": rows}


# ===========================================================================
# Background location tracking (NHS Location Ping) — independent of the
# check-in / punch flow. Called every ~5 min ONLY during the app's active
# windows (09:00-09:30 and 20:30-21:00). Keep this lightweight.
# ===========================================================================
@frappe.whitelist()
def log_location_ping(latitude=None, longitude=None, accuracy_meter=None,
                      window=None, capture_time=None):
    emp = _require_employee()
    if latitude in (None, "") or longitude in (None, ""):
        frappe.throw(_("latitude and longitude are required"))
    if window not in ("Morning", "Evening"):
        frappe.throw(_("window must be 'Morning' or 'Evening'"))

    ct = None
    if capture_time:
        try:
            ct = get_datetime(capture_time)
        except Exception:
            ct = None
    if not ct:
        ct = now_datetime()  # sanity fallback only

    acc = None
    if accuracy_meter not in (None, ""):
        try:
            acc = float(accuracy_meter)
        except Exception:
            acc = None

    doc = frappe.get_doc({
        "doctype": "NHS Location Ping",
        "employee": emp["name"],
        "employee_name": emp["employee_name"],
        "capture_time": ct,
        "window": window,
        "latitude": float(latitude),
        "longitude": float(longitude),
        "accuracy_meter": acc,
    })
    doc.insert(ignore_permissions=True)
    return {"status": "ok", "name": doc.name}


# ===========================================================================
# get_location_path — one employee's ordered movement path for a date+window
# (Desk map page). Restricted to the elevated roles that can read other
# employees' NHS Location Ping (matches the doctype's non-if_owner perms).
# ===========================================================================
@frappe.whitelist()
def get_location_path(employee=None, date=None, window=None):
    allowed = {"System Manager", "HR Manager", "HR User"}
    if not (allowed & set(frappe.get_roles())):
        frappe.throw(_("Not permitted to view location paths."),
                     frappe.PermissionError)
    if not employee or not date or window not in ("Morning", "Evening"):
        frappe.throw(_("employee, date and window (Morning/Evening) are required"))

    start = get_datetime(f"{date} 00:00:00")
    end = get_datetime(f"{date} 23:59:59")
    rows = frappe.get_all(
        "NHS Location Ping",
        filters={
            "employee": employee,
            "window": window,
            "capture_time": ["between", [start, end]],
        },
        fields=["capture_time", "latitude", "longitude", "accuracy_meter"],
        order_by="capture_time asc",
    )
    return {"points": rows, "count": len(rows)}
