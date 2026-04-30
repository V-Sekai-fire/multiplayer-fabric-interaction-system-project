extends Node

var _elapsed := 0.0
var _xr_cam: XRCamera3D
var _sky_mat: ShaderMaterial
var _left_ctrl: XRController3D
var _right_ctrl: XRController3D
var _interaction_action: Node


func _ready() -> void:
	Engine.max_fps = 60
	var ulid := _gen_ulid()
	call_deferred("_set_title", ulid)
	var ui_vp := _setup_scene(ulid)
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
		_xr_cam.position = Vector3.UP * 1.6
		origin.add_child(_xr_cam)

		# XR controller tracking nodes (no action host — DMA is the sole input)
		for hand in ["left", "right"]:
			var ctrl := XRController3D.new()
			ctrl.name = "XRController_" + hand
			ctrl.tracker = "/" + hand + "_hand/controller"
			origin.add_child(ctrl)
			if hand == "left":  _left_ctrl  = ctrl
			else:               _right_ctrl = ctrl
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

		# Regular camera looking at the canvas plane from the front
		var cam := Camera3D.new()
		cam.name = "Camera3D"
		cam.position = Vector3(0.0, 1.6, 3.5)
		origin.add_child(cam)
		cam.call_deferred("look_at", Vector3(0.0, 1.6, 1.5))

	# Canvas plane — always present, holds the 2D UI SubViewport
	var cp: Node3D = load("res://addons/canvas_plane/canvas_plane.gd").new()
	cp.name = "CanvasPlane"
	cp.set("canvas_width",       1280.0)
	cp.set("canvas_height",      720.0)
	cp.set("canvas_plane_scale", 0.0025)
	cp.position = Vector3.UP * 1.6 + Vector3.FORWARD * 1.5
	origin.add_child(cp)

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

	# Desktop mouse → lasso bridge — always active (sole input source)
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


func _process(delta: float) -> void:
	_elapsed += delta
	if _sky_mat and not _xr_cam:
		# Desktop mode: update s2h shader params each frame
		_sky_mat.set_shader_parameter("time_sec", _elapsed)
		if _interaction_action:
			_sky_mat.set_shader_parameter("lasso_found",     1 if _interaction_action.lasso_found else 0)
			_sky_mat.set_shader_parameter("lasso_poi_count", _interaction_action.lasso_poi_count)
			_sky_mat.set_shader_parameter("lasso_eucl_dist", _interaction_action.lasso_eucl_dist)
			_sky_mat.set_shader_parameter("lasso_ang_dist",  _interaction_action.lasso_ang_dist)
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
		if _interaction_action:
			_sky_mat.set_shader_parameter("lasso_found",     1 if _interaction_action.lasso_found else 0)
			_sky_mat.set_shader_parameter("lasso_poi_count", _interaction_action.lasso_poi_count)
			_sky_mat.set_shader_parameter("lasso_eucl_dist", _interaction_action.lasso_eucl_dist)
			_sky_mat.set_shader_parameter("lasso_ang_dist",  _interaction_action.lasso_ang_dist)
