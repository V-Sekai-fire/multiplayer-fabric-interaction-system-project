# SPDX-License-Identifier: MIT
# App-level OpenTelemetry tracer.
#
# Wraps the OpenTelemetry engine module and caches spans to SQLite.
# One trace per user action (click, XR button); startup recorded as a separate trace.
# Motion events are NOT traced — too noisy.
#
# SQLite schema:
#   traces(id TEXT PRIMARY KEY, service TEXT, started_at_ns INTEGER)
#   spans(span_id TEXT PRIMARY KEY, trace_id TEXT, parent_id TEXT,
#         name TEXT, kind INTEGER, started_ns INTEGER, ended_ns INTEGER,
#         status_code INTEGER, status_msg TEXT, attrs_json TEXT)
#
# Usage:
#   var t := AppTracer.new("user://traces.db")
#   var ev := t.begin_event("input.click", {"button": "left"})
#   var q  := t.begin_child(ev, "lasso.query", {"poi_count": 7})
#   t.finish_child(q, true, "found")
#   t.end_event(ev)
extends RefCounted

const _SCHEMA := [
	"""CREATE TABLE IF NOT EXISTS traces(
		id         TEXT PRIMARY KEY,
		service    TEXT,
		started_ns INTEGER
	)""",
	"""CREATE TABLE IF NOT EXISTS spans(
		span_id    TEXT PRIMARY KEY,
		trace_id   TEXT,
		parent_id  TEXT,
		name       TEXT,
		kind       INTEGER,
		started_ns INTEGER,
		ended_ns   INTEGER,
		status_code INTEGER DEFAULT 0,
		status_msg  TEXT,
		attrs_json  TEXT
	)""",
	"CREATE INDEX IF NOT EXISTS idx_spans_trace ON spans(trace_id)",
]

var _otel: OpenTelemetry
var _db:   SQLite
var _enabled := false

# Current trace_id shared across a session (set by begin_startup).
var _current_trace_id := ""

# Prepared queries (created once, reused).
var _q_insert_trace: SQLiteQuery
var _q_insert_span:  SQLiteQuery


func _init(db_path: String = "user://otel_traces.db") -> void:
	if not ClassDB.class_exists("OpenTelemetry") or not ClassDB.class_exists("SQLite"):
		push_warning("AppTracer: OpenTelemetry or SQLite module not available")
		return
	_otel = OpenTelemetry.new()
	_db   = SQLite.new()
	if not _db.open(db_path):
		push_warning("AppTracer: failed to open SQLite at %s" % db_path)
		return
	_apply_schema()
	_enabled = true


func _apply_schema() -> void:
	for stmt in _SCHEMA:
		var q := _db.create_query(stmt)
		q.execute([])
	_q_insert_trace = _db.create_query(
		"INSERT OR IGNORE INTO traces(id,service,started_ns) VALUES(?,?,?)")
	_q_insert_span  = _db.create_query(
		"""INSERT OR REPLACE INTO spans
		   (span_id,trace_id,parent_id,name,kind,started_ns,ended_ns,status_code,status_msg,attrs_json)
		   VALUES(?,?,?,?,?,?,?,?,?,?)""")


# ── trace lifecycle ────────────────────────────────────────────────────────────

## Start a startup trace. Returns the startup span id.
func begin_startup(service: String = "interaction-system") -> String:
	if not _enabled:
		return ""
	_current_trace_id = _new_trace_id()
	_q_insert_trace.execute([_current_trace_id, service, _now_ns()])
	return _otel.start_span("app.startup", 0, [], {"service.name": service})


## Finish the startup span.
func end_startup(span_id: String) -> void:
	if not _enabled or span_id.is_empty():
		return
	_otel.set_status(span_id, 1, "ok")
	_flush_span(span_id, _current_trace_id, "")


## Begin a user-interaction event (click, XR press, etc.). Returns event span id.
func begin_event(event_type: String, attrs: Dictionary = {}) -> String:
	if not _enabled:
		return ""
	var all_attrs := {"event.type": event_type}
	all_attrs.merge(attrs)
	return _otel.start_span("input.event", 0, [], all_attrs)


## Add a child span (lasso.query, lasso.dispatch, ui.reaction, …) under an event span.
## Immediately finished — use for instantaneous operations.
func record_child(parent_id: String, name: String, attrs: Dictionary = {},
		status_ok: bool = true, status_msg: String = "") -> void:
	if not _enabled or parent_id.is_empty():
		return
	var span := _otel.start_span_with_parent(name, parent_id, 0, [], attrs)
	_otel.set_status(span, 1 if status_ok else 2, status_msg)
	_otel.end_span(span)


## Open a long child span (e.g. a drag that runs across frames). Returns span id.
func begin_child(parent_id: String, name: String, attrs: Dictionary = {}) -> String:
	if not _enabled or parent_id.is_empty():
		return ""
	return _otel.start_span_with_parent(name, parent_id, 0, [], attrs)


## Close a long child span opened with begin_child.
func finish_child(span_id: String, ok: bool = true, msg: String = "") -> void:
	if not _enabled or span_id.is_empty():
		return
	_otel.set_status(span_id, 1 if ok else 2, msg)
	_otel.end_span(span_id)


## End an event span and flush all buffered spans to SQLite.
func end_event(span_id: String, error: String = "") -> void:
	if not _enabled or span_id.is_empty():
		return
	if error.is_empty():
		_otel.set_status(span_id, 1, "ok")
	else:
		_otel.record_error(span_id, error)
		_otel.set_status(span_id, 2, error)
	_otel.end_span(span_id)
	_flush_all()


# ── internal helpers ───────────────────────────────────────────────────────────

func _flush_span(span_id: String, trace_id: String, parent_id: String) -> void:
	if not _enabled:
		return
	_otel.end_span(span_id)
	_flush_all()


func _flush_all() -> void:
	var state = _otel.get_state()
	if state == null:
		return
	var doc = _otel.get_document()
	if doc == null:
		return
	# Parse the OTLP JSON and write each span to SQLite.
	var json_str: String = doc.serialize_traces(state)
	state.clear_spans()
	_persist_json(json_str)


func _persist_json(json_str: String) -> void:
	if json_str.is_empty() or not _enabled:
		return
	var root: Dictionary = JSON.parse_string(json_str)
	if root == null:
		return
	var trace_id := _current_trace_id
	for rs: Dictionary in root.get("resourceSpans", []):
		for ss: Dictionary in rs.get("scopeSpans", []):
			for sp: Dictionary in ss.get("spans", []):
				var sid:    String  = sp.get("spanId",       "")
				var pid:    String  = sp.get("parentSpanId", "")
				var name:   String  = sp.get("name",         "")
				var kind:   int     = sp.get("kind",         0)
				var t0:     int     = int(sp.get("startTimeUnixNano", 0))
				var t1:     int     = int(sp.get("endTimeUnixNano",   0))
				var status: Dictionary = sp.get("status", {})
				var scode:  int     = status.get("code",    0)
				var smsg:   String  = status.get("message", "")
				var attrs_j: String = JSON.stringify(sp.get("attributes", {}))
				if not sid.is_empty() and not trace_id.is_empty():
					_q_insert_trace.execute([trace_id, "interaction-system", t0])
					_q_insert_span.execute(
						[sid, trace_id, pid, name, kind, t0, t1, scode, smsg, attrs_j])


func _now_ns() -> int:
	return int(Time.get_unix_time_from_system() * 1_000_000_000)


func _new_trace_id() -> String:
	return "%016x%016x" % [randi(), randi()]
