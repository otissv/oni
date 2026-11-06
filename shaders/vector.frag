#version 460
layout(location = 0) in vec2 v_uv;
layout(location = 1) flat in vec4 v_colour;
layout(location = 2) in vec2 v_pos;
layout(location = 3) flat in vec4 v_paint;
layout(location = 4) flat in vec4 v_grad0;
layout(location = 5) flat in vec4 v_combined_linear;
layout(location = 6) flat in vec4 v_combined_shift_focal;
layout(set = 2, binding = 0) uniform sampler2D content_texture;
layout(set = 2, binding = 1) uniform sampler2D mask_texture;
layout(set = 2, binding = 2) uniform sampler2D ramp_texture;
layout(set = 3, binding = 0) uniform Paint { vec4 mode; vec4 uv_scale; vec4 uv_offset; };
layout(location = 0) out vec4 result;

// Matches Gradient_Spread: Pad=0, Reflect=1, Repeat=2.
float spread_parameter(float t, float spread) {
    if (spread < 0.5) {
        return clamp(t, 0.0, 1.0);
    }
    if (spread < 1.5) {
        float cycle = floor(t);
        float frac = t - cycle;
        if (mod(cycle, 2.0) >= 1.0) {
            return 1.0 - frac;
        }
        return frac;
    }
    return t - floor(t);
}

vec2 apply_combined(vec2 p) {
    return mat2(v_combined_linear.x, v_combined_linear.y, v_combined_linear.z, v_combined_linear.w) * p
        + v_combined_shift_focal.xy;
}

vec4 sample_ramp(float t) {
    float row = v_paint.z;
    float height = max(textureSize(ramp_texture, 0).y, 1);
    float v = (row + 0.5) / height;
    vec4 colour = texture(ramp_texture, vec2(clamp(t, 0.0, 1.0), v));
    return vec4(colour.rgb * colour.a, colour.a) * v_colour.a;
}

vec4 paint_linear() {
    vec2 p = apply_combined(v_pos);
    vec2 p1 = v_grad0.xy;
    vec2 p2 = v_grad0.zw;
    float scale = max(max(abs(p.x), abs(p.y)), max(max(abs(p1.x), abs(p1.y)), max(abs(p2.x), abs(p2.y))));
    if (scale == 0.0) {
        return sample_ramp(1.0);
    }
    p /= scale;
    p1 /= scale;
    p2 /= scale;
    vec2 d = p2 - p1;
    float len_sq = dot(d, d);
    if (len_sq == 0.0) {
        return sample_ramp(1.0);
    }
    float t = 0.0;
    if (len_sq > 0.0) {
        t = dot(p - p1, d) / len_sq;
    }
    t = spread_parameter(t, v_paint.y);
    return sample_ramp(t);
}

vec4 paint_radial() {
    vec2 p = apply_combined(v_pos);
    vec2 center = v_grad0.xy;
    float radius = max(v_grad0.z, 0.0);
    float fr = max(v_grad0.w, 0.0);
    vec2 focal = v_combined_shift_focal.zw;
    float scale = max(max(max(abs(p.x), abs(p.y)), max(abs(center.x), abs(center.y))), max(max(abs(focal.x), abs(focal.y)), max(radius, fr)));
    if (scale == 0.0 || (radius == 0.0 && fr == 0.0)) {
        return sample_ramp(1.0);
    }
    p /= scale;
    center /= scale;
    focal /= scale;
    radius /= scale;
    fr /= scale;
    vec2 d = p - focal;
    vec2 c = center - focal;
    float dr = radius - fr;
    float a = dot(c, c) - dr * dr;
    float b = -2.0 * (dot(d, c) + fr * dr);
    float cc = dot(d, d) - fr * fr;
    float t = 0.0;
    if (a == 0.0) {
        if (b > 0.0 && radius >= fr) {
            t = 1.0;
        } else if (b != 0.0) {
            t = -cc / b;
        } else if (cc > 0.0) {
            t = 1.0;
        }
    } else {
        float disc = max(b * b - 4.0 * a * cc, 0.0);
        float sqrt_disc = sqrt(disc);
        float q = -0.5 * (b + (b < 0.0 ? -sqrt_disc : sqrt_disc));
        t = q == 0.0 ? -b / (2.0 * a) : max(q / a, cc / q);
    }
    t = spread_parameter(t, v_paint.y);
    return sample_ramp(t);
}

float srgb_to_linear(float c) {
    if (c <= 0.04045) {
        return c / 12.92;
    }
    return pow((c + 0.055) / 1.055, 2.4);
}

// CSS Masking luminance over a premultiplied mask target: unpremultiply, convert
// to linearized sRGB, then multiply by alpha once.
float mask_luminance(vec4 mask_value) {
    float a = mask_value.a;
    vec3 rgb = a > 0.0 ? mask_value.rgb / a : vec3(0.0);
    float r = srgb_to_linear(rgb.r);
    float g = srgb_to_linear(rgb.g);
    float b = srgb_to_linear(rgb.b);
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) * a;
}

void main() {
    if (mode.x >= 0.5) {
        vec4 content = texture(content_texture, v_uv * uv_scale.xy + uv_offset.xy);
        vec4 mask_value = texture(mask_texture, v_uv * uv_scale.zw + uv_offset.zw);
        float coverage = 1.0;
        if (mode.y > 1.5) {
            coverage = mask_luminance(mask_value);
        } else if (mode.y > 0.5) {
            coverage = mask_value.a;
        }
        result = content * (coverage * v_colour.a);
        return;
    }
    if (v_paint.x < 0.5) {
        result = vec4(v_colour.rgb * v_colour.a, v_colour.a);
        return;
    }
    if (v_paint.x < 1.5) {
        result = paint_linear();
        return;
    }
    result = paint_radial();
}
