shader_type sky;

#include "res://addons/s2h/include/s2h_glsl.gdshaderinc"
#include "res://addons/s2h/include/s2h.gdshaderinc"
#include "res://addons/s2h/include/s2h_3d.gdshaderinc"

// Camera world transform, updated each frame from GDScript
uniform mat4 ego_basis = mat4(1.0);

void sky() {
	Context3D ctx;
	s2h_init(ctx, vec3(0.0), EYEDIR);

	// World-centric: infinite grid + horizon + X/Z axis indicators
	s2h_drawSkybox(ctx);

	// Ego-centric: camera local frame as 3 colored arrows at origin
	// X=red (RIGHT), Y=green (UP), Z=blue (BACK)
	s2h_drawBasis(ctx, ego_basis, 0.5);

	COLOR = ctx.dstColor.rgb;
}
