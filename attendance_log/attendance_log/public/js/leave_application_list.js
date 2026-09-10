// Display-only override of the Leave Application status pill in the LIST view.
// The stored `status` value is unchanged (still Open/Approved/Rejected/Cancelled);
// we only relabel/recolor it. We wrap HRMS's own listview_settings so its
// other behaviour (add_fields, has_indicator_for_draft) is preserved.
(function () {
	const DISPLAY = {
		Open: ["Pending", "red"],
		Approved: ["Approved", "green"],
		Rejected: ["Rejected", "red"],
		Cancelled: ["Cancelled", "gray"],
	};

	const existing = frappe.listview_settings["Leave Application"] || {};
	frappe.listview_settings["Leave Application"] = Object.assign({}, existing, {
		// route draft (Open) and cancelled through our get_indicator instead of
		// Frappe's default "Draft"/"Cancelled" so the label/color is ours.
		has_indicator_for_draft: 1,
		has_indicator_for_cancelled: 1,
		get_indicator: function (doc) {
			const m = DISPLAY[doc.status] || [doc.status, "gray"];
			// filter still uses the raw stored status value
			return [__(m[0]), m[1], "status,=," + doc.status];
		},
	});
})();
