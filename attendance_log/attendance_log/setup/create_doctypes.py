"""
Create all doctypes for the attendance_log app / module "JEW HRMS Mobile".

Run with:
  bench --site mysite.local execute attendance_log.setup.create_doctypes.run
(or copied to a standalone script invoked with the bench env python from sites/)

Developer mode must be ON so Frappe exports each DocType to disk as JSON under
apps/attendance_log/attendance_log/jew_hrms_mobile/doctype/<name>/.

Idempotent: skips doctypes that already exist.
"""

import frappe

MODULE = "JEW HRMS Mobile"
APP = "attendance_log"

MONTHS = "\n".join(
    ["January", "February", "March", "April", "May", "June", "July",
     "August", "September", "October", "November", "December"]
)

POLICY_ACTIONS = "\n".join(
    ["", "Warn Only", "Regularization Required", "Mark Half Day",
     "Mark LWP", "Block Attendance"]
)


def f(fieldname, fieldtype, label=None, options=None, reqd=0, default=None,
      description=None, in_list_view=0, read_only=0):
    d = {
        "fieldname": fieldname,
        "fieldtype": fieldtype,
        "label": label or fieldname.replace("_", " ").title(),
    }
    if options is not None:
        d["options"] = options
    if reqd:
        d["reqd"] = 1
    if default is not None:
        d["default"] = default
    if description:
        d["description"] = description
    if in_list_view:
        d["in_list_view"] = 1
    if read_only:
        d["read_only"] = 1
    return d


# ---------------------------------------------------------------------------
# Section 1: the 9 "JEW ..." doctypes (faithful recreation) + child tables
# ---------------------------------------------------------------------------

def jew_employee_face():
    return dict(name="JEW Employee Face", fields=[
        f("employee", "Link", options="Employee", reqd=1, in_list_view=1),
        f("user", "Link", options="User"),
        f("face_image", "Attach Image"),
        f("face_encoding", "Long Text",
          description="Serialized face embedding (JSON array)"),
        f("face_template", "Long Text"),
        f("is_active", "Check", default="1", in_list_view=1),
        f("registered_by", "Link", options="User"),
        f("registered_on", "Datetime"),
        f("last_updated_on", "Datetime"),
    ], title_field=None)


def jew_attendance_location():
    return dict(name="JEW Attendance Location", autoname="field:location_name",
                fields=[
        f("location_name", "Data", reqd=1, in_list_view=1),
        f("latitude", "Float", reqd=1),
        f("longitude", "Float", reqd=1),
        f("default_radius_meter", "Int", default="100"),
        f("is_active", "Check", default="1", in_list_view=1),
    ], title_field="location_name")


def jew_employee_location_assignment():
    return dict(name="JEW Employee Location Assignment", fields=[
        f("employee", "Link", options="Employee", reqd=1, in_list_view=1),
        f("location", "Link", options="JEW Attendance Location", reqd=1,
          in_list_view=1),
        f("radius_meter", "Int",
          description="Overrides default_radius_meter for this employee"),
        f("is_active", "Check", default="1", in_list_view=1),
    ])


def jew_hrms_notification():
    return dict(name="JEW HRMS Notification", fields=[
        f("employee", "Link", options="Employee", reqd=1, in_list_view=1),
        f("notification_type", "Select", options="Info\nWarning\nSuccess\nError",
          default="Info", in_list_view=1),
        f("title", "Data", reqd=1, in_list_view=1),
        f("message", "Long Text"),
        f("is_read", "Check", in_list_view=1),
        f("reference_doctype", "Data"),
        f("reference_name", "Data"),
    ], title_field="title")


def jew_shift_attendance_policy():
    return dict(name="JEW Shift Attendance Policy", autoname="field:shift_name",
                fields=[
        f("shift_name", "Data", reqd=1, in_list_view=1),
        f("shift_start_time", "Time", reqd=1),
        f("shift_end_time", "Time", reqd=1),
        f("break_minutes", "Int"),
        f("full_day_minimum_hours", "Float"),
        f("half_day_minimum_hours", "Float"),
        f("late_coming_grace_minutes", "Int"),
        f("early_going_grace_minutes", "Int"),
        f("max_late_coming_allowed_per_month", "Int"),
        f("max_early_going_allowed_per_month", "Int"),
        f("max_short_hours_allowed_per_month", "Int"),
        f("action_after_late_limit", "Select", options=POLICY_ACTIONS),
        f("action_after_early_limit", "Select", options=POLICY_ACTIONS),
        f("action_after_short_hours_limit", "Select", options=POLICY_ACTIONS),
        f("is_active", "Check", default="1", in_list_view=1),
    ], title_field="shift_name")


def leave_details_item():
    # child table, no module prefix per spec (kept in same module though)
    return dict(name="Leave Details Item", istable=1, fields=[
        f("date", "Date", in_list_view=1),
        f("leave_application", "Link", options="Leave Application",
          in_list_view=1),
        f("applied_type", "Data", in_list_view=1),
        f("half_day", "Check", in_list_view=1),
        f("pl", "Check", in_list_view=1),
        f("cl", "Check", in_list_view=1),
        f("lwp", "Check", in_list_view=1),
    ])


def leave_details():
    return dict(name="Leave Details", is_submittable=1, fields=[
        f("company", "Link", options="Company", reqd=1),
        f("month", "Select", options=MONTHS, reqd=1),
        f("year", "Int", reqd=1),
        f("employee", "Link", options="Employee", reqd=1, in_list_view=1),
        f("allotted_cl", "Float"),
        f("remaining_cl", "Float"),
        f("allotted_pl", "Float"),
        f("remaining_pl", "Float"),
        f("leaves", "Table", options="Leave Details Item"),
        f("cl_days", "Float",
          description="Casual Leave days deducted from balance"),
        f("pl_days", "Float",
          description="Privilege Leave days deducted from balance"),
        f("lwp_days", "Float",
          description="Unpaid days - deduct these from salary"),
        f("amended_from", "Link", options="Leave Details", read_only=1),
    ], title_field="employee")


def jew_late_early_application():
    return dict(name="JEW Late Early Application", fields=[
        f("employee", "Link", options="Employee", reqd=1, in_list_view=1),
        f("employee_name", "Data"),
        f("application_type", "Select", options="Late Coming\nEarly Going",
          reqd=1, in_list_view=1),
        f("application_date", "Date", reqd=1, in_list_view=1),
        f("expected_time", "Time", reqd=1),
        f("shift", "Data"),
        f("reason", "Small Text", reqd=1),
        f("status", "Select",
          options="Pending\nPending HR\nApproved\nRejected\nCancelled",
          default="Pending", in_list_view=1),
        f("dept_head_approved_by", "Link", options="User"),
        f("dept_head_approved_on", "Datetime"),
        f("hr_approved_by", "Link", options="User"),
        f("hr_approved_on", "Datetime"),
        f("reviewed_by", "Link", options="User"),
        f("reviewed_on", "Datetime"),
        f("remarks", "Small Text"),
        f("email_action_token", "Data"),
        f("email_action_token_user", "Data"),
        f("email_action_token_stage", "Data"),
        f("email_action_token_expiry", "Datetime"),
    ])


def jew_attendance_regularization():
    return dict(name="JEW Attendance Regularization", fields=[
        f("employee", "Link", options="Employee", reqd=1, in_list_view=1),
        f("attendance_date", "Date", reqd=1, in_list_view=1),
        f("issue_type", "Select", reqd=1, in_list_view=1, options="\n".join([
            "Missing Mark In", "Missing Mark Out", "Missing Mark In & Out",
            "Late Coming", "Early Going", "Short Hours", "Face Mismatch",
            "Outside Location"])),
        f("in_time", "Datetime"),
        f("out_time", "Datetime"),
        f("working_hours", "Float"),
        f("policy_action", "Select", options=POLICY_ACTIONS),
        f("status", "Select", default="Pending", in_list_view=1,
          options="\n".join([
              "Pending", "Approved as Present", "Marked Half Day",
              "Marked LWP", "Marked Late Coming", "Marked Early Going",
              "Rejected"])),
        f("requested_by", "Link", options="User"),
        f("created_by", "Link", options="User"),
        f("approved_by", "Link", options="User"),
        f("remarks", "Small Text"),
        f("linked_attendance", "Link", options="Attendance"),
        f("linked_employee_checkin", "Link", options="Employee Checkin"),
    ])


# ---------------------------------------------------------------------------
# Section 2: the new NHS Attendance Punch doctype
# ---------------------------------------------------------------------------

def nhs_attendance_punch():
    return dict(name="NHS Attendance Punch", fields=[
        f("employee", "Link", options="Employee", reqd=1, in_list_view=1),
        f("attendance_date", "Date", reqd=1, default="Today", in_list_view=1),
        f("punch_type", "Select", options="Check In\nCheck Out", reqd=1,
          in_list_view=1),
        f("punch_datetime", "Datetime", reqd=1, default="Now"),
        f("selfie_image", "Attach Image", reqd=1),
        f("face_match_status", "Select",
          options="\nMatched\nNot Matched\nPending Review\nNo Reference Image",
          in_list_view=1),
        f("face_match_score", "Float", description="similarity score 0-1"),
        f("latitude", "Float", reqd=1),
        f("longitude", "Float", reqd=1),
        f("matched_location", "Link", options="JEW Attendance Location"),
        f("distance_from_location_meter", "Float"),
        f("allowed_radius_meter", "Float"),
        f("within_geofence", "Check", in_list_view=1),
        f("shift", "Link", options="JEW Shift Attendance Policy"),
        f("is_late", "Check"),
        f("late_by_minutes", "Int"),
        f("is_early", "Check"),
        f("early_by_minutes", "Int"),
        f("status", "Select", in_list_view=1, options="\n".join([
            "", "Present", "Late", "Early Leaving", "Outside Location",
            "Face Mismatch", "Pending Review"])),
        f("linked_attendance", "Link", options="Attendance"),
        f("linked_employee_checkin", "Link", options="Employee Checkin"),
        f("regularization_reference", "Link",
          options="JEW Attendance Regularization"),
        f("source", "Select", options="Mobile App\nWeb App",
          default="Mobile App"),
        f("device_info", "Data"),
        f("remarks", "Small Text"),
    ])


ORDER = [
    # child tables & bases first (referenced by links/tables below)
    jew_attendance_location,
    jew_employee_face,
    jew_employee_location_assignment,
    jew_hrms_notification,
    jew_shift_attendance_policy,
    leave_details_item,
    leave_details,
    jew_late_early_application,
    jew_attendance_regularization,
    nhs_attendance_punch,
]


DEFAULT_PERMS = [
    {"role": "System Manager", "read": 1, "write": 1, "create": 1,
     "delete": 1, "submit": 0, "cancel": 0, "amend": 0, "report": 1,
     "export": 1, "share": 1, "print": 1, "email": 1},
    {"role": "HR Manager", "read": 1, "write": 1, "create": 1, "delete": 1,
     "report": 1, "export": 1, "share": 1, "print": 1, "email": 1},
    {"role": "HR User", "read": 1, "write": 1, "create": 1,
     "report": 1, "print": 1, "email": 1},
]


def build(spec):
    doc = {
        "doctype": "DocType",
        "name": spec["name"],
        "module": MODULE,
        "custom": 0,
        "istable": spec.get("istable", 0),
        "is_submittable": spec.get("is_submittable", 0),
        "editable_grid": 1,
        "engine": "InnoDB",
        "fields": spec["fields"],
        "track_changes": 1,
    }
    if not spec.get("istable"):
        doc["permissions"] = [dict(p) for p in DEFAULT_PERMS]
        # allow submit on submittable doctypes
        if spec.get("is_submittable"):
            for p in doc["permissions"]:
                if p["role"] in ("System Manager", "HR Manager"):
                    p["submit"] = 1
                    p["cancel"] = 1
                    p["amend"] = 1
    if spec.get("autoname"):
        doc["autoname"] = spec["autoname"]
    if spec.get("title_field"):
        doc["title_field"] = spec["title_field"]
        doc["show_title_field_in_link"] = 1
    return doc


def ensure_module():
    if not frappe.db.exists("Module Def", MODULE):
        md = frappe.get_doc({
            "doctype": "Module Def",
            "module_name": MODULE,
            "app_name": APP,
            "custom": 0,
        })
        md.insert(ignore_permissions=True)
        print("CREATED Module Def:", MODULE)


def run():
    frappe.flags.in_import = False
    ensure_module()
    created, skipped = [], []
    for factory in ORDER:
        spec = factory()
        name = spec["name"]
        if frappe.db.exists("DocType", name):
            skipped.append(name)
            continue
        doc = frappe.get_doc(build(spec))
        doc.insert(ignore_permissions=True)
        created.append(name)
        print("CREATED:", name)
    frappe.db.commit()
    print("\n=== SUMMARY ===")
    print("created:", created)
    print("skipped (already existed):", skipped)
