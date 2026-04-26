shader_type canvas_item;

#include "res://addons/s2h/include/s2h_glsl.gdshaderinc"
#include "res://addons/s2h/include/s2h.gdshaderinc"

uniform vec3 cam_pos = vec3(0.0);
uniform float dist_to_canvas = 1.5;
uniform int ulid_chars[26];

void fragment() {
	ContextGather ui;
	s2h_init(ui, FRAGCOORD.xy);
	s2h_setScale(ui, 2.0);

	// Position + distance in bottom-left corner
	s2h_setCursor(ui, float2(8.0, FRAGCOORD.y - 80.0));
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

	// ULID in bottom-right corner
	s2h_setCursor(ui, float2(FRAGCOORD.x - 220.0, FRAGCOORD.y - 20.0));
	for (int i = 0; i < 26; i++) {
		s2h_printCharacter(ui, uint(ulid_chars[i]));
	}

	COLOR = ui.dstColor;
}
