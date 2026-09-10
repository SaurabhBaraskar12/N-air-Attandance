"""
Create the NHS Location Ping doctype (background location tracking).
  bench --site mysite.local execute attendance_log.setup.create_location_ping.run
Independent of NHS Attendance Punch / the check-in flow.
"""

import frappe

MODULE = "NHS HRMS Mobile"
NAME = "NHS Location Ping"

FIELDS = [
    {"fieldname": "employee", "fieldtype": "Link", "label": "Employee",
     "options": "Employee", "reqd": 1, "in_list_view": 1, "in_standard_filter": 1},
    {"fieldname": "employee_name", "fieldtype": "Data", "label": "Employee Name",
     "fetch_from": "employee.employee_name", "read_only": 1, "in_list_view": 1},
    {"fieldname": "capture_time", "fieldtype": "Datetime", "label": "Capture Time",
     "reqd": 1, "in_list_view": 1},
    {"fieldname": "window", "fieldtype": "Select", "label": "Window",
     "options": "Morning\nEvening", "reqd": 1, "in_list_view": 1,
     "in_standard_filter": 1},
    {"fieldname": "latitude", "fieldtype": "Float", "label": "Latitude",
     "reqd": 1, "precision": "6"},
    {"fieldname": "longitude", "fieldtype": "Float", "label": "Longitude",
     "reqd": 1, "precision": "6"},
    {"fieldname": "accuracy_meter", "fieldtype": "Float", "label": "Accuracy (m)"},
    {"fieldname": "map_link", "fieldtype": "Data", "label": "Map Link",
     "read_only": 1, "in_list_view": 1, "options": "URL"},
]

PERMS = [
    {"role": "System Manager", "read": 1, "write": 1, "create": 1, "delete": 1,
     "report": 1, "export": 1, "print": 1, "email": 1, "share": 1},
    {"role": "HR Manager", "read": 1, "write": 1, "create": 1, "delete": 1,
     "report": 1, "export": 1, "print": 1},
    {"role": "HR User", "read": 1, "report": 1, "print": 1},
    {"role": "Employee", "read": 1, "if_owner": 1},
]


def run():
    if frappe.db.exists("DocType", NAME):
        print("already exists:", NAME)
        return
    doc = frappe.get_doc({
        "doctype": "DocType",
        "name": NAME,
        "module": MODULE,
        "custom": 0,
        "editable_grid": 1,
        "engine": "InnoDB",
        "sort_field": "capture_time",
        "sort_order": "DESC",
        "track_changes": 0,
        "fields": FIELDS,
        "permissions": [dict(p) for p in PERMS],
    })
    doc.insert(ignore_permissions=True)
    frappe.db.commit()
    print("created:", NAME)
