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
	var ui_vp := _setup_ui_viewport()
	_setup_2d(ui_vp)
	_setup_xr(ulid, ui_vp)

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

func _setup_ui_viewport() -> SubViewport:
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
	var tr := TextureRect.new()
	tr.name = "UITextureRect"
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.texture = ui_vp.get_texture()
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layer.add_child(tr)

func _setup_xr(ulid: String, ui_vp: SubViewport) -> void:
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface == null or not xr_interface.is_initialized():
		return

	var xr_vp := SubViewport.new()
	xr_vp.name = "XRViewport"
	xr_vp.use_xr = true
	add_child(xr_vp)

	# S2H debug sky: world grid + ULID + position text via GLSL preprocessor
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
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	xr_vp.add_child(world_env)

	var origin := XROrigin3D.new()
	origin.name = "XROrigin3D"
	xr_vp.add_child(origin)

	_xr_cam = XRCamera3D.new()
	_xr_cam.name = "XRCamera3D"
	_xr_cam.position = Vector3.UP * 1.6
	origin.add_child(_xr_cam)

	# Canvas plane: shared UIViewport texture on a quad in XR space
	# Same SubViewport shown in both the 2D window and XR — single source of truth
	var quad := MeshInstance3D.new()
	quad.name = "CanvasPlane"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.6, 0.9)
	quad.mesh = mesh
	quad.position = Vector3.UP * 1.6 + Vector3.FORWARD * 1.5
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ui_vp.get_texture()
	mat.flags_unshaded = true
	quad.material_override = mat
	origin.add_child(quad)

	for hand in ["left", "right"]:
		var ctrl := XRController3D.new()
		ctrl.name = "XRController_" + hand
		ctrl.tracker = "/" + hand + "_hand/controller"
		origin.add_child(ctrl)
		if hand == "left":  _left_ctrl  = ctrl
		else:               _right_ctrl = ctrl

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
