extends Node

const CanvasUtils := preload("res://addons/canvas_plane/canvas_utils.gd")


var _elapsed := 0.0
var _cp: Node3D      # canvas plane — world-space position set at scene design time
var _origin: Node3D  # XROrigin3D or SceneRoot — parent of canvas + camera
# Debug labels — one set per controller + one per button centre
var _dbg_lasso_labels: Array[Label3D] = []   # indexed by controller slot
var _dbg_src_labels:   Array[Label3D] = []
var _dbg_poi_labels:   Array[Label3D] = []
var _dbg_ready := false
var _shader_tick := 0.0          # accumulator for 20 Hz shader updates
const SHADER_HZ := 20.0
var _xr_cam: XRCamera3D
var _sky_mat: ShaderMaterial
var _left_ctrl: XRController3D
var _right_ctrl: XRController3D
var _interaction_action: Node
var _helper: Node3D
var _cp_anchors: Array[Node3D] = []
var _otel_chars  := PackedInt32Array()
var _otel_counts := PackedInt32Array()
# OTel span persistence — ring buffer, only oldest slot fades
const OTEL_N      := 8    # history depth
const OTEL_CLEN   := 20   # max chars per span name + tag
var _otel_span_n      := 0
var _otel_hist_spans: Array[String] = []   # e.g. ["lasso.dispatch press", "lasso.query found"]
var _otel_hist_counts: Array[int]   = []   # collapsed repeat count per entry
var _otel_fade_age    := 0.0


func _ready() -> void:
	Engine.max_fps = 60
	_otel_chars.resize(OTEL_N * OTEL_CLEN)
	_otel_counts.resize(OTEL_N)
	_init_otel()
	var ulid := _gen_ulid()
	call_deferred("_set_title", ulid)
	var ui_vp := _setup_scene(ulid)
	_setup_2d(ui_vp)


func _init_otel() -> void:
	if not ClassDB.class_exists("OpenTelemetry"):
		return
	if Engine.has_meta("_otel_instance"):
		return
	var otel := OpenTelemetry.new()
	otel.name = "OTel"
	var raw: String = ProjectSettings.get_setting("application/config/name", "godot-project")
	var service_name := raw.to_lower().replace(" ", "-").replace("_", "-")
	otel.init_tracer_provider("main", "http://localhost:4318", {"service.name": service_name})
	# Register synchronously so lasso_tracer._init() finds it without a tree search.
	Engine.set_meta("_otel_instance", otel)
	# Deferred add avoids "parent busy" error during _ready() tree setup.
	get_tree().root.add_child.call_deferred(otel)


func _set_title(ulid: String) -> void:
	DisplayServer.window_set_title("Interaction System Test [%s]" % ulid)


func _gen_ulid() -> String:
	const CHARS := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
	var t := int(Time.get_unix_time_from_system() * 1000)
	var result := ""
	for i in range(10):
		result = CHARS[t & 0x1F] + result
		t >>= 5
	for i in range(16):
		result += CHARS[randi() % 32]
	return result


# Sets up the 3D scene (XR or desktop), canvas plane, lasso, and DMA.
# Returns the canvas plane's SubViewport so _setup_2d can display it.
func _setup_scene(ulid: String) -> SubViewport:
	var xr_interface := XRServer.find_interface("OpenXR")
	var has_xr := xr_interface != null and xr_interface.is_initialized()

	var scene_vp := SubViewport.new()
	scene_vp.name = "SceneViewport"
	if has_xr:
		scene_vp.use_xr = true
	add_child(scene_vp)

	# S2H debug sky (XR only — requires rendering context)
	if has_xr:
		var sky_shader := load("res://debug_sky.gdshader") as Shader
		_sky_mat = ShaderMaterial.new()
		_sky_mat.shader = sky_shader
		if ulid != "":
			var ascii_arr := PackedInt32Array()
			for c in ulid:
				ascii_arr.append(c.unicode_at(0))
			_sky_mat.set_shader_parameter("ulid_chars", ascii_arr)
		var sky := Sky.new()
		sky.sky_material = _sky_mat
		var env := Environment.new()
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		var world_env := WorldEnvironment.new()
		world_env.environment = env
		scene_vp.add_child(world_env)

	# InteractionManager — always present
	var im: Node = load("res://addons/interaction_system/interaction_manager.gd").new()
	im.name = "InteractionManager"
	scene_vp.add_child(im)

	# Origin node — XROrigin3D with XR, plain Node3D with regular Camera3D otherwise
	var origin: Node3D
	if has_xr:
		var xr_origin := XROrigin3D.new()
		xr_origin.name = "XROrigin3D"
		scene_vp.add_child(xr_origin)
		origin = xr_origin

		_xr_cam = XRCamera3D.new()
		_xr_cam.name = "XRCamera3D"
		origin.add_child(_xr_cam)  # XR tracking sets the actual position

		# XR controller tracking nodes (used for sky shader HUD positions)
		for hand in ["left", "right"]:
			var ctrl := XRController3D.new()
			ctrl.name = "XRController_" + hand
			ctrl.tracker = hand + "_hand"
			origin.add_child(ctrl)
			if hand == "left":  _left_ctrl  = ctrl
			else:               _right_ctrl = ctrl

		# Wire XRServer tracker events → xr_action_host → lasso
		_helper = load("res://addons/interaction_system/xr_controller_interaction_helper.gd").new()
		_helper.name = "XRControllerInteractionHelper"
		_helper.set("controller_scene", load("res://addons/interaction_system/example/xr_action_host.tscn"))
		origin.add_child(_helper)
	else:
		# Desktop mode: add debug sky so s2h HUD is visible
		var sky_shader := load("res://debug_sky.gdshader") as Shader
		_sky_mat = ShaderMaterial.new()
		_sky_mat.shader = sky_shader
		var sky := Sky.new()
		sky.sky_material = _sky_mat
		var env := Environment.new()
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		var world_env := WorldEnvironment.new()
		world_env.environment = env
		scene_vp.add_child(world_env)

		var node3d := Node3D.new()
		node3d.name = "SceneRoot"
		scene_vp.add_child(node3d)
		origin = node3d

	# Canvas plane — always present, holds the 2D UI SubViewport.
	# All subsequent positioning derives from cp.position after it is placed.
	var cp: Node3D = load("res://addons/canvas_plane/canvas_plane.gd").new()
	cp.name = "CanvasPlane"
	# canvas_plane sizes mesh at canvas_width * 0.5 units → scale = 2 * UI_PIXELS_TO_METER
	# keeps physical_width = canvas_width * UI_PIXELS_TO_METER (Lean: halfW = canvas_width/2/1024 m).
	cp.set("canvas_plane_scale", 2.0 * CanvasUtils.UI_PIXELS_TO_METER)
	# canvas_anchor_x/y must equal Canvas3D.offset_ratio.x/y (both default 0.5)
	# so the mesh pivot and anchor coordinate origin agree.
	cp.set("canvas_anchor_x", 0.5)
	cp.set("canvas_anchor_y", 0.5)
	# XR: canvas position is deferred to _process once tracking delivers a real camera transform.
	# Desktop: place canvas in front of origin; camera looks at it from behind.
	# World position: scene design decision — canvas is a fixed object in the room.
	# In XR this is relative to XROrigin3D (floor centre). In desktop, _setup_cam overrides.
	cp.position = Vector3(0.0, 1.0, -1.5)
	origin.add_child(cp)
	_cp = cp
	_origin = origin

	if not has_xr:
		# Desktop: derive canvas position and camera distance from camera FOV + canvas height.
		var cam := Camera3D.new()
		cam.name = "Camera3D"
		origin.add_child(cam)
		var canvas_half_h: float = cp.get("canvas_height") * CanvasUtils.UI_PIXELS_TO_METER * 0.5
		# Distance so full canvas height fits within vertical FOV with no margin clipping.
		var viewer_dist := canvas_half_h / tan(deg_to_rad(cam.fov) * 0.5)
		cp.position = Vector3(0.0, 0.0, -viewer_dist * 0.5)  # canvas halfway between origin and camera
		cam.position = cp.position + Vector3(0.0, 0.0, viewer_dist)
		cam.call_deferred("look_at", cp.position)

	if has_xr:
		var cp_mat := cp.get("material") as StandardMaterial3D
		if cp_mat:
			cp_mat.set_flag(BaseMaterial3D.FLAG_ALBEDO_TEXTURE_FORCE_SRGB, false)

	# Test UI inside canvas
	var test_ui: Node = load("res://addons/interaction_system/test/test_interaction_ui.gd").new()
	test_ui.name = "TestInteractionUI"
	cp.call("get_control_root").add_child(test_ui)

	# Register canvas (deferred so controls finish layout first)
	im.call_deferred("register_canvas", cp)

	# AnimationPlayer: vary canvas position to stress-test lasso tracking.
	# DMA and canvas_3d_anchor both read global_transform each frame, so they
	# should track the moving canvas correctly. Verifies no hardcoded positions remain.
	call_deferred("_start_canvas_animation")

	# Desktop mouse → lasso bridge — always active.
	# In XR mode the XR controller drives pose; DMA adds a second input path for
	# mouse clicks directly in the Godot window (the OS routes clicks to the focused
	# Godot window regardless of whether the XR simulator is running).
	var dma: Node3D = load("res://desktop_mouse_action.gd").new()
	dma.name = "DesktopMouseAction"
	dma.set("interaction_manager", im)
	dma.set("canvas_plane_node", cp)
	var ia: Node3D = load("res://addons/interaction_system/controller_actions/interaction_action.gd").new()
	ia.name = "InteractionAction"
	dma.add_child(ia)
	add_child(dma)
	_interaction_action = ia

	# XR: show canvas plane texture overlay; Desktop: show full 3D scene with s2h sky
	if has_xr:
		return cp.call("get_control_viewport") as SubViewport
	else:
		return scene_vp


func _start_canvas_animation() -> void:
	if _origin == null or _cp == null:
		return
	var player := AnimationPlayer.new()
	player.name = "CanvasAnimPlayer"
	_origin.add_child(player)

	var anim := Animation.new()
	anim.loop_mode = Animation.LOOP_LINEAR
	anim.length = 6.0  # 6-second cycle

	# Vary canvas Y: 0.5 m (kneeling) → 1.5 m (standing) → back
	var ty := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(ty, NodePath("CanvasPlane:position:y"))
	anim.track_insert_key(ty, 0.0, _cp.position.y - 0.5)
	anim.track_insert_key(ty, 3.0, _cp.position.y + 0.5)
	anim.track_insert_key(ty, 6.0, _cp.position.y - 0.5)

	# Vary canvas Z: 1.0 m closer → 1.0 m further → back
	var tz := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(tz, NodePath("CanvasPlane:position:z"))
	anim.track_insert_key(tz, 0.0, _cp.position.z + 1.0)
	anim.track_insert_key(tz, 3.0, _cp.position.z - 1.0)
	anim.track_insert_key(tz, 6.0, _cp.position.z + 1.0)

	var lib := AnimationLibrary.new()
	lib.add_animation(&"vary_canvas", anim)
	player.add_animation_library(&"", lib)
	player.play("vary_canvas")


func _make_debug_label(text: String, color: Color) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.modulate = color
	lbl.outline_modulate = Color.BLACK
	lbl.outline_size = 4
	lbl.font_size = 14
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.pixel_size = 0.002
	_cp.get_parent().add_child(lbl)
	return lbl


func _init_debug_labels() -> void:
	# One lasso-endpoint + source pair per controller
	var ctrl_colors := [Color.ORANGE, Color.YELLOW, Color.PINK, Color.MAGENTA]
	var src_colors  := [Color.CYAN,   Color.AQUA,   Color.WHITE, Color.LIGHT_BLUE]
	var actions := _get_all_interaction_actions()
	for i in actions.size():
		_dbg_lasso_labels.append(_make_debug_label("lasso→", ctrl_colors[i % ctrl_colors.size()]))
		_dbg_src_labels.append(  _make_debug_label("src→",   src_colors[i  % src_colors.size()]))
	# One label per canvas_3d_anchor = button centre; cache anchor refs for _update_debug_labels
	for anchor in _cp.find_children("*", "Canvas3DAnchor", true, false):
		var anchor3d := anchor as Node3D
		var path: String = str(anchor3d.get("canvas_item_node_path"))
		var lbl := _make_debug_label("btn:" + path.get_file(), Color.LIME_GREEN)
		_dbg_poi_labels.append(lbl)
		_cp_anchors.append(anchor3d)
	_dbg_ready = true


# Display the canvas plane's SubViewport as a 2D texture overlay on the main window.
func _setup_2d(ui_vp: SubViewport) -> void:
	if ui_vp == null:
		return
	var layer := CanvasLayer.new()
	layer.name = "GUI2D"
	add_child(layer)
	var tr := TextureRect.new()
	tr.name = "UITextureRect"
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.texture = ui_vp.get_texture()
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(tr)


func _get_active_interaction_action() -> Node:
	var all := _get_all_interaction_actions()
	return all[0] if not all.is_empty() else null


func _get_all_interaction_actions() -> Array:
	if _interaction_action:
		return [_interaction_action]
	# XR mode: one InteractionAction per xr_action_host (= per controller)
	var result := []
	if _helper:
		for host in _helper.get_children():
			var ia := host.get_node_or_null("InteractionAction")
			if ia:
				result.append(ia)
	return result


func _update_debug_labels() -> void:
	# Godot: Y-up right-handed, forward = -Z, Euler order YXZ.
	# basis.z = local +Z; -basis.z = forward (into the scene).
	# Button centres: canvas_3d_anchor updates its transform in _process each frame.
	for i in min(_cp_anchors.size(), _dbg_poi_labels.size()):
		var anchor := _cp_anchors[i]
		var pos    := anchor.global_position
		var normal := -anchor.global_transform.basis.z  # -Z = forward/toward-viewer
		_dbg_poi_labels[i].global_position = pos + normal * 0.02
		_dbg_poi_labels[i].text = "btn\n(%.2f, %.2f, %.2f)\ndir (%.2f, %.2f, %.2f)" % [
			pos.x, pos.y, pos.z, normal.x, normal.y, normal.z]

	# One lasso endpoint + source label per controller.
	var actions := _get_all_interaction_actions()
	for i in min(actions.size(), _dbg_lasso_labels.size()):
		var ia: Node = actions[i]
		var _t = ia.get("current_target_pos_3d")
		var tgt: Vector3 = _t if _t != null else Vector3.ZERO
		var _x = ia.get("transform")
		var src_xf: Transform3D = _x if _x != null else Transform3D()
		var src_pos := src_xf.origin
		var src_dir := -src_xf.basis.z  # forward of source frame
		_dbg_lasso_labels[i].global_position = tgt + Vector3(0.0, 0.06 * (i + 1), 0.0)
		_dbg_lasso_labels[i].text = "lasso[%d]→\n(%.2f, %.2f, %.2f)" % [i, tgt.x, tgt.y, tgt.z]
		_dbg_src_labels[i].global_position = src_pos + Vector3(0.0, 0.06 * (i + 1), 0.0)
		_dbg_src_labels[i].text = "src[%d]\n(%.2f, %.2f, %.2f)\ndir (%.2f, %.2f, %.2f)" % [
			i, src_pos.x, src_pos.y, src_pos.z, src_dir.x, src_dir.y, src_dir.z]


func _process(delta: float) -> void:
	_elapsed += delta
	_shader_tick += delta
	_otel_fade_age += delta

	# Initialise debug labels once canvas anchors are laid out (deferred after register_canvas).
	if _cp and not _dbg_ready and _cp.get_child_count() > 2:
		_init_debug_labels()

	# Update debug labels every frame.
	if _dbg_ready:
		_update_debug_labels()

	var ia := _get_active_interaction_action()
	var tracer = ia.get_parent().get("_tracer") if ia else null

	if tracer:
		var n: int = tracer.spans_flushed
		if n != _otel_span_n and tracer.last_span != &"":
			_otel_span_n = n
			var label: String = "%s %s" % [tracer.last_span, tracer.last_tag]
			if not _otel_hist_spans.is_empty() and _otel_hist_spans[0] == label:
				_otel_hist_counts[0] += 1
			else:
				_push_otel_str(label)
		elif n != _otel_span_n:
			_otel_span_n = n

	if not _sky_mat:
		return

	# High-frequency params every frame
	_sky_mat.set_shader_parameter("time_sec", _elapsed)
	if _xr_cam:
		var wpos := _xr_cam.global_position
		_sky_mat.set_shader_parameter("cam_pos", wpos)
		_sky_mat.set_shader_parameter("dist_to_canvas",
			wpos.distance_to(_cp.global_position) if _cp else 1.5)
		if _left_ctrl:
			_sky_mat.set_shader_parameter("left_ctrl_pos",  _left_ctrl.global_position)
		if _right_ctrl:
			_sky_mat.set_shader_parameter("right_ctrl_pos", _right_ctrl.global_position)

	# 20 Hz throttled params (lasso + OTel)
	if _shader_tick < 1.0 / SHADER_HZ:
		return
	_shader_tick = 0.0

	if ia:
		_sky_mat.set_shader_parameter("lasso_found",     1 if ia.get("lasso_found") else 0)
		_sky_mat.set_shader_parameter("lasso_poi_count", ia.get("lasso_poi_count") as int)
		_sky_mat.set_shader_parameter("lasso_eucl_dist", ia.get("lasso_eucl_dist") as float)
		_sky_mat.set_shader_parameter("lasso_ang_dist",  ia.get("lasso_ang_dist") as float)

	# Encode string history as flat int[OTEL_N * OTEL_CLEN] ASCII char codes
	_otel_chars.fill(0)
	_otel_counts.fill(0)
	for i in _otel_hist_spans.size():
		var s: String = _otel_hist_spans[i]
		_otel_counts[i] = _otel_hist_counts[i]
		for j in min(s.length(), OTEL_CLEN):
			_otel_chars[i * OTEL_CLEN + j] = s.unicode_at(j)
	_sky_mat.set_shader_parameter("otel_span_n",      _otel_span_n)
	_sky_mat.set_shader_parameter("otel_fade_age",    _otel_fade_age)
	_sky_mat.set_shader_parameter("otel_hist_chars",  _otel_chars)
	_sky_mat.set_shader_parameter("otel_hist_counts", _otel_counts)


func _push_otel_str(label: String) -> void:
	var full := _otel_hist_spans.size() >= OTEL_N
	if full and _otel_fade_age < 3.0:
		return
	if full:
		_otel_hist_spans.pop_back()
		_otel_hist_counts.pop_back()
		_otel_fade_age = 0.0
	_otel_hist_spans.push_front(label)
	_otel_hist_counts.push_front(1)
