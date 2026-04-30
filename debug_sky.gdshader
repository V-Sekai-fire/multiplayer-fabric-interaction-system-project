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
uniform int   otel_span_n      = 0;
uniform float otel_fade_age    = 0.0;
uniform int   otel_hist_chars[160];    // OTEL_N(8) * OTEL_CLEN(20), ASCII
uniform int   otel_hist_counts[8];

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
	s2h_printTxt(ui, _l, _e, _f, _t, _COLON, _SPACE);
	s2h_printFloat(ui, left_ctrl_pos.x);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, left_ctrl_pos.y);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, left_ctrl_pos.z);
	s2h_printLF(ui);

	// Right controller — mint green #76dd77
	ui.textColor = float4(0.4624, 0.8660, 0.4662, 1.0);
	s2h_printTxt(ui, _r, _i, _g, _h, _t, _COLON);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, right_ctrl_pos.x);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, right_ctrl_pos.y);
	s2h_printTxt(ui, _SPACE);
	s2h_printFloat(ui, right_ctrl_pos.z);
	s2h_printLF(ui);

	// Distance + progress bar — neutral #e8e8e8 label, ramp on bar
	ui.textColor = float4(0.9102, 0.9102, 0.9102, 1.0);
	s2h_printTxt(ui, _d, _i, _s, _t, _a, _n);
	s2h_printTxt(ui, _c, _e, _COLON, _SPACE);
	s2h_printFloat(ui, dist_to_canvas);
	s2h_printTxt(ui, _m, _SPACE);
	ui.textColor = float4(s2h_colorRampRGB(clamp(1.0 - dist_to_canvas / 3.0, 0.0, 1.0)), 1.0);
	s2h_progress(ui, 8u, clamp(1.0 - dist_to_canvas / 3.0, 0.0, 1.0));
	s2h_printLF(ui);

	// Elapsed time — lavender #becbf0
	ui.textColor = float4(0.7469, 0.7974, 0.9415, 1.0);
	s2h_printTxt(ui, _t, _i, _m, _e, _COLON, _SPACE);
	s2h_printFloat(ui, time_sec);
	s2h_printTxt(ui, _s);
	s2h_printLF(ui);

	// Lasso debug — green if found, red if not
	ui.textColor = lasso_found == 1
		? float4(0.2, 0.9, 0.3, 1.0)
		: float4(0.9, 0.2, 0.2, 1.0);
	s2h_printTxt(ui, _l, _a, _s, _s, _o, _COLON);
	s2h_printTxt(ui, _SPACE);
	s2h_printInt(ui, lasso_poi_count);
	s2h_printTxt(ui, _SPACE, _p, _o, _i, _SPACE);
	s2h_printFloat(ui, lasso_eucl_dist);
	s2h_printTxt(ui, _m, _SPACE);
	s2h_printFloat(ui, lasso_ang_dist);
	s2h_printTxt(ui, _r, _a, _d);
	s2h_printLF(ui);

	// Button press count — yellow
	ui.textColor = float4(1.0, 0.9, 0.2, 1.0);
	s2h_printTxt(ui, _b, _u, _t, _t, _o, _n);
	s2h_printTxt(ui, _COLON, _SPACE);
	s2h_printInt(ui, btn_press_count);
	s2h_printLF(ui);

	// OpenTelemetry traces — cyan header: total spans flushed
	ui.textColor = float4(0.3, 0.9, 0.9, 1.0);
	s2h_printTxt(ui, _t, _r, _a, _c, _e, _s);
	s2h_printTxt(ui, _COLON, _SPACE);
	s2h_printInt(ui, otel_span_n);
	s2h_printTxt(ui, _SPACE, _s, _p, _a, _n, _s);
	s2h_printLF(ui);
	// Span history from char arrays — entries [0..N-2] opaque, [N-1] fades
	for (int i = 0; i < 8; i++) {
		if (otel_hist_chars[i * 20] == 0) break;
		float alpha = (i < 7) ? 1.0 : clamp(1.0 - otel_fade_age / 3.0, 0.0, 1.0);
		ui.textColor = float4(0.4 + float(i) * 0.02, 0.85 - float(i) * 0.04, 0.6, alpha);
		for (int j = 0; j < 20; j++) {
			int c = otel_hist_chars[i * 20 + j];
			if (c == 0) break;
			s2h_printCharacter(ui, uint(c));
		}
		int cnt = otel_hist_counts[i];
		if (cnt > 1) {
			s2h_printTxt(ui, _SPACE, _x);
			s2h_printInt(ui, cnt);
		}
		s2h_printLF(ui);
	}

	float3 sky_col = ctx.dstColor.rgb;
	COLOR = float3(sky_col * (1.0 - ui.dstColor.a) + ui.dstColor.rgb);
}
