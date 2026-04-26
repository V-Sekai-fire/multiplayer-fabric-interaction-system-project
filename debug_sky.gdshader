shader_type sky;

#include "res://addons/s2h/include/s2h_glsl.gdshaderinc"
#include "res://addons/s2h/include/s2h.gdshaderinc"
#include "res://addons/s2h/include/s2h_3d.gdshaderinc"

uniform int   ulid_chars[26];
uniform vec3  cam_pos         = vec3(0.0);
uniform vec3  left_ctrl_pos   = vec3(0.0);
uniform vec3  right_ctrl_pos  = vec3(0.0);
uniform float dist_to_canvas  = 1.5;
uniform float time_sec        = 0.0;

void sky() {
	Context3D ctx;
	s2h_init(ctx, POSITION, EYEDIR);
	s2h_drawSkybox(ctx);

	ContextGather ui;
	s2h_init(ui, FRAGCOORD.xy);
	s2h_setScale(ui, 2.0);
	s2h_setCursor(ui, float2(8.0, 8.0));

	// ULID
	for (int i = 0; i < 26; i++) {
		s2h_printCharacter(ui, uint(ulid_chars[i]));
	}
	s2h_printLF(ui);

	// Head position
	s2h_printTxt(ui, _H, _e, _a, _d, _COLON, _SPACE);
	s2h_printFloat(ui, cam_pos.x);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, cam_pos.y);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, cam_pos.z);
	s2h_printLF(ui);

	// Left controller
	s2h_printTxt(ui, _L, _COLON, _SPACE);
	s2h_printFloat(ui, left_ctrl_pos.x);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, left_ctrl_pos.y);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, left_ctrl_pos.z);
	s2h_printLF(ui);

	// Right controller
	s2h_printTxt(ui, _R, _COLON, _SPACE);
	s2h_printFloat(ui, right_ctrl_pos.x);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, right_ctrl_pos.y);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, right_ctrl_pos.z);
	s2h_printLF(ui);

	// Distance + progress bar
	s2h_printTxt(ui, _D, _COLON, _SPACE);
	s2h_printFloat(ui, dist_to_canvas);
	s2h_printTxt(ui, _m, _SPACE);
	ui.textColor = float4(s2h_colorRampRGB(clamp(1.0 - dist_to_canvas / 3.0, 0.0, 1.0)), 1.0);
	s2h_progress(ui, 8u, clamp(1.0 - dist_to_canvas / 3.0, 0.0, 1.0));
	ui.textColor = float4(1.0);
	s2h_printLF(ui);

	// Elapsed time
	s2h_printTxt(ui, _t, _COLON, _SPACE);
	s2h_printFloat(ui, time_sec);
	s2h_printTxt(ui, _s);

	float3 sky_col = ctx.dstColor.rgb;
	COLOR = float3(sky_col * (1.0 - ui.dstColor.a) + ui.dstColor.rgb);
}
