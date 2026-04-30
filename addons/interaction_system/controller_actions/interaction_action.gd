extends "./base_action.gd"

@export_node_path("MeshInstance3D") var laser_mesh: NodePath = ^"Laser":
	set(n):
		laser_mesh = n
		laser_mesh_instance = get_node_or_null(n) as MeshInstance3D
@onready var laser_mesh_instance: MeshInstance3D = get_node_or_null(laser_mesh) as MeshInstance3D

var current_poi: LassoPoint
var current_snap_node: Node
var current_canvas_item: CanvasItem
var current_canvas_plane: CanvasPlane
var current_pos_2d: Vector2
var current_target_pos_3d: Vector3
var pressed_buttons: Dictionary[StringName, bool]

# Lasso debug state — read by test_main._process() → debug_sky shader
var lasso_found     := false
var lasso_poi_count := 0
var lasso_eucl_dist := 0.0
var lasso_ang_dist  := 0.0


func on_action_added() -> void:
	pass

func on_action_removed() -> void:
	pass

func on_tracking_lost() -> void:
	pressed_buttons.clear()
	current_snap_node = null


func on_button_event(mb: InputEventMouseButton) -> bool:
	if mb.pressed:
		pressed_buttons[mb.resource_name] = true
	else:
		pressed_buttons.erase(mb.resource_name)
	interaction_manager.handle_pointer_moved_2d(null, current_canvas_item, current_pos_2d)
	mb.global_position = current_pos_2d.round()
	mb.position = current_pos_2d.round()
	interaction_manager.handle_mouse_button(current_canvas_item, mb)
	var tracer = get_parent().get("_tracer")
	if tracer and current_canvas_item:
		tracer.record_dispatch(
			"press" if mb.pressed else "release",
			current_canvas_item.get_class(),
			current_pos_2d)
	return mb.pressed


func on_pose_changed(pose: XRPose) -> void:
	super.on_pose_changed(pose)
	if pose.name != primary_pose_name:
		return

	var snap_locked := not pressed_buttons.is_empty()
	var tracer = get_parent().get("_tracer")
	lasso_poi_count = interaction_manager.lasso_poi_count
	if tracer:
		tracer.begin_query(lasso_poi_count)

	var result: Array = interaction_manager.lasso_db.calc_top_two_snapping_power(
		transform, current_snap_node, 1.0, 0.0, snap_locked
	)
	var found_poi := result[0] as LassoPoint
	lasso_found = found_poi != null and found_poi.get_origin() != null

	if not lasso_found:
		lasso_eucl_dist = 0.0
		lasso_ang_dist  = 0.0
		if tracer:
			tracer.record_query_result(false, "", Vector2.ZERO)
			tracer.end_query()
		return

	current_poi       = found_poi
	current_snap_node = found_poi.get_origin()

	var local_pos: Vector3 = transform.affine_inverse() * current_snap_node.global_position
	lasso_eucl_dist = local_pos.length()
	lasso_ang_dist  = local_pos.angle_to(Vector3(0, 0, -1))

	current_canvas_plane = interaction_manager.get_canvas_plane_from_poi(current_poi)
	var old_canvas_item  := current_canvas_item
	current_canvas_item  = interaction_manager.get_canvas_item_from_poi(current_poi)
	current_target_pos_3d = current_snap_node.global_position

	if current_canvas_plane == null or current_canvas_item == null:
		if tracer:
			tracer.record_query_result(false, "no_canvas", Vector2.ZERO)
			tracer.end_query()
		return

	current_pos_2d = interaction_manager.get_position_on_canvas_plane(
		current_canvas_plane, current_target_pos_3d)

	if tracer:
		var ci_type := current_canvas_item.get_class() if current_canvas_item else "null"
		tracer.record_query_result(true, ci_type, current_pos_2d, current_target_pos_3d)
		tracer.end_query()

	interaction_manager.handle_pointer_moved_2d(old_canvas_item, current_canvas_item, current_pos_2d)
	if laser_mesh_instance != null:
		laser_mesh_instance.set_instance_shader_parameter(
			&"target",
			laser_mesh_instance.global_transform.affine_inverse() * current_target_pos_3d)
