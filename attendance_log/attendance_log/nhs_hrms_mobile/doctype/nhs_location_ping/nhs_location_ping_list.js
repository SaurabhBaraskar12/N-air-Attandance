// Render map_link as a clickable "View on Map" link in the list view.
frappe.listview_settings["NHS Location Ping"] = {
	add_fields: ["map_link"],
	formatters: {
		map_link(value) {
			if (!value) return "";
			return `<a href="${value}" target="_blank" rel="noopener">View on Map</a>`;
		},
	},
};
