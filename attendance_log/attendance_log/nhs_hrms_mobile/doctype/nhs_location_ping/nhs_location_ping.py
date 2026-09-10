# Copyright (c) 2026, SVS Group and contributors
# For license information, please see license.txt

import frappe
from frappe.model.document import Document


class NHSLocationPing(Document):
    def validate(self):
        # plain Google Maps URL (no API key) pointing at the captured point
        if self.latitude is not None and self.longitude is not None:
            self.map_link = (
                f"https://www.google.com/maps?q={self.latitude},{self.longitude}"
            )
        if not self.employee_name and self.employee:
            self.employee_name = frappe.db.get_value(
                "Employee", self.employee, "employee_name")
