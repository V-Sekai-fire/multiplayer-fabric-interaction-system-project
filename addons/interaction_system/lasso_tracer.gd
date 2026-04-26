# Thin lasso-pipeline adapter over AppTracer.
# interaction_action.gd calls this via duck-typing; it maps lasso concepts
# (begin_query, record_dispatch, …) to AppTracer.record_child calls.
#
# When no AppTracer is supplied the tracer is a no-op.
extends RefCounted

var _app: RefCounted  # AppTracer — may be null
var _event_id  := ""  # current input.event span
var _query_id  := ""  # current lasso.query child span


func _init(app_tracer: RefCounted = null) -> void:
	_app = app_tracer


# ── called by desktop_mouse_action / xr_action_host ──────────────────────────

func begin_input(event_type: String, screen_pos: Vector2) -> void:
	if _app == null:
		return
	_event_id = _app.begin_event(event_type, {
		"screen.x": screen_pos.x,
		"screen.y": screen_pos.y,
	})


func end_input(error: String = "") -> void:
	if _app == null or _event_id.is_empty():
		return
	_app.end_event(_event_id, error)
	_event_id = ""


# ── called by interaction_action ─────────────────────────────────────────────

func begin_query(poi_count: int) -> void:
	if _app == null or _event_id.is_empty():
		return
	_query_id = _app.begin_child(_event_id, "lasso.query", {"poi.count": poi_count})


func record_query_result(found: bool, canvas_item_type: String, pos2d: Vector2) -> void:
	if _app == null or _query_id.is_empty():
		return
	_app._otel.set_attributes(_query_id, {
		"query.found":      found,
		"canvas_item.type": canvas_item_type,
		"pos2d.x":          pos2d.x,
		"pos2d.y":          pos2d.y,
	})


func end_query() -> void:
	if _app == null or _query_id.is_empty():
		return
	_app.finish_child(_query_id, true, "ok")
	_query_id = ""


func record_dispatch(action: String, canvas_item_type: String, pos2d: Vector2) -> void:
	if _app == null or _event_id.is_empty():
		return
	_app.record_child(_event_id, "lasso.dispatch", {
		"dispatch.action":  action,
		"canvas_item.type": canvas_item_type,
		"pos2d.x":          pos2d.x,
		"pos2d.y":          pos2d.y,
	}, true, "dispatched")


# ── stubs kept for call-site compatibility ────────────────────────────────────

func begin_pose(_uv: Vector2, _source: Vector3) -> void:
	pass  # not traced; motion is too noisy


func end_pose() -> void:
	pass
