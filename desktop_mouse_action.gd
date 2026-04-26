# Desktop mouse → lasso bridge.
#
# Lives in the main scene (not xr_vp) so it receives window _input() natively.
# Converts screen mouse position to a 3D canvas-plane pose, then fires through
# the interaction_action child — same lasso query path as XR controllers.
#
# Scale-safe: derives canvas bounds from the mesh's world-space AABB at runtime.
# No scale parameters to configure — it just measures the actual physical canvas.
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


func _get_canvas_world_bounds() -> Array:
	# Returns [center: Vector3, half_w: float, half_h: float, right: Vector3, up: Vector3, normal: Vector3]
	# Uses the PlaneMesh's 4 corners in world space — coplanar by definition for a flat quad.
	# No config params: everything derived from the mesh transform at runtime.
	var mi := canvas_plane_node.find_child("MeshInstance3D", true, false) as MeshInstance3D
	if mi == null or not (mi.mesh is PlaneMesh):
		var xf := canvas_plane_node.global_transform
		return [xf.origin, 0.8, 0.45,
				xf.basis.x.normalized(), xf.basis.y.normalized(), xf.basis.z.normalized()]
	var pm  := mi.mesh as PlaneMesh
	var hw  := pm.size.x * 0.5
	var hh  := pm.size.y * 0.5
	# Corners in PlaneMesh local space (XZ plane before rotate_x + scale on mesh_instance)
	var c00 := mi.global_transform * Vector3(-hw, 0.0, -hh)
	var c10 := mi.global_transform * Vector3( hw, 0.0, -hh)
	var c01 := mi.global_transform * Vector3(-hw, 0.0,  hh)
	var c11 := mi.global_transform * Vector3( hw, 0.0,  hh)
	var center := (c00 + c11) * 0.5
	var right  := (c10 - c00)   # world +X (left → right)
	var up_vec := (c00 - c01)   # world +Y (bottom → top); c00=top-left, c01=bottom-left
	var half_w := right.length()   * 0.5
	var half_h := up_vec.length()  * 0.5
	var normal := right.normalized().cross(up_vec.normalized())
	return [center, half_w, half_h, right.normalized(), up_vec.normalized(), normal]


func _update_pose(screen_pos: Vector2) -> void:
	var bounds  := _get_canvas_world_bounds()
	var center: Vector3 = bounds[0]
	var half_w: float   = bounds[1]
	var half_h: float   = bounds[2]
	var right:  Vector3 = bounds[3]
	var up_vec: Vector3 = bounds[4]
	var normal: Vector3 = bounds[5]

	if half_w < 0.001 or half_h < 0.001:
		return  # mesh not ready yet

	var canvas_aspect := half_w / half_h
	var win       := Vector2(_win_vp.size)
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

	# Use corner-derived right/up — tracks XROrigin3D movement since corners
	# are read from mi.global_transform at query time.
	var x3 := (uv.x - 0.5) * half_w * 2.0
	var y3 := (0.5 - uv.y) * half_h * 2.0  # flip Y: screen top = world up

	var point_on_canvas := center + right * x3 + up_vec * y3
	var source_pos      := point_on_canvas + normal * 0.1

	_pose.transform = Transform3D(Basis.looking_at(-normal), source_pos)
	_tracer.begin_pose(uv, source_pos)
	fire_pose_changed(_pose)
