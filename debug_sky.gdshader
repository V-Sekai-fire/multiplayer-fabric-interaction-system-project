shader_type sky;

#include "res://addons/s2h/include/s2h_glsl.gdshaderinc"
#include "res://addons/s2h/include/s2h.gdshaderinc"
#include "res://addons/s2h/include/s2h_3d.gdshaderinc"

void sky() {
	Context3D ctx;
	// Ray origin at camera (world pos via POSITION), direction from sky EYEDIR
	s2h_init(ctx, vec3(0.0), EYEDIR);

	s2h_drawSkybox(ctx);

	COLOR = ctx.dstColor.rgb;
}
