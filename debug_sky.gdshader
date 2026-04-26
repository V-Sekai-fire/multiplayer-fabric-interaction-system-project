shader_type sky;

#include "res://addons/s2h/include/s2h_glsl.gdshaderinc"
#include "res://addons/s2h/include/s2h.gdshaderinc"
#include "res://addons/s2h/include/s2h_3d.gdshaderinc"

// Camera world transform, updated each frame from GDScript
uniform mat4 ego_basis = mat4(1.0);

void sky() {
	Context3D ctx;
	// POSITION = camera world position (available in sky shaders)
	s2h_init(ctx, POSITION, EYEDIR);

	// World-centric: infinite grid + horizon + X/Z axis indicators
	s2h_drawSkybox(ctx);

	COLOR = ctx.dstColor.rgb;
}
