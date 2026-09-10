"""Scheduled tasks for attendance_log."""

import frappe
from frappe.utils import add_days, now_datetime


def cleanup_old_location_pings():
    """Daily: delete NHS Location Ping rows older than 30 days (retention)."""
    cutoff = add_days(now_datetime(), -30)
    count = frappe.db.count("NHS Location Ping", {"capture_time": ["<", cutoff]})
    if count:
        frappe.db.delete("NHS Location Ping", {"capture_time": ["<", cutoff]})
        frappe.db.commit()
    frappe.logger("attendance_log").info(
        f"cleanup_old_location_pings: deleted {count} pings older than {cutoff}")
    return count
