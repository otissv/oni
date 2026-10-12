#version 450

// Dual-source LCD-style outputs: out0 = tint * coverage, out1 = coverage.
layout(location = 0, index = 0) out vec4 out0;
layout(location = 0, index = 1) out vec4 out1;

void main() {
	vec3 tint = vec3(0.8, 0.2, 0.1);
	vec3 cov = vec3(0.5, 0.25, 0.75);
	out0 = vec4(tint * cov, 1.0);
	out1 = vec4(cov, 1.0);
}
