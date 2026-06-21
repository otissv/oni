#version 460

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec4 v_border_color;
layout(location = 2) in vec2 v_uv;
layout(location = 3) in vec2 v_rect_size;
layout(location = 4) in vec4 v_radii;
layout(location = 5) in vec2 v_params;
layout(location = 6) in vec4 v_border;

layout(set = 2, binding = 0) uniform sampler2D tex;

layout(location = 0) out vec4 out_color;

// v_radii: x=tl, y=tr, z=br, w=bl — screen space, y-down.
float sd_rounded_box_corners(vec2 p, vec2 half_size, vec4 corner_radii) {
    float r;
    if (p.x < 0.0) {
        r = (p.y < 0.0) ? corner_radii.x : corner_radii.w;
    } else {
        r = (p.y < 0.0) ? corner_radii.y : corner_radii.z;
    }
    r = min(r, min(half_size.x, half_size.y));
    vec2 q = abs(p) - half_size + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

vec4 rounded_fill(vec4 tint, float dist) {
    float alpha = 1.0 - smoothstep(-0.5, 0.5, dist);
    return vec4(tint.rgb, tint.a * alpha);
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

    vec2 size = v_rect_size;
    vec2 p = v_uv * size;
    vec2 half_size = size * 0.5;
    vec2 outer_local = p - half_size;

    float bt = v_border.x;
    float bb = v_border.y;
    float bl = v_border.z;
    float br = v_border.w;
    bool has_border = (bt + bb + bl + br) > 0.001;

    vec4 outer_r = v_radii;
    float outer_d = sd_rounded_box_corners(outer_local, half_size, outer_r);
    float outer_a = 1.0 - smoothstep(-0.5, 0.5, outer_d);
    if (outer_a <= 0.0) {
        discard;
    }

    if (!has_border) {
        out_color = rounded_fill(tint, outer_d);
        return;
    }

    vec2 fill_size = size - vec2(bl + br, bt + bb);
    vec2 fill_origin = vec2(bl, bt);
    vec2 inner_half = fill_size * 0.5;
    vec2 inner_local = p - fill_origin - inner_half;

    vec4 inner_r = vec4(
        max(0.0, outer_r.x - max(bt, bl)),
        max(0.0, outer_r.y - max(bt, br)),
        max(0.0, outer_r.z - max(bb, br)),
        max(0.0, outer_r.w - max(bb, bl))
    );

    float inner_d = sd_rounded_box_corners(inner_local, inner_half, inner_r);
    float inner_a = 1.0 - smoothstep(-0.5, 0.5, inner_d);
    vec4 fill = vec4(tint.rgb, tint.a * inner_a);
    if (fill.a > 0.0) {
        out_color = fill;
        return;
    }

    float border_a = outer_a * (1.0 - inner_a);
    out_color = vec4(v_border_color.rgb, v_border_color.a * border_a);
}
