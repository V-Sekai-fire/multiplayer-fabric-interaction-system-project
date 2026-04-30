extends "./base_action.gd"

@export_node_path("MeshInstance3D") var laser_mesh: NodePath = ^"Laser":
	set(n):
		laser_mesh = n
		laser_mesh_instance = get_node_or_null(n) as MeshInstance3D
@onready var laser_mesh_instance: MeshInstance3D = get_node_or_null(laser_mesh) as MeshInstance3D

var query := interaction_manager_class.LassoQuery.new()

var current_poi: interaction_manager_class.LassoPOI
var current_canvas_item: CanvasItem
var current_canvas_plane: interaction_manager_class.canvas_plane_class
var current_pos_2d: Vector2
var current_target_pos_3d: Vector3
var pressed_buttons: Dictionary[StringName, bool]

# Lasso debug state — read by test_main._process() → debug_sky shader
var lasso_found    := false
var lasso_poi_count := 0
var lasso_eucl_dist := 0.0
var lasso_ang_dist  := 0.0

func on_action_added() -> void:
	pass

func on_action_removed() -> void:
	pass

func on_tracking_lost() -> void:
	pressed_buttons.clear()
	query.override_point_set.clear()

func on_button_event(mb: InputEventMouseButton) -> bool:
	var xform := transform
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

func on_pose_changed(pose: XRPose):
	super.on_pose_changed(pose)
	if pose.name != primary_pose_name:
		return

	query.source = transform
	if not pressed_buttons.is_empty():
		query.override_point_set[current_poi] = true
	else:
		query.override_point_set.clear()
	var tracer = get_parent().get("_tracer")
	var poi_count := interaction_manager.lasso_db.point_set.size()
	if tracer:
		tracer.begin_query(poi_count)

	var found := interaction_manager.query_pointer_3d(query)

	lasso_found = found
	lasso_poi_count = poi_count
	if found and query.out_poi_to_local.has(query.out_best_poi):
		var local_pos := query.out_poi_to_local[query.out_best_poi]
		lasso_eucl_dist = local_pos.length()
		lasso_ang_dist  = local_pos.angle_to(Vector3(0.0, 0.0, -1.0))
	else:
		lasso_eucl_dist = 0.0
		lasso_ang_dist  = 0.0

	if not found:
		if tracer:
			tracer.record_query_result(false, "", Vector2.ZERO)
			tracer.end_query()
		return

	current_poi = query.out_best_poi
	if current_poi == null:
		if tracer:
			tracer.record_query_result(false, "no_poi", Vector2.ZERO)
			tracer.end_query()
		return
	current_canvas_plane = interaction_manager.get_canvas_plane_from_poi(query.out_best_poi)
	var old_canvas_item: CanvasItem = current_canvas_item
	current_canvas_item = interaction_manager.get_canvas_item_from_poi(query.out_best_poi)
	current_target_pos_3d = query.get_position_3d(current_poi)

	current_pos_2d = interaction_manager.get_position_on_canvas_plane(current_canvas_plane, current_target_pos_3d)

	if tracer:
		var ci_type := current_canvas_item.get_class() if current_canvas_item else "null"
		tracer.record_query_result(true, ci_type, current_pos_2d)
		tracer.end_query()

	interaction_manager.handle_pointer_moved_2d(old_canvas_item, current_canvas_item, current_pos_2d)
	if laser_mesh_instance != null:
		# print("Target pos 3d = " + str(current_target_pos_3d) + " / Target 2d = " + str(current_pos_2d))
		laser_mesh_instance.set_instance_shader_parameter(&"target", laser_mesh_instance.global_transform.affine_inverse() * current_target_pos_3d)
