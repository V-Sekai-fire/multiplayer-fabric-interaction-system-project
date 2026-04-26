# Copyright (c) 2018-present. This file is part of V-Sekai https://v-sekai.org/.
# SaracenOne & K. S. Ernest (Fire) Lee & Lyuma & MMMaellon & Contributors
# canvas_plane.gd
# SPDX-License-Identifier: MIT

@tool
@icon("icon_canvas_3d.svg")
class_name CanvasPlane
extends Canvas3D

@export_range(0.0, 1.0) var canvas_anchor_x: float = 0.0:
	set = set_canvas_anchor_x

@export_range(0.0, 1.0) var canvas_anchor_y: float = 0.0:
	set = set_canvas_anchor_y

# Defaults to 16:9
@export var canvas_width: float = DisplayServer.window_get_size(0).x:
	set = set_canvas_width

@export var canvas_height: float = DisplayServer.window_get_size(0).y:
	set = set_canvas_height

# Uniform scale: physical_width = canvas_width * 0.5 * canvas_plane_scale
# Named canvas_plane_scale to avoid conflicting with Canvas3D.canvas_scale (Vector2)
@export var canvas_plane_scale: float = 0.01:
	set = set_canvas_plane_scale

# Scale-safe: derives UV from the node's own global transform so any
# parent scale or runtime canvas_plane_scale change is accounted for.
func global_to_viewport(p_origin: Vector3) -> Vector2:
	var local := global_transform.affine_inverse() * p_origin
	var half_w := canvas_width  * 0.5 * canvas_plane_scale
	var half_h := canvas_height * 0.5 * canvas_plane_scale
	var u :=        (local.x /  half_w + 1.0) * 0.5
	var v := 1.0 - ((local.y /  half_h + 1.0) * 0.5)  # flip Y: 2D top = 3D high
	return Vector2(u * canvas_width, v * canvas_height)


func _update() -> void:
	# Keep canvas_size in sync so canvas_3d_anchor.update_transform() has valid data.
	canvas_size = Vector2(canvas_width, canvas_height)

	var canvas_width_offset:  float = (canvas_width  * 0.5 * 0.5) - (canvas_width  * 0.5 * canvas_anchor_x)
	var canvas_height_offset: float = -(canvas_height * 0.5 * 0.5) + (canvas_height * 0.5 * canvas_anchor_y)

	if mesh:
		mesh.set_size(Vector2(canvas_width, canvas_height) * 0.5)

	if mesh_instance:
		mesh_instance.set_position(Vector3(canvas_width_offset, canvas_height_offset, 0))

	if pointer_receiver == null:
		pointer_receiver = function_pointer_receiver_const.new()
		spatial_root.add_child(pointer_receiver)
	pointer_receiver.set_position(Vector3(canvas_width_offset, canvas_height_offset, 0))
	if collision_shape:
		if interactable:
			var box_shape := BoxShape3D.new()
			box_shape.set_size(Vector3(canvas_width * 0.5, canvas_height * 0.5, 0.0))
			collision_shape.set_shape(box_shape)
			pointer_receiver.add_child(collision_shape)
			pointer_receiver.set_name("PointerReceiver")
			pointer_receiver.collision_mask = collision_mask
			pointer_receiver.collision_layer = collision_layer
			if pointer_receiver.pointer_pressed.connect(Callable(self, "on_pointer_pressed")) != OK:
				push_error("Failed to connect pointer_receiver.pointer_pressed signal.")
			if pointer_receiver.pointer_release.connect(Callable(self, "on_pointer_release")) != OK:
				push_error("Failed to connect pointer_receiver.pointer_release signal.")
			if pointer_receiver.pointer_moved.connect(Callable(self, "on_pointer_moved")) != OK:
				push_error("Failed to connect pointer_receiver.pointer_moved signal.")
		else:
			collision_shape.set_shape(null)

	if spatial_root:
		spatial_root.set_scale(Vector3(canvas_plane_scale, canvas_plane_scale, canvas_plane_scale))


func get_control_root() -> Control:
	return control_root


func get_control_viewport() -> SubViewport:
	return viewport


func set_canvas_anchor_x(p_anchor: float) -> void:
	canvas_anchor_x = p_anchor
	set_process(true)


func set_canvas_anchor_y(p_anchor: float) -> void:
	canvas_anchor_y = p_anchor
	set_process(true)


func set_canvas_width(p_width: float) -> void:
	canvas_width = p_width
	set_process(true)


func set_canvas_height(p_height: float) -> void:
	canvas_height = p_height
	set_process(true)


func set_canvas_plane_scale(p_scale: float) -> void:
	canvas_plane_scale = p_scale
	set_process(true)


func _set_mesh_material(p_material: Material) -> void:
	if mesh:
		if mesh is PrimitiveMesh:
			mesh.set_material(p_material)
		else:
			mesh.surface_set_material(0, p_material)


func on_pointer_moved(from: Vector3, to: Vector3) -> void:
	var local_from := global_to_viewport(from)
	var local_to   := global_to_viewport(to)
	var event := InputEventMouseMotion.new()
	event.set_global_position(local_to)
	event.set_relative(local_to - local_from)
	event.set_button_mask(mouse_mask)
	event.set_pressure(0.5)
	if viewport:
		viewport.push_input(event)
	previous_mouse_position = local_to


func on_pointer_pressed(at: Vector3, p_doubleclick: bool) -> void:
	var local_at := global_to_viewport(at)
	mouse_mask = 1
	var event := InputEventMouseButton.new()
	event.set_button_index(MOUSE_BUTTON_LEFT)
	event.set_pressed(true)
	event.set_global_position(local_at)
	event.set_button_mask(mouse_mask)
	event.set_double_click(p_doubleclick)
	if viewport:
		viewport.push_unhandled_input(event)
	previous_mouse_position = local_at


func on_pointer_release(at: Vector3, p_doubleclick: bool) -> void:
	var local_at := global_to_viewport(at)
	mouse_mask = 0
	var event := InputEventMouseButton.new()
	event.set_button_index(MOUSE_BUTTON_LEFT)
	event.set_pressed(false)
	event.set_global_position(local_at)
	event.set_button_mask(mouse_mask)
	event.set_double_click(p_doubleclick)
	if viewport:
		viewport.push_unhandled_input(event)
	previous_mouse_position = local_at


func _process(_delta: float) -> void:
	_update()
	set_process(false)


func _setup_viewport() -> void:
	spatial_root = Node3D.new()
	spatial_root.set_name("SpatialRoot")
	add_child(spatial_root, true)

	viewport = SubViewport.new()
	viewport.size = Vector2(canvas_width, canvas_height)
	viewport.transparent_bg = true
	viewport.audio_listener_enable_2d = false
	viewport.audio_listener_enable_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.set_name("SubViewport")
	spatial_root.add_child(viewport, true)

	control_root = Control.new()
	control_root.set_name("ControlRoot")
	control_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(control_root, true)

	if not Engine.is_editor_hint():
		for child in get_children():
			if child.owner != null:
				child.get_parent().remove_child(child)
				control_root.add_child(child, true)


func _ready() -> void:
	_setup_viewport()

	mesh = PlaneMesh.new()

	mesh_instance = MeshInstance3D.new()
	mesh_instance.set_mesh(mesh)
	mesh_instance.rotate_x(-PI / 2)
	mesh_instance.set_scale(Vector3(1.0, -1.0, -1.0))
	mesh_instance.set_name("MeshInstance3D")
	mesh_instance.set_skeleton_path(NodePath())
	mesh_instance.set_cast_shadows_setting(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	spatial_root.add_child(mesh_instance, true)

	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.set_flag(BaseMaterial3D.FLAG_ALBEDO_TEXTURE_FORCE_SRGB, true)

	if not Engine.is_editor_hint():
		(material as StandardMaterial3D).albedo_texture = viewport.get_texture()

	_update()
	_set_mesh_material(material)
