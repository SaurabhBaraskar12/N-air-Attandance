"""
Create the "Attendance Log" Desk Workspace (spec section 5).

Run with:
  bench --site mysite.local execute attendance_log.setup.create_workspace.run

Internal/Desk workspace (not a public portal page). Shortcuts to the key
doctypes + a card grouping them, so HR can eyeball today's punches and open the
linked regularization records.
"""

import json
import frappe

LABEL = "Attendance Log"
MODULE = "NHS HRMS Mobile"

SHORTCUTS = [
    ("NHS Attendance Punch", "Today's Punches", "Green",
     json.dumps({"attendance_date": ["Timespan", "today"]})),
    ("Leave Application", "Leave Requests", "Orange",
     json.dumps({"status": "Open"})),
    ("JEW Late Early Application", "Late/Early Requests", "Purple",
     json.dumps({"status": "Pending"})),
    ("JEW Attendance Regularization", "Regularizations", "Red", None),
    ("JEW Attendance Location", "Locations", "Blue", None),
    ("JEW Employee Face", "Registered Faces", "Cyan", None),
]

CARD_LINKS = [
    ("Attendance", [
        "NHS Attendance Punch", "JEW Attendance Regularization",
    ]),
    ("Leave & Requests", [
        "Leave Application", "JEW Late Early Application", "Leave Details",
    ]),
    ("Configuration", [
        "JEW Attendance Location", "JEW Employee Location Assignment",
        "JEW Shift Attendance Policy", "JEW Employee Face",
    ]),
    ("Notifications", [
        "JEW HRMS Notification",
    ]),
]


def build_content():
    blocks = [
        {"id": "hdr_main", "type": "header",
         "data": {"text": "<span class='h4'><b>Attendance Log</b></span>",
                  "col": 12}},
    ]
    for name, label, color, _f in SHORTCUTS:
        blocks.append({"id": "sc_" + frappe.scrub(name), "type": "shortcut",
                       "data": {"shortcut_name": label, "col": 4}})
    # Page shortcut: Employee Location Path (map viewer)
    blocks.append({"id": "sc_location_path", "type": "shortcut",
                   "data": {"shortcut_name": "Employee Location Path", "col": 4}})
    blocks.append({"id": "hdr_cards", "type": "header",
                   "data": {"text": "<b>All Records</b>", "col": 12}})
    for card_name, _ in CARD_LINKS:
        blocks.append({"id": "card_" + frappe.scrub(card_name), "type": "card",
                       "data": {"card_name": card_name, "col": 4}})
    return json.dumps(blocks)


def run():
    if frappe.db.exists("Workspace", LABEL):
        frappe.delete_doc("Workspace", LABEL, force=True)

    ws = frappe.new_doc("Workspace")
    ws.label = LABEL
    ws.title = LABEL
    ws.module = MODULE
    ws.public = 1
    ws.icon = "users"
    ws.content = build_content()

    # shortcuts
    for name, label, color, filt in SHORTCUTS:
        row = {
            "label": label,
            "type": "DocType",
            "link_to": name,
            "color": color,
        }
        if filt:
            row["stats_filter"] = filt
        ws.append("shortcuts", row)

    # Page shortcut -> Employee Location Path map viewer
    ws.append("shortcuts", {
        "label": "Employee Location Path",
        "type": "Page",
        "link_to": "location-path",
        "color": "Green",
    })

    # links (cards)
    for card_name, doctypes in CARD_LINKS:
        ws.append("links", {
            "label": card_name,
            "type": "Card Break",
            "hidden": 0,
            "onboard": 0,
        })
        for dt in doctypes:
            ws.append("links", {
                "label": dt,
                "type": "Link",
                "link_type": "DocType",
                "link_to": dt,
                "hidden": 0,
                "onboard": 0,
            })

    ws.insert(ignore_permissions=True)
    frappe.db.commit()
    print("Workspace created:", ws.name)
