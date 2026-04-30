# Lightweight OTel span wrapper for the lasso interaction pipeline.
# One trace per input event: root span → pose span → query span → dispatch span.
# Serialises to OTLP JSON and prints when the root span ends.
extends RefCounted

var _otel: OpenTelemetry
var _doc           # OTelDocument
var _root_id  := ""
var _pose_id  := ""
var _query_id := ""
var _enabled  := false
var spans_flushed:    int = 0
var dispatches_ok:    int = 0
var queries_found:    int = 0
var queries_total:    int = 0
# Last completed span summary — read by test_main for HUD
var last_span:   StringName = &""   # e.g. &"lasso.dispatch"
var last_status: int = 0            # 0=ok 1=err
var last_tag:    StringName = &""   # op-specific detail, e.g. &"found" &"press"


func _init() -> void:
	if not ClassDB.class_exists("OpenTelemetry"):
		return
	# Prefer OTel node registered by test_main._init_otel via Engine meta.
	if Engine.has_meta("_otel_instance"):
		_otel = Engine.get_meta("_otel_instance") as OpenTelemetry
	else:
		_otel = OpenTelemetry.new()
		_otel.name = "LassoTracer_OTel"
		var raw: String = ProjectSettings.get_setting("application/config/name", "godot-project")
		var service_name := raw.to_lower().replace(" ", "-").replace("_", "-")
		_otel.init_tracer_provider("lasso", "http://localhost:4318", {"service.name": service_name})
		Engine.set_meta("_otel_instance", _otel)
		var tree := Engine.get_main_loop() as SceneTree
		if tree and tree.root:
			tree.root.add_child.call_deferred(_otel)
	_doc = _otel.get_document()
	_enabled = true


# ── trace lifecycle ────────────────────────────────────────────────────────

func begin_input(event_type: String, screen_pos: Vector2) -> void:
	if not _enabled:
		return
	_root_id = _otel.start_span("lasso.input", 0, [], {
		"event.type":   event_type,
		"screen.x":     screen_pos.x,
		"screen.y":     screen_pos.y,
	})

func begin_pose(uv: Vector2, source: Vector3, aim_dir: Vector3 = Vector3.ZERO) -> void:
	if not _enabled or _root_id.is_empty():
		return
	_pose_id = _otel.start_span_with_parent("lasso.pose", _root_id, 0, [], {
		"uv.x":       uv.x,
		"uv.y":       uv.y,
		"source.x":   source.x,
		"source.y":   source.y,
		"source.z":   source.z,
		"aim.x":      aim_dir.x,
		"aim.y":      aim_dir.y,
		"aim.z":      aim_dir.z,
	})

func end_pose() -> void:
	if not _enabled or _pose_id.is_empty():
		return
	_otel.end_span(_pose_id)
	_pose_id = ""

func begin_query(poi_count: int) -> void:
	if not _enabled or _pose_id.is_empty():
		return
	_query_id = _otel.start_span_with_parent("lasso.query", _pose_id, 0, [], {
		"poi.count": poi_count,
	})

func record_query_result(found: bool, canvas_item_type: String, pos2d: Vector2, target3d: Vector3 = Vector3.ZERO) -> void:
	queries_total += 1
	if found: queries_found += 1
	last_span = &"lasso.query"; last_status = 0; last_tag = &"found" if found else &"miss"
	if not _enabled or _query_id.is_empty():
		return
	_otel.set_attributes(_query_id, {
		"query.found":        found,
		"canvas_item.type":   canvas_item_type,
		"pos2d.x":            pos2d.x,
		"pos2d.y":            pos2d.y,
		"target.x":           target3d.x,
		"target.y":           target3d.y,
		"target.z":           target3d.z,
	})
	_otel.set_status(_query_id, 1 if found else 2, "found" if found else "no_poi")

func end_query() -> void:
	if not _enabled or _query_id.is_empty():
		return
	_otel.end_span(_query_id)
	_query_id = ""

func record_poi_positions(poi_set: Dictionary) -> void:
	if not _enabled or _query_id.is_empty():
		return
	var i := 0
	for poi in poi_set:
		if i >= 7:
			break
		var origin: Node3D = poi.origin
		if origin and origin.is_inside_tree():
			var gp: Vector3 = origin.global_position
			var ci = poi.canvas_item if "canvas_item" in poi else null
			var ci_name: String = ci.get_class() if ci else "unknown"
			_otel.set_attributes(_query_id, {
				"poi.%d.control" % i: ci_name,
				"poi.%d.x" % i: gp.x,
				"poi.%d.y" % i: gp.y,
				"poi.%d.z" % i: gp.z,
			})
		i += 1

func record_dispatch(action: String, canvas_item_type: String, pos2d: Vector2) -> void:
	dispatches_ok += 1
	last_span = &"lasso.dispatch"; last_status = 0; last_tag = &"press" if action == "press" else &"release"
	if not _enabled or _root_id.is_empty():
		return
	var span := _otel.start_span_with_parent("lasso.dispatch", _root_id, 0, [], {
		"dispatch.action":  action,
		"canvas_item.type": canvas_item_type,
		"pos2d.x":          pos2d.x,
		"pos2d.y":          pos2d.y,
	})
	_otel.set_status(span, 1, "dispatched")
	_otel.end_span(span)

func end_input(error: String = "") -> void:
	if not _enabled or _root_id.is_empty():
		return
	if not _pose_id.is_empty():
		_otel.end_span(_pose_id)
		_pose_id = ""
	if not error.is_empty():
		_otel.record_error(_root_id, error)
		_otel.set_status(_root_id, 2, error)
	else:
		_otel.set_status(_root_id, 1, "ok")
	_otel.end_span(_root_id)

	_otel.flush_all()  # enqueues spans — _process() sends them without blocking
	spans_flushed += 1

	_root_id = ""
