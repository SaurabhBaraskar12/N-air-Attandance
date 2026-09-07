"""
Add an "Employee" role permission (read-only, own records via If Owner) to the
employee-facing doctypes, per spec section 5. HR Manager / HR User already have
full access from create_doctypes.py.

  bench --site mysite.local execute attendance_log.setup.add_permissions.run
"""

import frappe

EMPLOYEE_FACING = [
    "NHS Attendance Punch",
    "JEW HRMS Notification",
    "JEW Attendance Regularization",
    "JEW Late Early Application",
    "Leave Details",
]


def run():
    for dt in EMPLOYEE_FACING:
        meta = frappe.get_doc("DocType", dt)
        # skip if an Employee perm already exists
        if any(p.role == "Employee" for p in meta.permissions):
            print("Employee perm already on", dt)
            continue
        meta.append("permissions", {
            "role": "Employee",
            "read": 1,
            "if_owner": 1,
            "report": 1,
        })
        meta.save(ignore_permissions=True)
        print("added Employee (read, if_owner) ->", dt)
    frappe.db.commit()
    print("done")
