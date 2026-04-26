# Desktop mouse → lasso bridge.
#
# Lives in the main scene (not xr_vp) so it receives window _input() natively.
# Converts screen mouse position to a 3D canvas-plane pose, then fires through
# the interaction_action child — same lasso query path as XR controllers.
#
# UV mapping accounts for pillarbox/letterbox at any window size.
extends "res://addons/interaction_system/action_host.gd"

const CANVAS_WIDTH_M  := 1.6
const CANVAS_HEIGHT_M := 0.9
const CANVAS_ASPECT   := CANVAS_WIDTH_M / CANVAS_HEIGHT_M

# World-space center of the canvas plane (XROrigin3D is at 0,0,0 → same coords as main scene)
var canvas_center := Vector3(0.0, 1.6, -1.5)

var _pose     := XRPose.new()
var _win_vp   : Viewport


func _ready() -> void:
	_pose.name = &"aim"
	_pose.tracking_confidence = XRPose.XR_TRACKING_CONFIDENCE_HIGH
	_win_vp = get_viewport()
	# action_host._ready() wires interaction_manager into child actions
	super._ready()


func _input(event: InputEvent) -> void:
	if interaction_manager == null:
		return
	if event is InputEventMouseMotion:
		_update_pose((event as InputEventMouseMotion).global_position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_update_pose(mb.global_position)
		var clone := mb.duplicate() as InputEventMouseButton
		clone.resource_name = str(mb.button_index)
		fire_button_event(clone)


func _update_pose(screen_pos: Vector2) -> void:
	var win := Vector2(_win_vp.size)
	var win_aspect := win.x / win.y
	var uv: Vector2

	if win_aspect > CANVAS_ASPECT:
		# Pillarbox: black bars left/right
		var cw := win.y * CANVAS_ASPECT
		uv.x = (screen_pos.x - (win.x - cw) * 0.5) / cw
		uv.y = screen_pos.y / win.y
	else:
		# Letterbox: black bars top/bottom
		var ch := win.x / CANVAS_ASPECT
		uv.x = screen_pos.x / win.x
		uv.y = (screen_pos.y - (win.y - ch) * 0.5) / ch

	uv = uv.clamp(Vector2.ZERO, Vector2.ONE)

	# 2D Y-down → 3D Y-up (matches canvas_3d_anchor convention)
	var x3 := (uv.x - 0.5) * CANVAS_WIDTH_M
	var y3 := (0.5 - uv.y) * CANVAS_HEIGHT_M

	# Source: 10 cm in front of canvas (+Z toward viewer), aimed straight at canvas (-Z)
	_pose.transform = Transform3D(
		Basis.looking_at(Vector3(0.0, 0.0, -1.0)),
		canvas_center + Vector3(x3, y3, 0.1)
	)
	fire_pose_changed(_pose)
