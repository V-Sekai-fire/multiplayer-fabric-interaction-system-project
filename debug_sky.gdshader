shader_type sky;

#include "res://addons/s2h/include/s2h_glsl.gdshaderinc"
#include "res://addons/s2h/include/s2h.gdshaderinc"
#include "res://addons/s2h/include/s2h_3d.gdshaderinc"

// ULID chars as ASCII codes — 26 chars (Crockford base32)
uniform int ulid_chars[26];

void sky() {
	// World-centric: infinite grid + horizon + X/Z axis indicators
	Context3D ctx;
	s2h_init(ctx, POSITION, EYEDIR);
	s2h_drawSkybox(ctx);

	// Overlay ULID text in top-left corner using ContextGather + FRAGCOORD
	ContextGather ui;
	s2h_init(ui, FRAGCOORD.xy);
	s2h_setScale(ui, 2.0);
	s2h_setCursor(ui, float2(8.0, 8.0));
	for (int i = 0; i < 26; i++) {
		s2h_printCharacter(ui, uint(ulid_chars[i]));
	}

	// Composite: S2H text on top of sky grid
	float3 sky_col = ctx.dstColor.rgb;
	COLOR = float3(sky_col * (1.0 - ui.dstColor.a) + ui.dstColor.rgb);
}
