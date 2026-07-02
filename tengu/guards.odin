package tengu

import "core:math"

/*
Numeric guards for production stepping. Invalid frame times never advance state;
finite outputs are preserved when configs are valid.
*/

sanitize_dt :: proc(dt: f32) -> f32 {
	if math.is_nan(dt) || dt <= 0 do return 0
	return dt
}

is_finite_f32 :: proc(v: f32) -> bool {
	return !math.is_nan(v) && !math.is_inf(v)
}

sanitize_finite_f32 :: proc(v: f32, fallback: f32 = 0) -> f32 {
	if is_finite_f32(v) do return v
	return fallback
}

is_finite_vec2 :: proc(v: Vec2) -> bool {
	return is_finite_f32(v.x) && is_finite_f32(v.y)
}

is_finite_vec3 :: proc(v: Vec3) -> bool {
	return is_finite_f32(v.x) && is_finite_f32(v.y) && is_finite_f32(v.z)
}

is_finite_vec4 :: proc(v: Vec4) -> bool {
	return is_finite_f32(v.x) && is_finite_f32(v.y) && is_finite_f32(v.z) && is_finite_f32(v.w)
}

is_finite_rgba :: proc(v: RGBA) -> bool {
	return is_finite_f32(v.r) && is_finite_f32(v.g) && is_finite_f32(v.b) && is_finite_f32(v.a)
}

is_finite_rect :: proc(v: Rect) -> bool {
	return is_finite_f32(v.x) && is_finite_f32(v.y) && is_finite_f32(v.w) && is_finite_f32(v.h)
}

is_finite :: proc {
	is_finite_f32,
	is_finite_vec2,
	is_finite_vec3,
	is_finite_vec4,
	is_finite_rgba,
	is_finite_rect,
}

step_value_is_finite :: proc(result: Step_Result($T)) -> bool {
	if !is_finite(result.value) do return false
	if result.has_velocity && !is_finite(result.velocity) do return false
	return true
}
