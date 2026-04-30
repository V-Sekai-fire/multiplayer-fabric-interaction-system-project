## Lasso interaction test — multiple buttons so aim direction is meaningful.
extends Control

var _btn: Button
var _press_count := 0
var _label: Label
var _btn_b: Button
var _btn_c: Button

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

	# Three buttons spread across the canvas so aim direction matters
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 40)
	vbox.add_child(hbox)

	_btn = Button.new()
	_btn.text = "Alpha"
	_btn.custom_minimum_size = Vector2(160, 60)
	_btn.pressed.connect(_on_btn_pressed.bind("Alpha"))
	hbox.add_child(_btn)

	_btn_b = Button.new()
	_btn_b.text = "Beta"
	_btn_b.custom_minimum_size = Vector2(160, 60)
	_btn_b.pressed.connect(_on_btn_pressed.bind("Beta"))
	hbox.add_child(_btn_b)

	_btn_c = Button.new()
	_btn_c.text = "Gamma"
	_btn_c.custom_minimum_size = Vector2(160, 60)
	_btn_c.pressed.connect(_on_btn_pressed.bind("Gamma"))
	hbox.add_child(_btn_c)

	_label = Label.new()
	_label.text = "presses: 0"
	_label.add_theme_color_override(&"font_color", Color(0.4, 1.0, 0.4))
	vbox.add_child(_label)


func _on_btn_pressed(name: String = "?") -> void:
	_press_count += 1
	_label.text = "presses: %d  last: %s" % [_press_count, name]
	print("[EVENT] Button pressed name=%s (total: %d)" % [name, _press_count])


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
	var db := LassoDB.new()
	var origin := Node3D.new()
	origin.position = Vector3(0.0, 0.0, -1.0)
	add_child(origin)
	var poi := LassoPoint.new()
	poi.set_snapping_power(1.0)
	poi.set_size(2.0)
	poi.register_point(db, origin)
	var source := Transform3D(Basis.looking_at(Vector3(0.0, 0.0, -1.0)), Vector3.ZERO)
	var result: Array = db.calc_top_two_snapping_power(source, null, 1.0, 0.0, false)
	var found_poi := result[0] as LassoPoint
	var found: bool = found_poi != null and found_poi.get_origin() != null
	var poi_json := ""
	if found_poi != null:
		var local: Vector3 = source.affine_inverse() * origin.global_position
		poi_json = JSON.stringify({
			"snapping_power": found_poi.get_snapping_power(),
			"snapping_enabled": found_poi.get_snapping_enabled(),
			"size": found_poi.get_size(),
			"origin_pos": str(origin.global_position) if origin.is_inside_tree() else null,
			"local": str(local),
		})
	origin.queue_free()
	_mark("lasso_query_returns_poi", found, poi_json)


func _test_lasso_query_poi_in_negative_z() -> void:
	var db := LassoDB.new()
	var origin := Node3D.new()
	origin.position = Vector3(0.0, 0.0, -1.0)
	add_child(origin)
	var poi := LassoPoint.new()
	poi.set_snapping_power(1.0)
	poi.set_size(2.0)
	poi.register_point(db, origin)
	var source := Transform3D(Basis.looking_at(Vector3(0.0, 0.0, -1.0)), Vector3.ZERO)
	var result: Array = db.calc_top_two_snapping_power(source, null, 1.0, 0.0, false)
	var found_poi := result[0] as LassoPoint
	var local_pos: Vector3 = source.affine_inverse() * origin.global_position if found_poi != null else Vector3.ZERO
	origin.queue_free()
	_mark("lasso_query_poi_in_negative_z", local_pos.z < 0.0,
		"local_pos=%s" % str(local_pos))


func _test_lasso_poi_registers_on_ready() -> void:
	var db := LassoDB.new()
	var origin := Node3D.new()
	origin.position = Vector3(0.0, 0.0, -1.0)
	add_child(origin)
	var poi := LassoPoint.new()
	poi.set_snapping_power(1.0)
	poi.set_size(1.0)
	poi.register_point(db, origin)
	var source := Transform3D(Basis.looking_at(Vector3(0.0, 0.0, -1.0)), Vector3.ZERO)
	var result: Array = db.calc_top_two_snapping_power(source, null, 1.0, 0.0, false)
	var registered := (result[0] as LassoPoint) != null
	origin.queue_free()
	_mark("lasso_poi_registers_on_ready", registered,
		"poi_found=%s" % str(registered))


func _test_lasso_poi_deregisters_on_exit() -> void:
	var db := LassoDB.new()
	var origin := Node3D.new()
	origin.position = Vector3(0.0, 0.0, -1.0)
	add_child(origin)
	var poi := LassoPoint.new()
	poi.set_snapping_power(1.0)
	poi.set_size(1.0)
	poi.register_point(db, origin)
	origin.tree_exiting.connect(poi.unregister_point)
	origin.queue_free()
	await get_tree().process_frame
	var source := Transform3D(Basis.looking_at(Vector3(0.0, 0.0, -1.0)), Vector3.ZERO)
	var result: Array = db.calc_top_two_snapping_power(source, null, 1.0, 0.0, false)
	var still_registered := (result[0] as LassoPoint) != null
	_mark("lasso_poi_deregisters_on_exit", not still_registered,
		"poi_found=%s" % str(still_registered))
