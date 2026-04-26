shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix;

#include "res://addons/s2h/include/s2h_glsl.gdshaderinc"
#include "res://addons/s2h/include/s2h.gdshaderinc"

uniform vec3 cam_pos = vec3(0.0);
uniform float dist_to_canvas = 1.5;

const float PX_W = 200.0;
const float PX_H = 80.0;

void fragment() {
	float2 px = UV * float2(PX_W, PX_H) + 0.5;

	ContextGather ui;
	s2h_init(ui, px);
	s2h_setScale(ui, 1.0);

	s2h_drawRectangle(ui, float2(2.0, 2.0), float2(PX_W - 2.0, PX_H - 2.0),
		float4(0.0, 0.0, 0.0, 0.8));

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
	s2h_printTxt(ui, _D, _COLON, _SPACE);
	s2h_printFloat(ui, dist_to_canvas);
	s2h_printTxt(ui, _m);

	ALBEDO = ui.dstColor.rgb;
	ALPHA  = ui.dstColor.a;
}
