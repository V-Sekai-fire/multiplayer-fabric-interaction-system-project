// Minimal XR HUD: camera position + crosshair + distance-to-canvas bar
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix;

#include "res://addons/s2h/include/s2h_glsl.gdshaderinc"
#include "res://addons/s2h/include/s2h.gdshaderinc"

uniform vec3 cam_pos = vec3(0.0);
uniform float dist_to_canvas = 1.5;

const float PX_W = 200.0;
const float PX_H = 80.0;

void fragment() {
	vec2 px = UV * vec2(PX_W, PX_H) + 0.5;

	ContextGather ui;
	s2h_init(ui, px);
	s2h_setScale(ui, 1.0);

	// Dark background
	s2h_drawRectangleAA(ui, float2(0.0, 0.0), float2(PX_W, PX_H),
		float4(0.0, 0.0, 0.0, 0.8), float4(0.0, 0.0, 0.0, 0.6), 1.5);

	// Camera position: X Y Z
	s2h_setCursor(ui, float2(4.0, 4.0));
	s2h_printTxt(ui, _X, _COLON, _SPACE);
	s2h_printFloat(ui, cam_pos.x);
	s2h_printLF(ui);
	s2h_printTxt(ui, _Y, _COLON, _SPACE);
	s2h_printFloat(ui, cam_pos.y);
	s2h_printLF(ui);
	s2h_printTxt(ui, _Z, _COLON, _SPACE);
	s2h_printFloat(ui, cam_pos.z);
	s2h_printLF(ui);

	// Distance to canvas bar
	s2h_printTxt(ui, _D, _COLON, _SPACE);
	float frac = clamp(1.0 - dist_to_canvas / 3.0, 0.0, 1.0);
	ui.textColor = float4(s2h_colorRampRGB(frac), 1.0);
	s2h_progress(ui, 10u, frac);

	// Crosshair at center
	s2h_drawCrosshair(ui, float2(PX_W * 0.5, PX_H * 0.5), 8.0,
		float4(1.0, 1.0, 1.0, 0.6), 1.0);

	ALBEDO = ui.dstColor.rgb;
	ALPHA = ui.dstColor.a;
}
