frappe.pages["location-path"].on_page_load = function (wrapper) {
	const page = frappe.ui.make_app_page({
		parent: wrapper,
		title: "Employee Location Path",
		single_column: true,
	});

	const $body = $(page.body);
	$body.html(`
		<div class="row" style="margin-bottom:12px;align-items:end">
			<div class="col-sm-3"><div class="elp-employee"></div></div>
			<div class="col-sm-3"><div class="elp-date"></div></div>
			<div class="col-sm-2"><div class="elp-window"></div></div>
			<div class="col-sm-2" style="padding-top:24px">
				<button class="btn btn-primary btn-sm elp-show">Show Path</button>
			</div>
		</div>
		<div class="elp-status text-muted" style="margin:4px 0 10px"></div>
		<div id="elp-map" style="height:600px;border:1px solid var(--border-color);border-radius:8px"></div>
	`);

	const employee = frappe.ui.form.make_control({
		df: { fieldtype: "Link", options: "Employee", label: "Employee",
			reqd: 1, fieldname: "employee" },
		parent: $body.find(".elp-employee"), render_input: true,
	});
	employee.refresh();

	const date = frappe.ui.form.make_control({
		df: { fieldtype: "Date", label: "Date", reqd: 1, fieldname: "date" },
		parent: $body.find(".elp-date"), render_input: true,
	});
	date.set_value(frappe.datetime.get_today());
	date.refresh();

	const windowCtrl = frappe.ui.form.make_control({
		df: { fieldtype: "Select", label: "Window", options: "Morning\nEvening",
			reqd: 1, fieldname: "window" },
		parent: $body.find(".elp-window"), render_input: true,
	});
	windowCtrl.set_value("Morning");
	windowCtrl.refresh();

	let map = null;
	let layer = null;

	function ensureLeaflet(cb) {
		if (window.L) return cb();
		if (!document.getElementById("elp-leaflet-css")) {
			const l = document.createElement("link");
			l.id = "elp-leaflet-css";
			l.rel = "stylesheet";
			l.href = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css";
			document.head.appendChild(l);
		}
		const s = document.createElement("script");
		s.src = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";
		s.onload = cb;
		document.head.appendChild(s);
	}

	function initMap() {
		if (map) return;
		map = L.map("elp-map").setView([23.0112, 72.5288], 12);
		L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
			maxZoom: 19,
			attribution: "&copy; OpenStreetMap contributors",
		}).addTo(map);
		layer = L.layerGroup().addTo(map);
	}

	function draw(points) {
		initMap();
		layer.clearLayers();
		setTimeout(() => map.invalidateSize(), 50);

		if (!points.length) {
			$body.find(".elp-status").html(
				"<b>No location data found for this employee/date/window.</b>");
			map.setView([23.0112, 72.5288], 11);
			return;
		}
		$body.find(".elp-status").text(points.length + " points — path in time order");

		const latlngs = points.map((p) => [p.latitude, p.longitude]);
		L.polyline(latlngs, { color: "#1565C0", weight: 4, opacity: 0.85 }).addTo(layer);

		points.forEach((p, i) => {
			if (i === 0 || i === points.length - 1) return;
			L.circleMarker([p.latitude, p.longitude], {
				radius: 5, color: "#1565C0", fillColor: "#1565C0", fillOpacity: 0.9,
			}).bindPopup("Time: " + p.capture_time).addTo(layer);
		});

		const start = points[0];
		const end = points[points.length - 1];
		L.circleMarker([start.latitude, start.longitude], {
			radius: 9, color: "green", fillColor: "green", fillOpacity: 0.95, weight: 2,
		}).bindTooltip("Start", { permanent: true, direction: "top" })
			.bindPopup("Start — " + start.capture_time).addTo(layer);
		L.circleMarker([end.latitude, end.longitude], {
			radius: 9, color: "red", fillColor: "red", fillOpacity: 0.95, weight: 2,
		}).bindTooltip("End", { permanent: true, direction: "top" })
			.bindPopup("End — " + end.capture_time).addTo(layer);

		map.fitBounds(L.latLngBounds(latlngs).pad(0.25));
	}

	function showPath() {
		const emp = employee.get_value();
		const d = date.get_value();
		const w = windowCtrl.get_value();
		if (!emp || !d || !w) {
			frappe.msgprint(__("Please select employee, date and window."));
			return;
		}
		$body.find(".elp-status").text("Loading…");
		frappe.call({
			method: "attendance_log.api.get_location_path",
			args: { employee: emp, date: d, window: w },
			callback: (r) => {
				const points = (r.message && r.message.points) || [];
				ensureLeaflet(() => draw(points));
			},
		});
	}

	$body.find(".elp-show").on("click", showPath);
	// warm up the map so the container isn't blank before the first search
	ensureLeaflet(initMap);
};
