## S2HCompositorEffect
##
## Injects ShaderToHuman debug overlay as a POST_TRANSPARENT CompositorEffect.
## Runs after opaque objects, sky, and transparent objects are drawn.
## Has full access to the colour buffer and depth buffer.
##
## Usage:
##   var effect := S2HCompositorEffect.new()
##   camera.compositor = Compositor.new()
##   camera.compositor.compositor_effects = [effect]
@tool
extends CompositorEffect
class_name S2HCompositorEffect

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID

func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	RenderingServer.call_on_render_thread(_init_gpu)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _pipeline.is_valid(): _rd.free_rid(_pipeline)
		if _shader.is_valid():   _rd.free_rid(_shader)

func _init_gpu() -> void:
	_rd = RenderingServer.get_rendering_device()
	var src := RDShaderFile.new()
	src.base_error = ""
	var code_path := get_script().resource_path.get_base_dir().path_join("s2h_compositor.glsl")
	var spv: RDShaderSPIRV = src.get_spirv(load(code_path))
	if spv == null:
		push_error("S2HCompositorEffect: failed to compile s2h_compositor.glsl")
		return
	_shader   = _rd.shader_create_from_spirv(spv)
	_pipeline = _rd.compute_pipeline_create(_shader)

func _render_callback(_effect_callback_type: int, render_data: RenderData) -> void:
	if not _pipeline.is_valid():
		return

	var scene_buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if scene_buffers == null:
		return

	var size: Vector2i = scene_buffers.get_internal_size()
	if size.x == 0 || size.y == 0:
		return

	RenderingServer.call_on_render_thread(
		_dispatch.bind(scene_buffers, size))

func _dispatch(scene_buffers: RenderSceneBuffersRD, size: Vector2i) -> void:
	var color_image: RID = scene_buffers.get_color_layer(0)
	var depth_tex:   RID = scene_buffers.get_depth_layer(0)

	# Uniform set: binding 0 = color image (read/write), binding 1 = depth sampler
	var uniforms: Array[RDUniform] = []

	var u_color := RDUniform.new()
	u_color.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_color.binding = 0
	u_color.add_id(color_image)
	uniforms.append(u_color)

	var u_depth := RDUniform.new()
	u_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_depth.binding = 1
	u_depth.add_id(_rd.sampler_create(RDSamplerState.new()))
	u_depth.add_id(depth_tex)
	uniforms.append(u_depth)

	var uniform_set: RID = UniformSetCacheRD.get_cache(
		_shader, 0, uniforms)

	# Push constants: screen size + time
	var push_data := PackedByteArray()
	push_data.resize(16)
	push_data.encode_s32(0, size.x)
	push_data.encode_s32(4, size.y)
	push_data.encode_float(8, Time.get_ticks_msec() / 1000.0)
	push_data.encode_float(12, 0.0)  # padding

	var cl := _rd.draw_command_begin_label("S2H Compositor", Color.WHITE)
	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	_rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())
	_rd.compute_list_dispatch(compute_list,
		(size.x + 7) / 8,
		(size.y + 7) / 8,
		1)
	_rd.compute_list_end()
	_rd.draw_command_end_label()
