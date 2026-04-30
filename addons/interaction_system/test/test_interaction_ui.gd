## Minimal lasso interaction test — one Button.
extends Control

var _btn: Button
var _press_count := 0
var _label: Label

# ── OTel ─────────────────────────────────────────────────────────────────────
var _otel: OpenTelemetry
var _suite_span := ""


func _ready() -> void:
	_build_ui()
	_otel_init()
	_run_unit_tests()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override(&"separation", 12)
	add_child(vbox)

	var heading := Label.new()
	heading.text = "Lasso Test"
	heading.add_theme_color_override(&"font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(heading)

	_btn = Button.new()
	_btn.text = "Press Me"
	_btn.custom_minimum_size = Vector2(200, 60)
	_btn.pressed.connect(_on_btn_pressed)
	vbox.add_child(_btn)

	_label = Label.new()
	_label.text = "presses: 0"
	_label.add_theme_color_override(&"font_color", Color(0.4, 1.0, 0.4))
	vbox.add_child(_label)


func _on_btn_pressed() -> void:
	_press_count += 1
	_label.text = "presses: %d" % _press_count
	print("[EVENT] Button pressed (total: %d)" % _press_count)


# ── OTel ─────────────────────────────────────────────────────────────────────

func _otel_init() -> void:
	if not ClassDB.class_exists("OpenTelemetry"):
		return
	_otel = OpenTelemetry.new()
	_otel.name = "OTelTestTracer"
	add_child(_otel)
	var project_name: String = ProjectSettings.get_setting("application/config/name", "godot-project")
	_otel.init_tracer_provider(
		"test",
		"http://localhost:4318",
		{"service.name": project_name, "service.version": "0.1.0"}
	)
	_suite_span = _otel.start_span("interaction.test.suite", OpenTelemetry.SPAN_KIND_INTERNAL)


func _otel_flush() -> void:
	if _otel == null or _suite_span.is_empty():
		return
	_otel.set_status(_suite_span, OpenTelemetry.STATUS_OK)
	_otel.end_span(_suite_span)
	_otel.flush_all()


# ── Unit tests ────────────────────────────────────────────────────────────────

var _rows: Dictionary = {}
var _results: VBoxContainer


func _run_unit_tests() -> void:
	# Build a small result panel
	_results = VBoxContainer.new()
	_results.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_results.offset_left = -300
	_results.offset_top  = -200
	add_child(_results)

	_add_row("lasso_query_returns_poi")
	_add_row("lasso_query_poi_in_negative_z")
	_add_row("lasso_poi_registers_on_ready")
	_add_row("lasso_poi_deregisters_on_exit")

	await get_tree().process_frame

	_test_lasso_query_returns_poi()
	_test_lasso_query_poi_in_negative_z()
	_test_lasso_poi_registers_on_ready()
	_test_lasso_poi_deregisters_on_exit()
	_otel_flush()


func _add_row(name: String) -> void:
	var lbl := Label.new()
	lbl.text = "[ ] %s" % name
	lbl.add_theme_font_size_override(&"font_size", 11)
	_results.add_child(lbl)
	_rows[name] = lbl


func _mark(name: String, passed: bool, detail: String = "") -> void:
	var suffix := (" — " + detail) if detail else ""
	print("%s %s%s" % ["[PASS]" if passed else "[FAIL]", name, suffix])
	if _otel != null and not _suite_span.is_empty():
		var span := _otel.start_span_with_parent(
			"interaction.test.case", _suite_span, OpenTelemetry.SPAN_KIND_INTERNAL)
		_otel.set_attributes(span, {"test.name": name, "test.passed": passed, "test.detail": detail})
		_otel.set_status(span, OpenTelemetry.STATUS_OK if passed else OpenTelemetry.STATUS_ERROR, name)
		_otel.end_span(span)
	var lbl: Label = _rows.get(name)
	if lbl == null:
		return
	lbl.text = ("[PASS] " if passed else "[FAIL] ") + name + suffix
	lbl.add_theme_color_override(&"font_color", Color(0.2, 0.9, 0.3) if passed else Color(0.9, 0.2, 0.2))


func _test_lasso_query_returns_poi() -> void:
	const LassoDb = preload("res://addons/interaction_system/lassodb.gd")
	var db = LassoDb.new()
	var origin := Node3D.new()
	origin.position = Vector3(0.0, 0.0, -1.0)
	add_child(origin)
	var poi := LassoDb.PointOfInterest.new()
	poi.snapping_power = 1.0
	poi.size = 2.0
	poi.register_point(db, origin)
	var query := LassoDb.LassoQuery.new()
	query.source = Transform3D(Basis.looking_at(Vector3(0.0, 0.0, -1.0)), Vector3.ZERO)
	var found := db.query(query)
	origin.queue_free()
	var poi_json := ""
	if query.out_best_poi != null:
		var p := query.out_best_poi
		poi_json = JSON.stringify({
			"snapping_power": p.snapping_power,
			"snapping_enabled": p.snapping_enabled,
			"size": p.size,
			"origin_pos": str(p.origin.global_position) if p.origin and p.origin.is_inside_tree() else null,
			"local": str(query.out_poi_to_local.get(p, Vector3.ZERO)),
		})
	_mark("lasso_query_returns_poi", found and query.out_best_poi != null, poi_json)


func _test_lasso_query_poi_in_negative_z() -> void:
	const LassoDb = preload("res://addons/interaction_system/lassodb.gd")
	var db = LassoDb.new()
	var origin := Node3D.new()
	origin.position = Vector3(0.0, 0.0, -1.0)
	add_child(origin)
	var poi := LassoDb.PointOfInterest.new()
	poi.snapping_power = 1.0
	poi.size = 2.0
	poi.register_point(db, origin)
	var query := LassoDb.LassoQuery.new()
	query.source = Transform3D(Basis.looking_at(Vector3(0.0, 0.0, -1.0)), Vector3.ZERO)
	db.query(query)
	var local_pos := Vector3.ZERO
	if query.out_best_poi != null and query.out_poi_to_local.has(query.out_best_poi):
		local_pos = query.out_poi_to_local[query.out_best_poi]
	origin.queue_free()
	_mark("lasso_query_poi_in_negative_z", local_pos.z < 0.0,
		"local_pos=%s" % str(local_pos))


func _test_lasso_poi_registers_on_ready() -> void:
	const LassoDb = preload("res://addons/interaction_system/lassodb.gd")
	var db = LassoDb.new()
	var origin := Node3D.new()
	add_child(origin)
	var poi := LassoDb.PointOfInterest.new()
	poi.snapping_power = 1.0
	poi.size = 1.0
	poi.register_point(db, origin)
	var count_after: int = db.point_set.size()
	origin.queue_free()
	_mark("lasso_poi_registers_on_ready", count_after == 1,
		"point_set.size=%d" % count_after)


func _test_lasso_poi_deregisters_on_exit() -> void:
	const LassoDb = preload("res://addons/interaction_system/lassodb.gd")
	var db = LassoDb.new()
	var origin := Node3D.new()
	add_child(origin)
	var poi := LassoDb.PointOfInterest.new()
	poi.snapping_power = 1.0
	poi.size = 1.0
	poi.register_point(db, origin)
	origin.tree_exiting.connect(poi.unregister_point)
	origin.queue_free()
	await get_tree().process_frame
	var count_final: int = db.point_set.size()
	_mark("lasso_poi_deregisters_on_exit", count_final == 0,
		"point_set.size=%d" % count_final)
