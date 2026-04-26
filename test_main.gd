extends Node

var _elapsed := 0.0
var _xr_cam: XRCamera3D
var _sky_mat: ShaderMaterial
var _left_ctrl: XRController3D
var _right_ctrl: XRController3D


func _ready() -> void:
	Engine.max_fps = 60
	var ulid := _gen_ulid()
	call_deferred("_set_title", ulid)
	var ui_vp := _setup_xr(ulid)
	if ui_vp == null:
		ui_vp = _make_fallback_ui_vp()
	_setup_2d(ui_vp)


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


# Returns the SubViewport that owns TestInteractionUI, or null if XR not available.
func _setup_xr(ulid: String) -> SubViewport:
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface == null or not xr_interface.is_initialized():
		return null

	var xr_vp := SubViewport.new()
	xr_vp.name = "XRViewport"
	xr_vp.use_xr = true
	add_child(xr_vp)

	# S2H debug sky
	var sky_shader := load("res://debug_sky.gdshader") as Shader
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = sky_shader
	if ulid != "":
		var ascii_arr := PackedInt32Array()
		for i in range(ulid.length()):
			ascii_arr.append(ulid.unicode_at(i))
		_sky_mat.set_shader_parameter("ulid_chars", ascii_arr)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	xr_vp.add_child(world_env)

	# InteractionManager — must be in viewport before XRControllerInteractionHelper
	var im: Node = load("res://addons/interaction_system/interaction_manager.gd").new()
	im.name = "InteractionManager"
	xr_vp.add_child(im)

	var origin := XROrigin3D.new()
	origin.name = "XROrigin3D"
	xr_vp.add_child(origin)

	_xr_cam = XRCamera3D.new()
	_xr_cam.name = "XRCamera3D"
	_xr_cam.position = Vector3.UP * 1.6
	origin.add_child(_xr_cam)

	# CanvasPlane: owns SubViewport + ControlRoot + 3D mesh
	# canvas_scale: physical_width = canvas_width * 0.5 * canvas_scale
	# 1280 * 0.5 * 0.0025 = 1.6 m  /  720 * 0.5 * 0.0025 = 0.9 m
	var cp: Node3D = load("res://addons/canvas_plane/canvas_plane.gd").new()
	cp.name = "CanvasPlane"
	cp.set("canvas_width",  1280.0)
	cp.set("canvas_height", 720.0)
	cp.set("canvas_scale",  0.0025)
	cp.position = Vector3.UP * 1.6 + Vector3.FORWARD * 1.5
	origin.add_child(cp)  # triggers cp._ready() → SubViewport + ControlRoot created

	# canvas_plane sets FLAG_ALBEDO_TEXTURE_FORCE_SRGB which causes incorrect gamma
	# in the XR linear pipeline — viewport texture is already in the right space.
	var cp_mat := cp.get("material") as StandardMaterial3D
	if cp_mat:
		cp_mat.set_flag(BaseMaterial3D.FLAG_ALBEDO_TEXTURE_FORCE_SRGB, false)

	# Single TestInteractionUI lives inside the CanvasPlane
	var test_ui: Node = load("res://addons/interaction_system/test/test_interaction_ui.gd").new()
	test_ui.name = "TestInteractionUI"
	cp.call("get_control_root").add_child(test_ui)

	# Register canvas deferred so test_ui._ready() has run first
	im.call_deferred("register_canvas", cp)

	# XRControllerInteractionHelper: spawns one xr_action_host.tscn per tracker
	var helper: Node3D = load("res://addons/interaction_system/xr_controller_interaction_helper.gd").new()
	helper.name = "XRControllerInteractionHelper"
	helper.set("controller_scene", load("res://addons/interaction_system/example/xr_action_host.tscn"))
	origin.add_child(helper)

	for hand in ["left", "right"]:
		var ctrl := XRController3D.new()
		ctrl.name = "XRController_" + hand
		ctrl.tracker = "/" + hand + "_hand/controller"
		origin.add_child(ctrl)
		if hand == "left":  _left_ctrl  = ctrl
		else:               _right_ctrl = ctrl

	return cp.call("get_control_viewport") as SubViewport


# Fallback when XR is not available: standalone SubViewport for 2D window only.
func _make_fallback_ui_vp() -> SubViewport:
	var ui_vp := SubViewport.new()
	ui_vp.name = "UIViewport"
	ui_vp.size = Vector2i(1280, 720)
	ui_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(ui_vp)
	var test = load("res://addons/interaction_system/test/test_interaction_ui.gd").new()
	test.name = "TestInteractionUI"
	ui_vp.add_child(test)
	return ui_vp


func _setup_2d(ui_vp: SubViewport) -> void:
	var layer := CanvasLayer.new()
	layer.name = "GUI2D"
	add_child(layer)

	var fwd := _InputForwarder.new()
	fwd.name = "UIInputForwarder"
	fwd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fwd.ui_vp = ui_vp
	layer.add_child(fwd)

	var tr := TextureRect.new()
	tr.name = "UITextureRect"
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.texture = ui_vp.get_texture()
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(tr)


class _InputForwarder extends Control:
	var ui_vp: SubViewport

	func _gui_input(event: InputEvent) -> void:
		if ui_vp == null:
			return
		if event is InputEventMouse:
			var vp_size := Vector2(ui_vp.size)
			var my_size := size
			var scale := vp_size / my_size
			var ev := event.duplicate() as InputEventMouse
			ev.position = event.position * scale
			if ev is InputEventMouseMotion:
				(ev as InputEventMouseMotion).relative = \
					(event as InputEventMouseMotion).relative * scale
			ui_vp.push_input(ev)
		else:
			ui_vp.push_input(event)
		accept_event()


func _process(delta: float) -> void:
	_elapsed += delta
	if _xr_cam and _sky_mat:
		var wpos := _xr_cam.global_position
		var dist := wpos.distance_to(Vector3.UP * 1.6 + Vector3.FORWARD * 1.5)
		_sky_mat.set_shader_parameter("cam_pos", wpos)
		_sky_mat.set_shader_parameter("dist_to_canvas", dist)
		_sky_mat.set_shader_parameter("time_sec", _elapsed)
		if _left_ctrl:
			_sky_mat.set_shader_parameter("left_ctrl_pos",  _left_ctrl.global_position)
		if _right_ctrl:
			_sky_mat.set_shader_parameter("right_ctrl_pos", _right_ctrl.global_position)
