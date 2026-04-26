extends Node

const QUIT_AFTER_SECONDS := 30.0

var _elapsed := 0.0
var _xr_cam: XRCamera3D
var _hud_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _canvas_world_pos := Vector3.UP * 1.6 + Vector3.FORWARD * 1.5

func _ready() -> void:
	Engine.max_fps = 60
	# Stamp window title with a ULID so each run is uniquely identifiable
	var ulid := _gen_ulid()
	# Deferred so the window exists before we rename it
	call_deferred("_set_title", ulid)
	_setup_2d()
	_setup_xr(ulid)

func _set_title(ulid: String) -> void:
	DisplayServer.window_set_title("Interaction System Test [%s]" % ulid)

func _gen_ulid() -> String:
	# ULID: 10-char timestamp (ms since epoch) + 16-char random, Crockford base32
	const CHARS := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
	var t := int(Time.get_unix_time_from_system() * 1000)
	var result := ""
	for i in range(10):
		result = CHARS[t & 0x1F] + result
		t >>= 5
	for i in range(16):
		result += CHARS[randi() % 32]
	return result

func _setup_2d() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GUI2D"
	add_child(layer)
	var test = load("res://addons/interaction_system/test/test_interaction_ui.gd").new()
	test.name = "TestInteractionUI"
	layer.add_child(test)

func _setup_xr(ulid: String = "") -> void:
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface == null or not xr_interface.is_initialized():
		return

	var xr_vp := SubViewport.new()
	xr_vp.name = "XRViewport"
	xr_vp.use_xr = true
	add_child(xr_vp)

	# Debug sky: grid + horizon + X/Z axes via ShaderToHuman s2h_drawSkybox
	var sky_shader := load("res://debug_sky.gdshader") as Shader
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = sky_shader
	# Push ULID as array of ASCII codes
	if ulid != "":
		var ascii_arr := PackedInt32Array()
		for i in range(ulid.length()):
			ascii_arr.append(ulid.unicode_at(i))
		_sky_mat.set_shader_parameter("ulid_chars", ascii_arr)
	var sky_mat := _sky_mat
	var sky := Sky.new()
	sky.sky_material = sky_mat
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

	# S2H HUD quad: position + crosshair + distance bar, parented to camera
	var hud_shader := load("res://hud.gdshader") as Shader
	_hud_mat = ShaderMaterial.new()
	_hud_mat.shader = hud_shader
	var hud_mesh := MeshInstance3D.new()
	hud_mesh.name = "HUD"
	var hud_quad := QuadMesh.new()
	hud_quad.size = Vector2(0.22, 0.088)
	hud_mesh.mesh = hud_quad
	hud_mesh.material_override = _hud_mat
	hud_mesh.position = Vector3(-0.14, -0.10, -0.35)
	_xr_cam.add_child(hud_mesh)

	var ui_vp := SubViewport.new()
	ui_vp.name = "UIViewport"
	ui_vp.size = Vector2i(1280, 720)
	ui_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	xr_vp.add_child(ui_vp)

	var ui_xr = load("res://addons/interaction_system/test/test_interaction_ui.gd").new()
	ui_xr.name = "TestInteractionUIXR"
	ui_vp.add_child(ui_xr)

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

	if ResourceLoader.exists("res://addons/canvas_plane/canvas_plane.gd"):
		var im = load("res://addons/interaction_system/interaction_manager.gd").new()
		im.name = "InteractionManager"
		add_child(im)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= QUIT_AFTER_SECONDS:
		get_tree().quit()
	if _hud_mat and _xr_cam:
		var wpos := _xr_cam.global_position
		_hud_mat.set_shader_parameter("cam_pos", wpos)
		_hud_mat.set_shader_parameter("dist_to_canvas",
			wpos.distance_to(_canvas_world_pos))
