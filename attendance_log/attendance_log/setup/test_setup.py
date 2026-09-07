"""
Test data + end-to-end pipeline test for attendance_log.

  bench --site mysite.local execute attendance_log.setup.test_setup.setup_data
  bench --site mysite.local execute attendance_log.setup.test_setup.run_tests

setup_data() creates: a test company (reuses default), a test User + Employee,
a JEW Employee Face (reference selfie), a JEW Attendance Location + assignment,
and a JEW Shift Attendance Policy.

run_tests() creates three NHS Attendance Punch records directly (same code path
the API uses via after_insert) and asserts:
  1. in-range GPS + matching selfie  -> Present, within_geofence=1, Matched
  2. out-of-range GPS + matching selfie -> Outside Location + regularization
  3. in-range GPS + mismatched selfie -> Face Mismatch + regularization
"""

import io
import json
import frappe
from frappe.utils import today, get_datetime

from attendance_log import face_match

TEST_USER = "attendance.test@example.com"
LOC_LAT, LOC_LON = 18.5204, 73.8567          # Pune
FAR_LAT, FAR_LON = 19.0760, 72.8777          # Mumbai (~120 km away)
LOCATION = "Head Office - Pune"
SHIFT = "General Shift"


# ---------------------------------------------------------------------------
# image helpers (deterministic, distinct patterns)
# ---------------------------------------------------------------------------
def _img_bytes(kind):
    from PIL import Image
    import numpy as np
    if kind == "reference":
        # horizontal gradient
        row = np.linspace(0, 255, 128, dtype="uint8")
        arr = np.tile(row, (128, 1))
    elif kind == "mismatch":
        # deterministic pseudo-random noise -> uncorrelated with the gradient
        rng = np.random.RandomState(42)
        arr = rng.randint(0, 256, (128, 128), dtype="uint8")
    else:  # "match" == identical to reference
        row = np.linspace(0, 255, 128, dtype="uint8")
        arr = np.tile(row, (128, 1))
    buf = io.BytesIO()
    Image.fromarray(arr, mode="L").save(buf, format="PNG")
    return buf.getvalue()


def _save_file(content, name):
    f = frappe.get_doc({
        "doctype": "File", "file_name": name, "is_private": 1,
        "content": content,
    })
    f.insert(ignore_permissions=True)
    return f.file_url


# ---------------------------------------------------------------------------
# setup
# ---------------------------------------------------------------------------
def setup_data():
    company = frappe.db.get_single_value("Global Defaults", "default_company") \
        or frappe.get_all("Company", pluck="name", limit=1)[0]
    print("company:", company)

    # user
    if not frappe.db.exists("User", TEST_USER):
        u = frappe.get_doc({
            "doctype": "User", "email": TEST_USER, "first_name": "Attendance",
            "last_name": "Tester", "send_welcome_email": 0,
            "roles": [{"role": "Employee"}],
        })
        u.insert(ignore_permissions=True)
    # employee
    emp = frappe.db.get_value("Employee", {"user_id": TEST_USER}, "name")
    if not emp:
        e = frappe.get_doc({
            "doctype": "Employee", "first_name": "Attendance",
            "last_name": "Tester", "employee_name": "Attendance Tester",
            "user_id": TEST_USER, "company": company, "gender": "Other",
            "date_of_joining": "2024-01-01", "date_of_birth": "1995-01-01",
            "status": "Active",
        })
        e.insert(ignore_permissions=True)
        emp = e.name
    print("employee:", emp)

    # reference face
    ref_url = _save_file(_img_bytes("reference"), f"ref_face_{emp}.png")
    fobj = frappe.get_doc("File", {"file_url": ref_url})
    with open(fobj.get_full_path(), "rb") as fh:
        encoding = face_match.encode_image(fh.read())
    face = frappe.db.get_value("JEW Employee Face", {"employee": emp}, "name")
    if face:
        fd = frappe.get_doc("JEW Employee Face", face)
    else:
        fd = frappe.new_doc("JEW Employee Face")
        fd.employee = emp
    fd.user = TEST_USER
    fd.face_image = ref_url
    fd.face_encoding = encoding
    fd.is_active = 1
    fd.registered_by = "Administrator"
    fd.registered_on = get_datetime()
    fd.last_updated_on = get_datetime()
    fd.save(ignore_permissions=True)
    print("face backend:", face_match.backend_name(), "face:", fd.name)

    # location
    if not frappe.db.exists("JEW Attendance Location", LOCATION):
        frappe.get_doc({
            "doctype": "JEW Attendance Location", "location_name": LOCATION,
            "latitude": LOC_LAT, "longitude": LOC_LON,
            "default_radius_meter": 200, "is_active": 1,
        }).insert(ignore_permissions=True)
    # assignment
    if not frappe.db.exists("JEW Employee Location Assignment",
                            {"employee": emp, "location": LOCATION}):
        frappe.get_doc({
            "doctype": "JEW Employee Location Assignment", "employee": emp,
            "location": LOCATION, "radius_meter": 200, "is_active": 1,
        }).insert(ignore_permissions=True)

    # shift policy
    if not frappe.db.exists("JEW Shift Attendance Policy", {"shift_name": SHIFT}):
        frappe.get_doc({
            "doctype": "JEW Shift Attendance Policy", "shift_name": SHIFT,
            "shift_start_time": "09:00:00", "shift_end_time": "18:00:00",
            "late_coming_grace_minutes": 15, "early_going_grace_minutes": 15,
            "max_late_coming_allowed_per_month": 3,
            "max_early_going_allowed_per_month": 3,
            "full_day_minimum_hours": 8, "half_day_minimum_hours": 4,
            "is_active": 1,
        }).insert(ignore_permissions=True)

    frappe.db.commit()
    print("setup_data done")
    return emp


def _make_punch(emp, punch_type, lat, lon, img_kind, dt=None, shift=None):
    url = _save_file(_img_bytes(img_kind),
                     f"selfie_{img_kind}_{frappe.generate_hash(length=6)}.png")
    doc = frappe.get_doc({
        "doctype": "NHS Attendance Punch", "employee": emp,
        "attendance_date": today(), "punch_type": punch_type,
        "punch_datetime": dt or (today() + " 09:05:00"),
        "selfie_image": url, "latitude": lat, "longitude": lon,
        "shift": shift, "source": "Web App",
        "device_info": "pytest",
    })
    doc.insert(ignore_permissions=True)
    doc.reload()
    return doc


def _cleanup(emp):
    for dt in ["NHS Attendance Punch", "JEW Attendance Regularization",
               "JEW HRMS Notification", "Employee Checkin"]:
        for n in frappe.get_all(dt, filters={"employee": emp}, pluck="name"):
            frappe.delete_doc(dt, n, force=True, ignore_permissions=True)
    for n in frappe.get_all("Attendance", filters={"employee": emp},
                            pluck="name"):
        try:
            d = frappe.get_doc("Attendance", n)
            if d.docstatus == 1:
                d.cancel()
            frappe.delete_doc("Attendance", n, force=True, ignore_permissions=True)
        except Exception:
            pass
    frappe.db.commit()


def run_tests():
    emp = frappe.db.get_value("Employee", {"user_id": TEST_USER}, "name")
    assert emp, "run setup_data first"
    _cleanup(emp)

    results = []

    # 1. in-range + matching selfie
    p1 = _make_punch(emp, "Check In", LOC_LAT, LOC_LON, "match", shift=SHIFT)
    ok1 = (p1.status == "Present" and p1.within_geofence == 1
           and p1.face_match_status == "Matched")
    results.append(("in-range + match -> Present/geofence/Matched",
                    ok1, dict(status=p1.status, geo=p1.within_geofence,
                              face=p1.face_match_status,
                              score=p1.face_match_score,
                              att=p1.linked_attendance,
                              chk=p1.linked_employee_checkin)))

    # 2. out-of-range + matching selfie
    p2 = _make_punch(emp, "Check In", FAR_LAT, FAR_LON, "match", shift=SHIFT)
    reg2 = frappe.get_all("JEW Attendance Regularization",
                          filters={"employee": emp,
                                   "issue_type": "Outside Location"})
    ok2 = (p2.within_geofence == 0 and p2.status == "Outside Location"
           and len(reg2) >= 1)
    results.append(("out-of-range -> Outside Location + regularization",
                    ok2, dict(status=p2.status, geo=p2.within_geofence,
                              dist=p2.distance_from_location_meter,
                              regs=len(reg2))))

    # 3. in-range + mismatched selfie
    p3 = _make_punch(emp, "Check In", LOC_LAT, LOC_LON, "mismatch", shift=SHIFT)
    reg3 = frappe.get_all("JEW Attendance Regularization",
                          filters={"employee": emp,
                                   "issue_type": "Face Mismatch"})
    ok3 = (p3.face_match_status == "Not Matched"
           and p3.status == "Face Mismatch" and len(reg3) >= 1)
    results.append(("mismatch selfie -> Face Mismatch + regularization",
                    ok3, dict(status=p3.status, face=p3.face_match_status,
                              score=p3.face_match_score, regs=len(reg3))))

    print("\n===== TEST RESULTS =====")
    allok = True
    for label, ok, detail in results:
        allok = allok and ok
        print(("PASS" if ok else "FAIL"), "-", label)
        print("      ", detail)
    print("========================")
    print("ALL PASSED" if allok else "SOME FAILED")
    return allok
