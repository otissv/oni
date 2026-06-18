#version 460

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec2 v_uv;
layout(location = 2) in vec2 v_rect_size;
layout(location = 3) in vec2 v_params;

layout(set = 2, binding = 0) uniform sampler2D tex;

layout(location = 0) out vec4 out_color;

float sd_rounded_box(vec2 p, vec2 half_size, float radius) {
    vec2 q = abs(p) - half_size + radius;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

void main() {
    vec4 tint = v_color;
    float mode = v_params.y;

    if (mode >= 1.5) {
        float edge = min(v_uv.y, 1.0 - v_uv.y);
        float alpha = smoothstep(0.0, 0.05, edge);
        out_color = vec4(tint.rgb, tint.a * alpha);
        return;
    }

    if (mode >= 0.5) {
        out_color = texture(tex, v_uv) * tint;
        return;
    }

    vec2 half_size = v_rect_size * 0.5;
    float radius = min(v_params.x, min(half_size.x, half_size.y));
    vec2 p = (v_uv - 0.5) * v_rect_size;
    float dist = sd_rounded_box(p, half_size, radius);
    float alpha = 1.0 - smoothstep(-0.5, 0.5, dist);
    out_color = vec4(tint.rgb, tint.a * alpha);
}
