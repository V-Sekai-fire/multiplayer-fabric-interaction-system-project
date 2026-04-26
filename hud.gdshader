// Minimal XR HUD: camera position + distance-to-canvas bar
// Self-contained: no S2H includes (spatial shader pipeline doesn't support them)
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix;

uniform vec3 cam_pos = vec3(0.0);
uniform float dist_to_canvas = 1.5;

// Draw a single digit (0-9) at px position, return true if pixel is inside glyph
// 5x7 bitmap font encoded as 35-bit masks
float digit(vec2 px, vec2 origin, int d) {
	vec2 p = floor(px - origin);
	if (p.x < 0.0 || p.x > 4.0 || p.y < 0.0 || p.y > 6.0) return 0.0;
	// 10 glyphs × 35 bits — stored as 5 rows of uint, row0=top
	int col = int(p.x);
	int row = int(p.y);
	// Simple 3×5 segment patterns mapped to 5 columns
	// Using a compact per-digit column mask
	int masks[10] = int[10](
		0x1F11111F, // 0
		0x04040404, // 1  (simplified)
		0x1F011F10, // 2  (simplified)
		0x1F011F01, // 3
		0x11111F01, // 4
		0x1F101F01, // 5
		0x1F101F11, // 6
		0x1F010101, // 7
		0x1F111F11, // 8
		0x1F111F01  // 9
	);
	// Use UV distance field instead — draw a colored block per digit
	return 1.0;
}

// Render a colored horizontal bar
float bar(vec2 px, vec2 tl, vec2 br) {
	return step(tl.x, px.x) * step(px.x, br.x) *
		   step(tl.y, px.y) * step(px.y, br.y);
}

// Map 0-1 value to green-yellow-red
vec3 traffic_light(float t) {
	return t > 0.5
		? mix(vec3(1,1,0), vec3(0,1,0), (t - 0.5) * 2.0)
		: mix(vec3(1,0,0), vec3(1,1,0), t * 2.0);
}

void fragment() {
	// UV → pixel coords in a 128×64 virtual canvas
	vec2 res = vec2(128.0, 64.0);
	vec2 px  = UV * res;

	vec4 col = vec4(0.0, 0.0, 0.0, 0.75); // dark background

	// Border
	float border = bar(px, vec2(0), res) - bar(px, vec2(2), res - 2.0);
	col = mix(col, vec4(0.5, 0.5, 0.5, 1.0), border);

	// Distance-to-canvas bar (green=close, red=far), max range 3m
	float frac = clamp(1.0 - dist_to_canvas / 3.0, 0.0, 1.0);
	float bar_w = (res.x - 8.0) * frac;
	float in_bar = bar(px, vec2(4.0, 48.0), vec2(4.0 + bar_w, 58.0));
	col = mix(col, vec4(traffic_light(frac), 1.0), in_bar);

	// Bar track outline
	float in_track = bar(px, vec2(3.0, 47.0), vec2(res.x - 4.0, 59.0)) -
					 bar(px, vec2(4.0, 48.0), vec2(res.x - 4.0, 58.0));
	col = mix(col, vec4(0.4, 0.4, 0.4, 1.0), in_track);

	// Crosshair at center
	vec2 center = res * 0.5;
	float ch_h = bar(px, center + vec2(-6.0, -0.5), center + vec2(6.0, 0.5));
	float ch_v = bar(px, center + vec2(-0.5, -6.0), center + vec2(0.5, 6.0));
	col = mix(col, vec4(1.0, 1.0, 1.0, 0.8), max(ch_h, ch_v));

	// Position bands: encode X/Y/Z as colored strips in upper area
	// X = red strip, Y = green strip, Z = blue strip (normalized ±3m)
	float xn = clamp((cam_pos.x + 3.0) / 6.0, 0.0, 1.0);
	float yn = clamp((cam_pos.y     ) / 4.0, 0.0, 1.0); // 0-4m range
	float zn = clamp((cam_pos.z + 3.0) / 6.0, 0.0, 1.0);

	float xs = bar(px, vec2(4.0, 6.0),  vec2(4.0 + (res.x-8.0)*xn, 14.0));
	float ys = bar(px, vec2(4.0, 18.0), vec2(4.0 + (res.x-8.0)*yn, 26.0));
	float zs = bar(px, vec2(4.0, 30.0), vec2(4.0 + (res.x-8.0)*zn, 38.0));

	col = mix(col, vec4(1.0, 0.3, 0.3, 1.0), xs); // X red
	col = mix(col, vec4(0.3, 1.0, 0.3, 1.0), ys); // Y green
	col = mix(col, vec4(0.3, 0.5, 1.0, 1.0), zs); // Z blue

	ALBEDO = col.rgb;
	ALPHA  = col.a;
}
