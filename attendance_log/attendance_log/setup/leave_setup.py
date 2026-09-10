"""
One-time HR master-data setup so the leave feature works: creates the three
Leave Types that mirror our Leave Details CL/PL/LWP model, and a Leave
Allocation for the given employee (so balance is real, not zero).

  bench --site mysite.local execute attendance_log.setup.leave_setup.run
"""

import frappe
from frappe.utils import getdate, today

LEAVE_TYPES = [
    {"leave_type_name": "Casual Leave", "max_leaves_allowed": 12, "is_lwp": 0},
    {"leave_type_name": "Privilege Leave", "max_leaves_allowed": 15, "is_lwp": 0},
    {"leave_type_name": "Loss of Pay", "is_lwp": 1},
]

ALLOCATIONS = {"Casual Leave": 12, "Privilege Leave": 15}  # for the test employee


def ensure_leave_types():
    for lt in LEAVE_TYPES:
        name = lt["leave_type_name"]
        if frappe.db.exists("Leave Type", name):
            print("Leave Type exists:", name)
            continue
        doc = frappe.get_doc({"doctype": "Leave Type", **lt})
        doc.insert(ignore_permissions=True)
        print("created Leave Type:", name)


def ensure_allocation(employee):
    company = frappe.db.get_value("Employee", employee, "company")
    year = getdate(today()).year
    frm, to = f"{year}-01-01", f"{year}-12-31"
    for lt, days in ALLOCATIONS.items():
        exists = frappe.db.exists("Leave Allocation", {
            "employee": employee, "leave_type": lt,
            "from_date": frm, "docstatus": 1,
        })
        if exists:
            print("allocation exists:", employee, lt)
            continue
        doc = frappe.get_doc({
            "doctype": "Leave Allocation",
            "employee": employee,
            "leave_type": lt,
            "from_date": frm,
            "to_date": to,
            "new_leaves_allocated": days,
            "company": company,
        })
        doc.insert(ignore_permissions=True)
        doc.submit()
        print(f"allocated {days} {lt} to {employee}")


def ensure_holiday_list(employee):
    """Frappe HR needs a Holiday List to compute leave days. Create one for the
    current year (Sundays as weekly off) and set it as the company default +
    on the employee if not already set."""
    company = frappe.db.get_value("Employee", employee, "company")
    year = getdate(today()).year
    name = f"Holidays {year}"
    if not frappe.db.exists("Holiday List", name):
        hl = frappe.get_doc({
            "doctype": "Holiday List",
            "holiday_list_name": name,
            "from_date": f"{year}-01-01",
            "to_date": f"{year}-12-31",
            "weekly_off": "Sunday",
        })
        hl.get_weekly_off_dates()
        hl.insert(ignore_permissions=True)
        print("created Holiday List:", name)
    # set company default
    if not frappe.db.get_value("Company", company, "default_holiday_list"):
        frappe.db.set_value("Company", company, "default_holiday_list", name)
        print("set company default_holiday_list:", name)
    # set on employee
    if not frappe.db.get_value("Employee", employee, "holiday_list"):
        frappe.db.set_value("Employee", employee, "holiday_list", name)
        print("set employee holiday_list:", name)


def run(employee="HR-EMP-00001"):
    ensure_holiday_list(employee)
    ensure_leave_types()
    ensure_allocation(employee)
    frappe.db.commit()
    print("leave setup done")
