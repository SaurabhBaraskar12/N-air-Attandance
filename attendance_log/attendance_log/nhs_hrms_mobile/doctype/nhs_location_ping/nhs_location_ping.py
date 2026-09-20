# Copyright (c) 2026, SVS Group and contributors
# For license information, please see license.txt

import frappe
from frappe.model.document import Document
from frappe.model.naming import make_autoname


class NHSLocationPing(Document):
    def autoname(self):
        # Human-readable ID based on the Employee Name, e.g. "Shivani-00001".
        nm = self.employee_name or (self.employee and frappe.db.get_value(
            "Employee", self.employee, "employee_name")) or self.employee
        self.name = make_autoname(f"{nm}-.#####")

    def validate(self):
        # employee_name fallback (path + map_link are built in
        # attendance_log.api.log_location_ping as points accumulate).
        if not self.employee_name and self.employee:
            self.employee_name = frappe.db.get_value(
                "Employee", self.employee, "employee_name")
