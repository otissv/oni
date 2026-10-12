#version 460

// LCD text only — dual-source outs for ONE / ONE_MINUS_SRC1_* blend.
// Gray AA stays on ui.frag + the UI pipeline (no approximate LCD there).

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec4 v_border_color;
layout(location = 2) in vec2 v_uv;
layout(location = 3) in vec2 v_local_uv;
layout(location = 4) in vec2 v_rect_size;
layout(location = 5) in vec4 v_radii;
layout(location = 6) in vec2 v_params;
layout(location = 7) in vec4 v_border;

layout(set = 2, binding = 0) uniform sampler2D tex;

// Display subpixel order: bgr > 0.5 swaps FreeType RGB coverage to BGR.
layout(set = 3, binding = 0) uniform LcdUBO {
	float bgr;
};

layout(location = 0, index = 0) out vec4 out0;
layout(location = 0, index = 1) out vec4 out1;

// Skia-style per-channel fake-gamma (same exponents as ui.frag gray text).
vec3 text_coverage_rgb(vec3 coverage, vec3 tint_rgb) {
	float lum = dot(tint_rgb, vec3(0.2126, 0.7152, 0.0722));
	float exponent = mix(1.45, 0.70, clamp(lum, 0.0, 1.0));
	return pow(max(coverage, vec3(0.0)), vec3(exponent));
}

void main() {
	vec3 tint = v_color.rgb;
	vec3 sample_rgb = texture(tex, v_uv).rgb;
	if (bgr > 0.5) {
		sample_rgb = sample_rgb.bgr;
	}
	vec3 cov = text_coverage_rgb(sample_rgb, tint);
	out0 = vec4(tint * cov, 1.0);
	out1 = vec4(cov, 1.0);
}
