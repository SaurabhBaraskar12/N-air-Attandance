# Copyright (c) 2026, SVS Group and contributors
# For license information, please see license.txt

import frappe
from frappe.model.document import Document
from frappe.utils import today, now_datetime

from attendance_log.attendance_logic import process_punch


class NHSAttendancePunch(Document):
    def validate(self):
        # light defaults only; the heavy pipeline runs in after_insert so the
        # attached selfie file is available and both API + Desk share one path.
        if not self.attendance_date:
            self.attendance_date = today()
        if not self.punch_datetime:
            self.punch_datetime = now_datetime()
        if not self.source:
            self.source = "Web App"

    def after_insert(self):
        # run the full attendance pipeline (face match, geofence, shift,
        # HR-core sync, notifications). Guard against re-entry.
        if self.flags.get("skip_pipeline"):
            return
        try:
            process_punch(self)
        except Exception:
            frappe.log_error(frappe.get_traceback(),
                             "NHS Attendance Punch: process_punch failed")
