# Desktop mouse → lasso bridge.
#
# Lives in the main scene (not xr_vp) so it receives window _input() natively.
# Converts screen mouse position to a 3D canvas-plane pose, then fires through
# the interaction_action child — same lasso query path as XR controllers.
#
# Scale-safe: derives canvas bounds from the mesh's world-space AABB at runtime.
# No scale parameters to configure — it just measures the actual physical canvas.
extends "res://addons/interaction_system/action_host.gd"

# Set from test_main.gd after the canvas plane is created.
var canvas_plane_node: Node3D

var _pose   := XRPose.new()
var _win_vp : Viewport


func _ready() -> void:
	_pose.name = &"aim"
	_pose.tracking_confidence = XRPose.XR_TRACKING_CONFIDENCE_HIGH
	_win_vp = get_viewport()
	super._ready()


func _input(event: InputEvent) -> void:
	if interaction_manager == null or canvas_plane_node == null:
		return
	if event is InputEventMouseMotion:
		_update_pose((event as InputEventMouseMotion).global_position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_update_pose(mb.global_position)
		var clone := mb.duplicate() as InputEventMouseButton
		clone.resource_name = str(mb.button_index)
		fire_button_event(clone)


func _get_canvas_world_bounds() -> Array:
	# Returns [center: Vector3, half_w: float, half_h: float, normal: Vector3]
	# Derived from the mesh instance's world-space AABB — no config params needed.
	var mi := canvas_plane_node.find_child("MeshInstance3D", true, false) as MeshInstance3D
	if mi == null:
		return [canvas_plane_node.global_transform.origin, 0.8, 0.45,
				canvas_plane_node.global_transform.basis.z.normalized()]
	var aabb: AABB = mi.get_aabb()
	var center := mi.global_transform * aabb.get_center()
	var size   := aabb.size * mi.global_transform.basis.get_scale()
	var half_w := maxf(absf(size.x), absf(size.z)) * 0.5
	var half_h := absf(size.y) * 0.5
	var normal := canvas_plane_node.global_transform.basis.z.normalized()
	return [center, half_w, half_h, normal]


func _update_pose(screen_pos: Vector2) -> void:
	var bounds := _get_canvas_world_bounds()
	var center: Vector3  = bounds[0]
	var half_w: float    = bounds[1]
	var half_h: float    = bounds[2]
	var normal: Vector3  = bounds[3]

	var canvas_aspect := half_w / half_h
	var win := Vector2(_win_vp.size)
	var win_aspect := win.x / win.y
	var uv: Vector2

	if win_aspect > canvas_aspect:
		var cw := win.y * canvas_aspect
		uv.x = (screen_pos.x - (win.x - cw) * 0.5) / cw
		uv.y = screen_pos.y / win.y
	else:
		var ch := win.x / canvas_aspect
		uv.x = screen_pos.x / win.x
		uv.y = (screen_pos.y - (win.y - ch) * 0.5) / ch

	uv = uv.clamp(Vector2.ZERO, Vector2.ONE)

	var cp_xform := canvas_plane_node.global_transform
	var x3 := (uv.x - 0.5) * half_w * 2.0
	var y3 := (0.5 - uv.y) * half_h * 2.0

	var point_on_canvas := center \
		+ cp_xform.basis.x.normalized() * x3 \
		+ cp_xform.basis.y.normalized() * y3
	var source_pos := point_on_canvas + normal * 0.1

	_pose.transform = Transform3D(Basis.looking_at(-normal), source_pos)
	fire_pose_changed(_pose)
