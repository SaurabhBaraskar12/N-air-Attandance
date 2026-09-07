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
from frappe.utils import today, getdate, now_datetime, add_days

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
