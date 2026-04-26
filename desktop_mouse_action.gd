# Desktop mouse → lasso bridge.
#
# Lives in the main scene (not xr_vp) so it receives window _input() natively.
# Converts screen mouse position to a 3D canvas-plane pose, then fires through
# the interaction_action child — same lasso query path as XR controllers.
extends "res://addons/interaction_system/action_host.gd"

const LassoTracer := preload("res://addons/interaction_system/lasso_tracer.gd")

# Set from test_main.gd after the canvas plane is created.
var canvas_plane_node: Node3D

var _pose   := XRPose.new()
var _win_vp : Viewport
var _tracer : RefCounted   # LassoTracer instance


func _ready() -> void:
	_pose.name = &"aim"
	_pose.tracking_confidence = XRPose.XR_TRACKING_CONFIDENCE_HIGH
	_win_vp = get_viewport()
	_tracer = LassoTracer.new()
	super._ready()


func _input(event: InputEvent) -> void:
	if interaction_manager == null or canvas_plane_node == null:
		return
	if event is InputEventMouseMotion:
		_tracer.begin_input("MouseMotion", (event as InputEventMouseMotion).global_position)
		_update_pose((event as InputEventMouseMotion).global_position)
		_tracer.end_input()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_tracer.begin_input("MouseButton", mb.global_position)
		_update_pose(mb.global_position)
		var clone := mb.duplicate() as InputEventMouseButton
		clone.resource_name = str(mb.button_index)
		fire_button_event(clone)
		_tracer.end_input()


func _update_pose(screen_pos: Vector2) -> void:
	var cw: float = canvas_plane_node.get("canvas_width")
	var ch: float = canvas_plane_node.get("canvas_height")
	if cw < 1.0 or ch < 1.0:
		return

	var win := Vector2(_win_vp.size)
	if win.x < 1.0 or win.y < 1.0:
		return

	# Pillarbox/letterbox: map screen pixel to normalised canvas UV [0,1]²
	var uv: Vector2
	if win.x * ch > win.y * cw:
		var cw_screen := win.y * cw / ch
		uv.x = (screen_pos.x - (win.x - cw_screen) * 0.5) / cw_screen
		uv.y = screen_pos.y / win.y
	else:
		var ch_screen := win.x * ch / cw
		uv.x = screen_pos.x / win.x
		uv.y = (screen_pos.y - (win.y - ch_screen) * 0.5) / ch_screen
	uv = uv.clamp(Vector2.ZERO, Vector2.ONE)

	# Source position uses UI_PIXELS_TO_METER = 1/1024 — same scale as canvas_3d_anchor.
	# canvas_3d_anchor places anchors at (px - cw/2, ch/2 - py) / 1024 in canvas-plane local space.
	const UI_PM := 1.0 / 1024.0
	var x3 := (uv.x * cw - cw * 0.5) * UI_PM
	var y3 := (ch * 0.5 - uv.y * ch) * UI_PM

	var cp_xf := canvas_plane_node.global_transform
	var point_on_canvas := cp_xf.origin + cp_xf.basis.x * x3 + cp_xf.basis.y * y3
	var source_pos := point_on_canvas + cp_xf.basis.z * 0.1

	_pose.transform = Transform3D(Basis.looking_at(-cp_xf.basis.z), source_pos)
	_tracer.begin_pose(uv, source_pos)
	fire_pose_changed(_pose)
