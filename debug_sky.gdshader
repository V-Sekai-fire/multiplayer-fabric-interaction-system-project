shader_type sky;

#include "res://addons/s2h/include/s2h_glsl.gdshaderinc"
#include "res://addons/s2h/include/s2h.gdshaderinc"
#include "res://addons/s2h/include/s2h_3d.gdshaderinc"

// ULID chars as ASCII codes — 26 chars (Crockford base32)
uniform int ulid_chars[26];
// Camera state — updated each frame from GDScript
uniform vec3 cam_pos = vec3(0.0);
uniform float dist_to_canvas = 1.5;

void sky() {
	// World-centric: infinite grid + horizon + X/Z axis indicators
	Context3D ctx;
	s2h_init(ctx, POSITION, EYEDIR);
	s2h_drawSkybox(ctx);

	// S2H text overlay in top-left corner via ContextGather + FRAGCOORD
	ContextGather ui;
	s2h_init(ui, FRAGCOORD.xy);
	s2h_setScale(ui, 2.0);

	// Row 1: ULID
	s2h_setCursor(ui, float2(8.0, 8.0));
	for (int i = 0; i < 26; i++) {
		s2h_printCharacter(ui, uint(ulid_chars[i]));
	}
	s2h_printLF(ui);

	// Row 2-4: camera position X Y Z
	s2h_printTxt(ui, _X, _COLON, _SPACE);
	s2h_printFloat(ui, cam_pos.x);
	s2h_printLF(ui);
	s2h_printTxt(ui, _Y, _COLON, _SPACE);
	s2h_printFloat(ui, cam_pos.y);
	s2h_printLF(ui);
	s2h_printTxt(ui, _Z, _COLON, _SPACE);
	s2h_printFloat(ui, cam_pos.z);
	s2h_printLF(ui);

	// Row 5: distance to canvas
	s2h_printTxt(ui, _D, _COLON, _SPACE);
	s2h_printFloat(ui, dist_to_canvas);
	s2h_printTxt(ui, _m);

	// Composite text over sky
	float3 sky_col = ctx.dstColor.rgb;
	COLOR = float3(sky_col * (1.0 - ui.dstColor.a) + ui.dstColor.rgb);
}
