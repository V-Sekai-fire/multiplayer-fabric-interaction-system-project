extends "./action_host.gd"

const LassoTracer := preload("res://addons/interaction_system/lasso_tracer.gd")

var xr_tracker: XRControllerTracker
var _tracer: RefCounted

var mb := InputEventMouseButton.new()


func _ready() -> void:
	_tracer = LassoTracer.new()
	super._ready()

func _xr_tracker_button(button_name: StringName, pressed: bool):
	mb.resource_name = button_name
	mb.global_position = Vector2(0,0)
	mb.position = Vector2(0,0)
	mb.canceled = false
	mb.button_index = 1
	mb.button_mask = 1 << mb.button_index
	mb.pressed = pressed
	mb.factor = 1.0 if pressed else 0.0
	mb.double_click = false # FIXME: Calculate by time? Or maybe use a specific binding for double click
	fire_button_event(mb)
	# SteamVR has a double click detection threshold I think
	#interaction_manager.handle_mouse_button(mb)

func _xr_tracker_pose(pose: XRPose):
	var xf := pose.transform
	var aim_dir := -xf.basis.z  # OpenXR: -Z is forward

	# Replace straight-ray source with parabolic endpoint on the canvas plane.
	# t_dist is meters along the ray; convert to time via CURVE_SPEED so gravity
	# produces a gentle visual arc (~5 cm drop per metre at 10 m/s).
	const CURVE_SPEED    := 10.0  # virtual m/s — controls parabola droop (~5 cm/m at 10 m/s)
	const HALF_GRAVITY   := 4.9   # m/s² (half of g = 9.8) — standard projectile formula ½gt²
	var canvas_planes := interaction_manager.canvas_planes if interaction_manager else []
	if not canvas_planes.is_empty():
		var cp_xf := canvas_planes[0].global_transform
		var to_plane := cp_xf.origin - xf.origin
		var plane_normal := -cp_xf.basis.z  # canvas face normal (toward viewer)
		var denom := aim_dir.dot(plane_normal)
		if abs(denom) > 0.001:
			var t_dist := to_plane.dot(plane_normal) / denom
			if t_dist > 0.01:
				var t_sec := t_dist / CURVE_SPEED
				var hit := xf.origin + aim_dir * t_dist + Vector3(0.0, -HALF_GRAVITY * t_sec * t_sec, 0.0)
				var source_pos := hit + cp_xf.basis.z * 0.1
				var new_pose := XRPose.new()
				new_pose.name = pose.name
				new_pose.tracking_confidence = pose.tracking_confidence
				new_pose.transform = Transform3D(Basis.looking_at(-cp_xf.basis.z), source_pos)
				pose = new_pose

	if _tracer:
		_tracer.begin_input("XRPose", Vector2.ZERO)
		_tracer.begin_pose(Vector2.ZERO, pose.transform.origin, aim_dir)
	fire_pose_changed(pose)
	if _tracer:
		_tracer.end_input()

func _xr_pose_lost_tracking(pose: XRPose):
	fire_tracking_lost()
	pose.tracking_confidence = XRPose.XR_TRACKING_CONFIDENCE_NONE
	fire_pose_changed(pose)
