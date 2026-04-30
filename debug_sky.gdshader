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
uniform int   lasso_found     = 0;
uniform int   lasso_poi_count = 0;
uniform float lasso_eucl_dist = 0.0;
uniform float lasso_ang_dist  = 0.0;
uniform int   btn_press_count = 0;

void sky() {
	Context3D ctx;
	s2h_init(ctx, POSITION, EYEDIR);
	s2h_drawSkybox(ctx);

	ContextGather ui;
	s2h_init(ui, FRAGCOORD.xy);
	s2h_setScale(ui, 2.0);
	s2h_setCursor(ui, float2(8.0, 8.0));

	// ULID — amber #f8c266
	ui.textColor = float4(0.9736, 0.7619, 0.3981, 1.0);
	for (int i = 0; i < 26; i++) {
		s2h_printCharacter(ui, uint(ulid_chars[i]));
	}
	s2h_printLF(ui);

	// Head position — sky blue #6de0f1
	ui.textColor = float4(0.4281, 0.8769, 0.9463, 1.0);
	s2h_printTxt(ui, _H, _e, _a, _d, _COLON, _SPACE);
	s2h_printFloat(ui, cam_pos.x);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, cam_pos.y);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, cam_pos.z);
	s2h_printLF(ui);

	// Left controller — warm orange #fcaa89
	ui.textColor = float4(0.9891, 0.6679, 0.5353, 1.0);
	s2h_printTxt(ui, _L, _COLON, _SPACE);
	s2h_printFloat(ui, left_ctrl_pos.x);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, left_ctrl_pos.y);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, left_ctrl_pos.z);
	s2h_printLF(ui);

	// Right controller — mint green #76dd77
	ui.textColor = float4(0.4624, 0.8660, 0.4662, 1.0);
	s2h_printTxt(ui, _R, _COLON, _SPACE);
	s2h_printFloat(ui, right_ctrl_pos.x);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, right_ctrl_pos.y);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, right_ctrl_pos.z);
	s2h_printLF(ui);

	// Distance + progress bar — neutral #e8e8e8 label, ramp on bar
	ui.textColor = float4(0.9102, 0.9102, 0.9102, 1.0);
	s2h_printTxt(ui, _D, _COLON, _SPACE);
	s2h_printFloat(ui, dist_to_canvas);
	s2h_printTxt(ui, _m, _SPACE);
	ui.textColor = float4(s2h_colorRampRGB(clamp(1.0 - dist_to_canvas / 3.0, 0.0, 1.0)), 1.0);
	s2h_progress(ui, 8u, clamp(1.0 - dist_to_canvas / 3.0, 0.0, 1.0));
	s2h_printLF(ui);

	// Elapsed time — lavender #becbf0
	ui.textColor = float4(0.7469, 0.7974, 0.9415, 1.0);
	s2h_printTxt(ui, _t, _COLON, _SPACE);
	s2h_printFloat(ui, time_sec);
	s2h_printTxt(ui, _s);
	s2h_printLF(ui);

	// Lasso debug — green if found, red if not
	ui.textColor = lasso_found == 1
		? float4(0.2, 0.9, 0.3, 1.0)
		: float4(0.9, 0.2, 0.2, 1.0);
	s2h_printTxt(ui, _L, _Q, _COLON, _SPACE);
	s2h_printInt(ui, lasso_poi_count);
	s2h_printTxt(ui, _p, _SPACE);
	s2h_printFloat(ui, lasso_eucl_dist);
	s2h_printTxt(ui, _m, _SPACE);
	s2h_printFloat(ui, lasso_ang_dist);
	s2h_printTxt(ui, _r);
	s2h_printLF(ui);

	// Button press count — yellow
	ui.textColor = float4(1.0, 0.9, 0.2, 1.0);
	s2h_printTxt(ui, _B, _T, _N, _COLON, _SPACE);
	s2h_printInt(ui, btn_press_count);

	float3 sky_col = ctx.dstColor.rgb;
	COLOR = float3(sky_col * (1.0 - ui.dstColor.a) + ui.dstColor.rgb);
}
