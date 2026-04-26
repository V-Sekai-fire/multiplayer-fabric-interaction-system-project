#[compute]
#version 450

// S2H CompositorEffect compute shader.
// Dispatched at POST_TRANSPARENT so it has access to:
//   - The fully composited color buffer (opaque + sky + transparent)
//   - The depth buffer for 3D-aware occlusion of debug primitives
//
// Thread group matches Godot's standard 8×8 tile size.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;

layout(set = 0, binding = 1) uniform sampler2D depth_sampler;

// Per-frame data pushed by S2HCompositorEffect.gd
layout(push_constant, std430) uniform Params {
    ivec2 screen_size;
    float time;
    float _pad;
    // Extend with uniform ULID, camera pos, etc.
} params;

#include "res://addons/s2h/include/s2h_glsl.gdshaderinc"
#include "res://addons/s2h/include/s2h.gdshaderinc"

void main() {
    ivec2 px_i = ivec2(gl_GlobalInvocationID.xy);
    if (px_i.x >= params.screen_size.x || px_i.y >= params.screen_size.y) return;

    vec4 col = imageLoad(color_image, px_i);

    // S2H 2D overlay — FRAGCOORD equivalent is px_i + 0.5
    ContextGather ui;
    s2h_init(ui, float2(px_i) + 0.5);
    s2h_setScale(ui, 2.0);

    // Example: draw frame time / depth at screen center
    float depth = texelFetch(depth_sampler, px_i, 0).r;

    s2h_setCursor(ui, float2(8.0, 8.0));
    s2h_printTxt(ui, _t, _i, _m, _e, _COLON, _SPACE);
    s2h_printFloat(ui, params.time);
    s2h_printLF(ui);
    s2h_printTxt(ui, _d, _e, _p, _t, _h, _COLON, _SPACE);
    s2h_printFloat(ui, depth);

    // Composite: S2H text over scene colour, depth-aware occlusion left to caller
    col.rgb = col.rgb * (1.0 - ui.dstColor.a) + ui.dstColor.rgb;
    imageStore(color_image, px_i, col);
}
