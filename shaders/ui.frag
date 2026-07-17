#version 460

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec4 v_border_color;
layout(location = 2) in vec2 v_uv;
layout(location = 3) in vec2 v_local_uv;
layout(location = 4) in vec2 v_rect_size;
layout(location = 5) in vec4 v_radii;
layout(location = 6) in vec2 v_params;
layout(location = 7) in vec4 v_border;

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

vec4 rounded_shape(vec4 tint, vec2 local_uv, vec2 size, vec4 outer_r, vec4 border_widths) {
    vec2 p = local_uv * size;
    vec2 half_size = size * 0.5;
    vec2 outer_local = p - half_size;

    float bt = border_widths.x;
    float bb = border_widths.y;
    float bl = border_widths.z;
    float br = border_widths.w;
    bool has_border = (bt + bb + bl + br) > 0.001;

    float outer_d = sd_rounded_box_corners(outer_local, half_size, outer_r);
    float outer_a = 1.0 - smoothstep(-0.5, 0.5, outer_d);
    if (outer_a <= 0.0) {
        discard;
    }

    if (!has_border) {
        return rounded_fill(tint, outer_d);
    }

    // Inset the fill box by border width; keep outer corner radii so inner border
    // edges stay parallel/concentric with the outer curve (r_inner = r_outer, not r - border).
    vec2 inner_half = max(half_size - 0.5 * vec2(bl + br, bt + bb), vec2(0.0));
    vec2 inner_local = outer_local - 0.5 * vec2(bl - br, bt - bb);

    float inner_d = sd_rounded_box_corners(inner_local, inner_half, outer_r);
    float inner_a = 1.0 - smoothstep(-0.5, 0.5, inner_d);
    vec4 fill = vec4(tint.rgb, tint.a * inner_a);
    if (fill.a > 0.0) {
        return fill;
    }

    float border_a = outer_a * (1.0 - inner_a);
    return vec4(v_border_color.rgb, v_border_color.a * border_a);
}

void main() {
    vec4 tint = v_color;
    float mode = v_params.y;

    if (mode >= 2.5) {
        vec2 local_px = v_local_uv * v_rect_size;
        if (v_params.x > 0.5) {
            float min_x = v_border.z;
            float min_y = v_border.x;
            float max_x = v_rect_size.x - v_border.w;
            float max_y = v_rect_size.y - v_border.y;
            if (local_px.x < min_x || local_px.y < min_y || local_px.x > max_x || local_px.y > max_y) {
                discard;
            }
        }
        vec4 tex_color = texture(tex, v_uv) * tint;
        out_color = rounded_shape(tex_color, v_local_uv, v_rect_size, v_radii, vec4(0.0));
        return;
    }

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

    out_color = rounded_shape(tint, v_uv, v_rect_size, v_radii, v_border);
}
