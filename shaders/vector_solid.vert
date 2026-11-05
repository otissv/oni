#version 460
layout(location = 0) in vec2 position;
layout(location = 2) in vec4 colour;
layout(location = 3) in vec2 origin;
layout(location = 4) in vec4 morph_linear;
layout(location = 5) in vec2 morph_shift;
layout(set = 1, binding = 0) uniform View { vec4 bounds; };
layout(location = 0) out vec2 v_uv;
layout(location = 1) flat out vec4 v_colour;
layout(location = 2) out vec2 v_pos;
layout(location = 3) flat out vec4 v_paint;
layout(location = 4) flat out vec4 v_grad0;
layout(location = 5) flat out vec4 v_combined_linear;
layout(location = 6) flat out vec4 v_combined_shift_focal;
void main() {
    vec2 local = mat2(morph_linear.x, morph_linear.y, morph_linear.z, morph_linear.w) * position + morph_shift;
    vec2 p = (local + origin - bounds.xy) / bounds.zw;
    gl_Position = vec4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
    v_uv = vec2(0.0);
    v_colour = colour;
    v_pos = position;
    v_paint = vec4(0.0);
    v_grad0 = vec4(0.0);
    v_combined_linear = vec4(0.0);
    v_combined_shift_focal = vec4(0.0);
}
