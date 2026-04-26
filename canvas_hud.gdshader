shader_type canvas_item;

#include "res://addons/s2h/include/s2h_glsl.gdshaderinc"
#include "res://addons/s2h/include/s2h.gdshaderinc"

uniform vec3 cam_pos = vec3(0.0);
uniform float dist_to_canvas = 1.5;
uniform vec3 left_ctrl_pos  = vec3(0.0);
uniform vec3 right_ctrl_pos = vec3(0.0);
uniform float time_sec = 0.0;
uniform int ulid_chars[26];

void fragment() {
	ContextGather ui;
	s2h_init(ui, FRAGCOORD.xy);
	s2h_setScale(ui, 2.0);

	// ── info panel (bottom-left) ─────────────────────────────────────
	s2h_setCursor(ui, float2(8.0, FRAGCOORD.y - 140.0));

	// framed box around debug info
	s2h_drawRectangleAA(ui,
		float2(4.0,       FRAGCOORD.y - 148.0),
		float2(280.0,     FRAGCOORD.y - 4.0),
		float4(0.5,0.5,0.5,0.8), float4(0,0,0,0.5), 1.5);

	// head position
	s2h_printTxt(ui, _H, _e, _a, _d, _COLON, _SPACE);
	s2h_printFloat(ui, cam_pos.x);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, cam_pos.y);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, cam_pos.z);
	s2h_printLF(ui);

	// left controller
	s2h_printTxt(ui, _L, _COLON, _SPACE);
	s2h_printFloat(ui, left_ctrl_pos.x);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, left_ctrl_pos.y);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, left_ctrl_pos.z);
	s2h_printLF(ui);

	// right controller
	s2h_printTxt(ui, _R, _COLON, _SPACE);
	s2h_printFloat(ui, right_ctrl_pos.x);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, right_ctrl_pos.y);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, right_ctrl_pos.z);
	s2h_printLF(ui);

	// distance to canvas + progress bar
	s2h_printTxt(ui, _D, _COLON, _SPACE);
	s2h_printFloat(ui, dist_to_canvas);
	s2h_printTxt(ui, _m, _SPACE);
	ui.textColor = float4(s2h_colorRampRGB(clamp(1.0 - dist_to_canvas / 3.0, 0.0, 1.0)), 1.0);
	s2h_progress(ui, 8u, clamp(1.0 - dist_to_canvas / 3.0, 0.0, 1.0));
	ui.textColor = float4(1.0);
	s2h_printLF(ui);

	// elapsed time
	s2h_printTxt(ui, _t, _COLON, _SPACE);
	s2h_printFloat(ui, time_sec);
	s2h_printTxt(ui, _s);

	// ── crosshair at canvas centre ───────────────────────────────────
	float2 center = float2(FRAGCOORD.x * 0.5, FRAGCOORD.y * 0.5);
	s2h_drawCrosshair(ui, center, 12.0, float4(1.0, 1.0, 0.3, 0.9), 1.5);

	// ── ULID top-right ───────────────────────────────────────────────
	s2h_setCursor(ui, float2(FRAGCOORD.x - 220.0, 8.0));
	for (int i = 0; i < 26; i++) {
		s2h_printCharacter(ui, uint(ulid_chars[i]));
	}

	COLOR = ui.dstColor;
}
