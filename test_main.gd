extends Node

const QUIT_AFTER_SECONDS := 30.0

var _elapsed := 0.0
var _sky_mat: ShaderMaterial
var _xr_cam: XRCamera3D

func _ready() -> void:
	Engine.max_fps = 60
	_setup_2d()
	_setup_xr()

func _setup_2d() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GUI2D"
	add_child(layer)
	var test = load("res://addons/interaction_system/test/test_interaction_ui.gd").new()
	test.name = "TestInteractionUI"
	layer.add_child(test)

func _setup_xr() -> void:
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

	# Ego-centric axis labels: world-centric / ego-centric enum name pairs
	# at 0.6m along each local camera axis
	var axis_labels := {
		Vector3.RIGHT:   "RIGHT\nMODEL_LEFT",
		Vector3.UP:      "UP\nMODEL_TOP",
		Vector3.BACK:    "BACK\nMODEL_FRONT",
	}
	var axis_colors := {
		Vector3.RIGHT:  Color(1, 0.2, 0.2),
		Vector3.UP:     Color(0.2, 1, 0.2),
		Vector3.BACK:   Color(0.2, 0.4, 1),
	}
	for axis in axis_labels:
		var lbl := Label3D.new()
		lbl.text = axis_labels[axis]
		lbl.modulate = axis_colors[axis]
		lbl.pixel_size = 0.004
		lbl.position = _xr_cam.position + axis * 0.6
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		origin.add_child(lbl)

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
	# Push ego-centric camera transform to sky shader each frame
	if _sky_mat and _xr_cam:
		_sky_mat.set_shader_parameter("ego_basis", Projection(_xr_cam.global_transform))
