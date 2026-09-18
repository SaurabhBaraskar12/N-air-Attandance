"""
attendance_log.attendance_logic
===============================

Core business logic for an NHS Attendance Punch. Kept in ONE place so both the
whitelisted API (attendance_log.api.mark_attendance) and the DocType controller
run identical logic. `process_punch(doc)` is the single entry point, invoked
from the controller's after_insert hook. The API just builds + inserts the doc
and then reads back the computed result.

Pipeline (simplified — no face match, no location blocking):
  1. Geofence (informational) -> matched_location, distance, within_geofence
     (recorded so the admin can see WHERE the punch happened; never blocks).
  2. Shift/late-early -> is_late/is_early + minutes vs. the attendance windows.
  3. Location ping -> upsert a single-point NHS Location Ping for the map.
  4. Sync into HR core -> Employee Checkin (+ Attendance = Present).
  5. Notifications -> JEW HRMS Notification.

Attendance windows (local server time), used when no JEW Shift Attendance
Policy is configured for the employee:
  * Check In  on-time 09:00-09:30  (start 09:00 + 30 min grace) -> after = late
  * Check Out on-time 20:30-21:00  (end   21:00 + 30 min grace) -> before = early

Shift mapping: the employee's shift is resolved in resolve_shift_policy() in
this order:
  a) NHS Attendance Punch.shift if already set,
  b) an active Shift Assignment / Employee.default_shift (Frappe HR) whose
     Shift Type name == JEW Shift Attendance Policy.shift_name,
  c) the single active JEW Shift Attendance Policy if only one exists,
  d) None -> the default windows above are used.
"""

import json
import math
import frappe
from frappe.utils import (
    now_datetime, get_datetime, getdate, get_time, flt, cint, today,
)

# Fixed, company-wide attendance windows (local server time). Applied to every
# employee for the late/early calculation, regardless of any shift policy.
DEFAULT_CHECKIN_START = "09:00:00"      # morning check-in start
DEFAULT_CHECKIN_GRACE_MIN = 30          # on-time until 09:30 -> after = late
DEFAULT_CHECKOUT_END = "21:00:00"       # evening check-out end (9:00 PM)
DEFAULT_CHECKOUT_GRACE_MIN = 30         # on-time from 20:30 -> before = early


# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------
def haversine_meters(lat1, lon1, lat2, lon2):
    """Great-circle distance in meters between two lat/long points."""
    R = 6371000.0  # earth radius, meters
    p1, p2 = math.radians(flt(lat1)), math.radians(flt(lat2))
    dphi = math.radians(flt(lat2) - flt(lat1))
    dlmb = math.radians(flt(lon2) - flt(lon1))
    a = (math.sin(dphi / 2) ** 2
         + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2)
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _minutes_between_times(t_later, t_earlier):
    """Difference in whole minutes between two datetime.time objects."""
    def mins(t):
        return t.hour * 60 + t.minute + t.second / 60.0
    return int(round(mins(t_later) - mins(t_earlier)))


# ---------------------------------------------------------------------------
# step 1: geofence (informational only — never blocks the punch)
# ---------------------------------------------------------------------------
def resolve_location(doc):
    """Return (location_name, allowed_radius). Assignment first, else nearest."""
    assign = frappe.db.get_value(
        "JEW Employee Location Assignment",
        {"employee": doc.employee, "is_active": 1},
        ["location", "radius_meter"], as_dict=True,
    )
    if assign and assign.get("location"):
        loc = frappe.db.get_value(
            "JEW Attendance Location", assign["location"],
            ["name", "latitude", "longitude", "default_radius_meter"],
            as_dict=True,
        )
        if loc:
            radius = cint(assign.get("radius_meter")) or cint(
                loc.get("default_radius_meter")) or 100
            return loc, radius

    # fallback: nearest active location to the punch
    locs = frappe.get_all(
        "JEW Attendance Location", filters={"is_active": 1},
        fields=["name", "latitude", "longitude", "default_radius_meter"],
    )
    best, best_d = None, None
    for l in locs:
        d = haversine_meters(doc.latitude, doc.longitude,
                             l["latitude"], l["longitude"])
        if best_d is None or d < best_d:
            best, best_d = l, d
    if best:
        return best, (cint(best.get("default_radius_meter")) or 100)
    return None, None


def run_geofence(doc, result):
    loc, radius = resolve_location(doc)
    if not loc:
        result["within_geofence"] = 0
        return
    dist = haversine_meters(doc.latitude, doc.longitude,
                            loc["latitude"], loc["longitude"])
    result["matched_location"] = loc["name"]
    result["distance_from_location_meter"] = round(dist, 2)
    result["allowed_radius_meter"] = radius
    result["within_geofence"] = 1 if dist <= radius else 0


# ---------------------------------------------------------------------------
# step 3: shift + late/early
# ---------------------------------------------------------------------------
def resolve_shift_policy(doc):
    """See module docstring for the mapping order."""
    if doc.get("shift"):
        return frappe.get_doc("JEW Shift Attendance Policy", doc.shift)

    shift_type_name = None
    # (b) try Frappe HR shift assignment / employee default shift
    try:
        sa = frappe.db.get_value(
            "Shift Assignment",
            {"employee": doc.employee, "docstatus": 1, "status": "Active"},
            "shift_type",
        )
        shift_type_name = sa or frappe.db.get_value(
            "Employee", doc.employee, "default_shift")
    except Exception:
        shift_type_name = None

    if shift_type_name:
        match = frappe.db.get_value(
            "JEW Shift Attendance Policy",
            {"shift_name": shift_type_name, "is_active": 1}, "name")
        if match:
            return frappe.get_doc("JEW Shift Attendance Policy", match)

    # (c) single active policy
    active = frappe.get_all("JEW Shift Attendance Policy",
                            filters={"is_active": 1}, pluck="name")
    if len(active) == 1:
        return frappe.get_doc("JEW Shift Attendance Policy", active[0])
    return None


def run_shift(doc, result):
    """Compute late/early against the FIXED, company-wide attendance windows —
    Check In on-time 09:00-09:30, Check Out on-time 20:30-21:00 — for every
    employee, independent of any JEW Shift Attendance Policy. This guarantees a
    single consistent rule:
      * Check In  after 09:30  -> late by (minutes past 09:30)
      * Check Out before 20:30 -> early by (minutes before 20:30)
    """
    result["shift"] = None
    punch_time = get_datetime(doc.punch_datetime).time()

    if doc.punch_type == "Check In":
        start = get_time(DEFAULT_CHECKIN_START)
        late_by = _minutes_between_times(punch_time, start) - DEFAULT_CHECKIN_GRACE_MIN
        if late_by > 0:
            result["is_late"] = 1
            result["late_by_minutes"] = late_by
            result["status"] = "Late"
    elif doc.punch_type == "Check Out":
        end = get_time(DEFAULT_CHECKOUT_END)
        early_by = _minutes_between_times(end, punch_time) - DEFAULT_CHECKOUT_GRACE_MIN
        if early_by > 0:
            result["is_early"] = 1
            result["early_by_minutes"] = early_by
            result["status"] = "Early Leaving"
    return None


def apply_monthly_limits(doc, result, policy):
    """Count this month's late/early punches and apply the policy action."""
    if not policy:
        return
    month_start = getdate(doc.attendance_date).replace(day=1)

    def count(field):
        return frappe.db.count("NHS Attendance Punch", {
            "employee": doc.employee,
            field: 1,
            "attendance_date": [">=", month_start],
            "name": ["!=", doc.name],
        })

    checks = []
    if result.get("is_late"):
        checks.append(("is_late", cint(policy.max_late_coming_allowed_per_month),
                       policy.action_after_late_limit, "Late Coming"))
    if result.get("is_early"):
        checks.append(("is_early", cint(policy.max_early_going_allowed_per_month),
                       policy.action_after_early_limit, "Early Going"))

    for field, limit, action, issue in checks:
        if not limit:
            continue
        used = count(field) + 1  # include the current punch
        if used <= limit:
            continue
        # limit exceeded -> apply action
        if action == "Warn Only":
            notify(doc, "Warning",
                   "Attendance limit reached",
                   f"You have exceeded the monthly {issue} limit ({limit}).")
        elif action == "Regularization Required":
            reg = raise_regularization(doc, issue, policy_action=action)
            result["regularization_reference"] = reg
        elif action in ("Mark Half Day", "Mark LWP", "Block Attendance"):
            result["_attendance_status"] = (
                "Half Day" if action == "Mark Half Day" else "On Leave"
                if action == "Mark LWP" else None)
            if action == "Block Attendance":
                result["status"] = "Pending Review"
            reg = raise_regularization(doc, issue, policy_action=action)
            result["regularization_reference"] = reg


# ---------------------------------------------------------------------------
# regularization + notifications
# ---------------------------------------------------------------------------
def raise_regularization(doc, issue_type, policy_action=None):
    reg = frappe.get_doc({
        "doctype": "JEW Attendance Regularization",
        "employee": doc.employee,
        "attendance_date": doc.attendance_date,
        "issue_type": issue_type,
        "in_time": doc.punch_datetime if doc.punch_type == "Check In" else None,
        "out_time": doc.punch_datetime if doc.punch_type == "Check Out" else None,
        "policy_action": policy_action,
        "status": "Pending",
        "requested_by": frappe.session.user,
        "created_by": frappe.session.user,
        "remarks": f"Auto-raised from NHS Attendance Punch {doc.name}",
        "linked_attendance": doc.get("linked_attendance"),
        "linked_employee_checkin": doc.get("linked_employee_checkin"),
    })
    reg.insert(ignore_permissions=True)
    return reg.name


def notify(doc, ntype, title, message):
    n = frappe.get_doc({
        "doctype": "JEW HRMS Notification",
        "employee": doc.employee,
        "notification_type": ntype,
        "title": title,
        "message": message,
        "is_read": 0,
        "reference_doctype": "NHS Attendance Punch",
        "reference_name": doc.name,
    })
    n.insert(ignore_permissions=True)
    return n.name


# ---------------------------------------------------------------------------
# step 4: sync into Frappe HR core (Employee Checkin + Attendance)
# ---------------------------------------------------------------------------
def sync_hr_core(doc, result):
    log_type = "IN" if doc.punch_type == "Check In" else "OUT"
    checkin = frappe.get_doc({
        "doctype": "Employee Checkin",
        "employee": doc.employee,
        "log_type": log_type,
        "time": doc.punch_datetime,
        "device_id": (doc.get("device_info") or "Attendance Log")[:140],
        "latitude": flt(doc.latitude),
        "longitude": flt(doc.longitude),
    })
    checkin.insert(ignore_permissions=True)
    result["linked_employee_checkin"] = checkin.name

    # Attendance for the date
    att_status = result.get("_attendance_status") or "Present"
    existing = frappe.db.get_value("Attendance", {
        "employee": doc.employee,
        "attendance_date": doc.attendance_date,
        "docstatus": ["<", 2],
    }, "name")

    if existing:
        att = frappe.get_doc("Attendance", existing)
        result["linked_attendance"] = att.name
        if doc.punch_type == "Check Out":
            att.db_set("out_time", doc.punch_datetime)
            _update_working_hours(att)
        return

    company = frappe.db.get_value("Employee", doc.employee, "company")
    att = frappe.get_doc({
        "doctype": "Attendance",
        "employee": doc.employee,
        "attendance_date": doc.attendance_date,
        "status": att_status,
        "company": company,
        "in_time": doc.punch_datetime if doc.punch_type == "Check In" else None,
        "out_time": doc.punch_datetime if doc.punch_type == "Check Out" else None,
    })
    att.flags.ignore_validate = False
    try:
        att.insert(ignore_permissions=True)
        att.submit()
        result["linked_attendance"] = att.name
    except Exception:
        frappe.log_error(frappe.get_traceback(), "attendance_log: Attendance sync")


def _update_working_hours(att):
    if att.in_time and att.out_time:
        secs = (get_datetime(att.out_time) - get_datetime(att.in_time)).total_seconds()
        att.db_set("working_hours", round(max(0.0, secs) / 3600.0, 2))


# ---------------------------------------------------------------------------
# top-level entry point
# ---------------------------------------------------------------------------
def process_punch(doc):
    """Run the simplified pipeline and persist the computed fields on `doc`.

    No face match and no location blocking: geofence + shift late/early are
    recorded for the admin, HR-core Attendance is always synced as Present, and
    the punch's location is mirrored into NHS Location Ping for the map.
    """
    result = {
        "status": "Present",
        "is_late": 0, "is_early": 0,
        "within_geofence": 0,
    }

    run_geofence(doc, result)   # informational only — records distance/location
    run_shift(doc, result)      # -> Present / Late / Early Leaving

    # always sync HR core (Employee Checkin + Attendance = Present)
    try:
        sync_hr_core(doc, result)
    except Exception:
        frappe.log_error(frappe.get_traceback(), "attendance_log: sync_hr_core")

    # mirror the location into NHS Location Ping so the admin sees it on the map
    try:
        result["location_ping"] = write_location_ping(doc)
    except Exception:
        frappe.log_error(frappe.get_traceback(),
                         "attendance_log: write_location_ping")

    # summary notification
    notify(doc, _ntype_for(result["status"]),
           f"Attendance: {result['status']}", _summary_message(doc, result))

    # persist everything in one write (avoids re-triggering doc hooks)
    persist = {k: v for k, v in result.items() if not k.startswith("_")}
    persist.pop("location_ping", None)  # not a field on the punch
    frappe.db.set_value("NHS Attendance Punch", doc.name, persist,
                        update_modified=False)
    frappe.db.commit()
    doc.reload()
    return result


# ---------------------------------------------------------------------------
# location ping: one single-point record per (employee, date, window) mirroring
# the punch, so the admin can see WHERE the employee marked on the Desk map.
# Check In -> Morning window, Check Out -> Evening window.
# ---------------------------------------------------------------------------
def write_location_ping(doc):
    window = "Morning" if doc.punch_type == "Check In" else "Evening"
    cdate = getdate(doc.attendance_date)
    ct = get_datetime(doc.punch_datetime)
    lat = flt(doc.latitude)
    lng = flt(doc.longitude)

    name = frappe.db.get_value("NHS Location Ping", {
        "employee": doc.employee, "window": window, "capture_date": cdate,
    })
    if name:
        ping = frappe.get_doc("NHS Location Ping", name)
    else:
        ping = frappe.get_doc({
            "doctype": "NHS Location Ping",
            "employee": doc.employee,
            "employee_name": frappe.db.get_value(
                "Employee", doc.employee, "employee_name"),
            "window": window,
            "capture_date": cdate,
            "capture_time": ct,
        })

    ping.last_capture = ct
    ping.points_count = 1
    ping.latitude = lat
    ping.longitude = lng
    ping.path = json.dumps({
        "type": "FeatureCollection",
        "features": [{
            "type": "Feature",
            "properties": {"name": "Punch location"},
            "geometry": {"type": "Point", "coordinates": [lng, lat]},
        }],
    })
    ping.map_link = "https://www.google.com/maps?q={0},{1}".format(lat, lng)
    ping.points_json = json.dumps([{
        "t": ct.strftime("%Y-%m-%d %H:%M:%S"), "lat": lat, "lng": lng, "acc": None,
    }])
    ping.save(ignore_permissions=True)
    return ping.name


def _ntype_for(status):
    return {
        "Present": "Success", "Late": "Warning", "Early Leaving": "Warning",
    }.get(status, "Info")


def _summary_message(doc, result):
    msgs = {
        "Present": "Marked Present.",
        "Late": f"Marked Present but Late by {result.get('late_by_minutes',0)} min.",
        "Early Leaving": f"Early leaving by {result.get('early_by_minutes',0)} min.",
    }
    return f"{doc.punch_type} at {doc.punch_datetime}: " + msgs.get(
        result["status"], result["status"])
