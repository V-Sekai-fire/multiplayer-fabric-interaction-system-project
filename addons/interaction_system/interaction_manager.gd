extends Node

const canvas_plane_class := preload("res://addons/canvas_plane/canvas_plane.gd")
const canvas_3d_anchor   := preload("res://addons/canvas_plane/canvas_3d_anchor.gd")

var lasso_db: LassoDB = LassoDB.new()
var canvas_planes: Array[canvas_plane_class]
var lasso_poi_count: int = 0   # tracked manually; LassoDB has no size getter


func _ready() -> void:
	get_viewport().set_meta(&"interaction_manager", self)

func _enter_tree() -> void:
	get_viewport().set_meta(&"interaction_manager", self)


func register_node_3d(node: Node3D) -> void:
	var lasso_point := LassoPoint.new()
	lasso_point.set_size(0.3)
	lasso_point.set_snapping_power(1.0)
	lasso_point.register_point(lasso_db, node)
	lasso_poi_count += 1
	node.tree_exiting.connect(_on_poi_node_exiting.bind(lasso_point))


func _on_poi_node_exiting(lasso_point: LassoPoint) -> void:
	lasso_point.unregister_point()
	lasso_poi_count -= 1


func register_canvas(cp: canvas_plane_class) -> void:
	if cp.has_meta(&"canvas_registered"):
		return
	cp.set_meta(&"canvas_registered", true)
	canvas_planes.append(cp)
	var root_control: Control = cp.control_root
	var form_element: Control = root_control.find_next_valid_focus()
	var already_added_items := {}
	var canvas_anchors := root_control.find_children("*", "Node3D", false, false)
	print(canvas_anchors)
	for anchor in canvas_anchors:
		if anchor is canvas_3d_anchor:
			var canvas_item := anchor.get_node_or_null(anchor.canvas_item_node_path)
			anchor.canvas_item_node_path = NodePath("../" + str(cp.get_path_to(canvas_item)))
			anchor.reparent(cp)
	while form_element != null:
		print("New form element: " + str(form_element))
		already_added_items[form_element] = true
		var form_3d_anchor := canvas_3d_anchor.new()
		form_3d_anchor.canvas_item_node_path = NodePath("../" + str(cp.get_path_to(form_element)))
		cp.add_child(form_3d_anchor)
		form_3d_anchor.spatial_canvas = cp
		register_node_3d(form_3d_anchor)
		var form_element_new: Control = form_element.find_next_valid_focus()
		if already_added_items.has(form_element_new):
			break
		form_element = form_element_new


func register_action_host(_action_host: Node3D) -> void:
	pass

func unregister_action_host(_action_host: Node3D) -> void:
	pass


func get_canvas_plane_from_poi(poi: LassoPoint) -> canvas_plane_class:
	if poi == null:
		return null
	var anchor := poi.get_origin() as canvas_3d_anchor
	if anchor != null:
		return anchor.spatial_canvas
	return null


func get_canvas_item_from_poi(poi: LassoPoint) -> CanvasItem:
	if poi == null:
		return null
	var anchor := poi.get_origin() as canvas_3d_anchor
	if anchor != null:
		return anchor.canvas_item
	return null


func get_position_on_canvas_plane(sc: canvas_plane_class, poi_position_3d: Vector3) -> Vector2:
	return sc.global_to_viewport(poi_position_3d)


# FIXME: We need to allow multiple mouse cursors, which Godot's input system is not designed for.
# So we should ask the caller to pass in the coordinate for each event
# And delegate our own MOUSE_ENTERED and MOUSE_EXITED signals for each control.
func handle_pointer_moved_2d(last_canvas_item: CanvasItem, new_canvas_item: CanvasItem, pos_2d: Vector2) -> void:
	if new_canvas_item != null:
		var viewport: Viewport = new_canvas_item.get_viewport()
		if viewport != null:
			var event := InputEventMouseMotion.new()
			event.global_position = pos_2d.floor()
			event.position = pos_2d.floor()
			event.set_relative(Vector2(0, 0))
			event.set_button_mask(0)
			event.set_pressure(1.0)
			viewport.push_input(event, true)
			if last_canvas_item != new_canvas_item:
				var last_control := last_canvas_item as Control
				if last_control != null:
					last_control.mouse_exited.emit()
				var new_control := new_canvas_item as Control
				if new_control != null:
					new_control.mouse_entered.emit()
	else:
		var last_control := last_canvas_item as Control
		if last_control != null:
			last_control.mouse_exited.emit()


func handle_mouse_button(canvas_item: CanvasItem, mb: InputEventMouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.global_position = mb.global_position
	ev.position = mb.position
	ev.double_click = mb.double_click
	ev.factor = mb.factor
	ev.pressed = mb.pressed
	ev.canceled = mb.canceled
	ev.button_index = mb.button_index
	ev.button_mask = mb.button_mask
	var control := canvas_item as Control
	if control != null:
		var viewport := control.get_viewport()
		if viewport:
			viewport.push_input(ev, true)
