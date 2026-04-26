shader_type canvas_item;

#include "res://addons/s2h/include/s2h_glsl.gdshaderinc"
#include "res://addons/s2h/include/s2h.gdshaderinc"

uniform vec3 cam_pos = vec3(0.0);
uniform float dist_to_canvas = 1.5;
uniform vec3 left_ctrl_pos  = vec3(0.0);
uniform vec3 right_ctrl_pos = vec3(0.0);
uniform float time_sec = 0.0;
uniform int ulid_chars[26];
// Fixed viewport size matching ui_vp.size
uniform vec2 vp_size = vec2(1280.0, 720.0);

void fragment() {
	ContextGather ui;
	s2h_init(ui, FRAGCOORD.xy);
	s2h_setScale(ui, 2.0);

	// ── info panel: bottom-left ──────────────────────────────────────
	float panel_x = 8.0;
	float panel_y = vp_size.y - 148.0;

	s2h_drawRectangleAA(ui,
		float2(panel_x - 4.0, panel_y - 4.0),
		float2(panel_x + 280.0, vp_size.y - 4.0),
		float4(0.5,0.5,0.5,0.8), float4(0,0,0,0.5), 1.5);

	s2h_setCursor(ui, float2(panel_x, panel_y));

	s2h_printTxt(ui, _H, _e, _a, _d, _COLON, _SPACE);
	s2h_printFloat(ui, cam_pos.x);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, cam_pos.y);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, cam_pos.z);
	s2h_printLF(ui);

	s2h_printTxt(ui, _L, _COLON, _SPACE);
	s2h_printFloat(ui, left_ctrl_pos.x);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, left_ctrl_pos.y);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, left_ctrl_pos.z);
	s2h_printLF(ui);

	s2h_printTxt(ui, _R, _COLON, _SPACE);
	s2h_printFloat(ui, right_ctrl_pos.x);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, right_ctrl_pos.y);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, right_ctrl_pos.z);
	s2h_printLF(ui);

	s2h_printTxt(ui, _D, _COLON, _SPACE);
	s2h_printFloat(ui, dist_to_canvas);
	s2h_printTxt(ui, _m, _SPACE);
	ui.textColor = float4(s2h_colorRampRGB(clamp(1.0 - dist_to_canvas / 3.0, 0.0, 1.0)), 1.0);
	s2h_progress(ui, 8u, clamp(1.0 - dist_to_canvas / 3.0, 0.0, 1.0));
	ui.textColor = float4(1.0);
	s2h_printLF(ui);

	s2h_printTxt(ui, _t, _COLON, _SPACE);
	s2h_printFloat(ui, time_sec);
	s2h_printTxt(ui, _s);

	// ── crosshair at canvas centre ───────────────────────────────────
	s2h_drawCrosshair(ui, vp_size * 0.5, 14.0, float4(1.0, 1.0, 0.3, 0.9), 1.5);

	// ── ULID: bottom-right ───────────────────────────────────────────
	s2h_setCursor(ui, float2(vp_size.x - 222.0, vp_size.y - 20.0));
	for (int i = 0; i < 26; i++) {
		s2h_printCharacter(ui, uint(ulid_chars[i]));
	}

	COLOR = ui.dstColor;
}
