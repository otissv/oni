package tengu

import "core:math"

clamp01 :: proc(v: f32) -> f32 {
	if !is_finite_f32(v) do return 0
	return clamp(v, 0, 1)
}

f32_zero :: proc() -> f32 {
	return 0
}

vec2_zero :: proc() -> Vec2 {
	return {}
}

vec3_zero :: proc() -> Vec3 {
	return {}
}

vec4_zero :: proc() -> Vec4 {
	return {}
}

rgba_zero :: proc() -> RGBA {
	return {}
}

rect_zero :: proc() -> Rect {
	return {}
}

add_f32 :: proc(a, b: f32) -> f32 {
	return a + b
}

sub_f32 :: proc(a, b: f32) -> f32 {
	return a - b
}

scale_f32 :: proc(v: f32, s: f32) -> f32 {
	return v * s
}

mix_f32 :: proc(a, b: f32, t: f32) -> f32 {
	return lerp(a, b, t)
}

distance_f32 :: proc(a, b: f32) -> f32 {
	return math.abs(b - a)
}

add_vec2 :: proc(a, b: Vec2) -> Vec2 {
	return {a.x + b.x, a.y + b.y}
}

sub_vec2 :: proc(a, b: Vec2) -> Vec2 {
	return {a.x - b.x, a.y - b.y}
}

scale_vec2 :: proc(v: Vec2, s: f32) -> Vec2 {
	return {v.x * s, v.y * s}
}

mix_vec2 :: proc(a, b: Vec2, t: f32) -> Vec2 {
	return {
		lerp(a.x, b.x, t),
		lerp(a.y, b.y, t),
	}
}

distance_vec2 :: proc(a, b: Vec2) -> f32 {
	dx := b.x - a.x
	dy := b.y - a.y
	return math.sqrt(dx * dx + dy * dy)
}

add_vec3 :: proc(a, b: Vec3) -> Vec3 {
	return {a.x + b.x, a.y + b.y, a.z + b.z}
}

sub_vec3 :: proc(a, b: Vec3) -> Vec3 {
	return {a.x - b.x, a.y - b.y, a.z - b.z}
}

scale_vec3 :: proc(v: Vec3, s: f32) -> Vec3 {
	return {v.x * s, v.y * s, v.z * s}
}

mix_vec3 :: proc(a, b: Vec3, t: f32) -> Vec3 {
	return {
		lerp(a.x, b.x, t),
		lerp(a.y, b.y, t),
		lerp(a.z, b.z, t),
	}
}

distance_vec3 :: proc(a, b: Vec3) -> f32 {
	dx := b.x - a.x
	dy := b.y - a.y
	dz := b.z - a.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
}

add_vec4 :: proc(a, b: Vec4) -> Vec4 {
	return {a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w}
}

sub_vec4 :: proc(a, b: Vec4) -> Vec4 {
	return {a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w}
}

scale_vec4 :: proc(v: Vec4, s: f32) -> Vec4 {
	return {v.x * s, v.y * s, v.z * s, v.w * s}
}

mix_vec4 :: proc(a, b: Vec4, t: f32) -> Vec4 {
	return {
		lerp(a.x, b.x, t),
		lerp(a.y, b.y, t),
		lerp(a.z, b.z, t),
		lerp(a.w, b.w, t),
	}
}

distance_vec4 :: proc(a, b: Vec4) -> f32 {
	dx := b.x - a.x
	dy := b.y - a.y
	dz := b.z - a.z
	dw := b.w - a.w
	return math.sqrt(dx * dx + dy * dy + dz * dz + dw * dw)
}

premultiply_rgba :: proc(c: RGBA) -> RGBA {
	alpha := clamp01(c.a)
	return {
		clamp01(c.r) * alpha,
		clamp01(c.g) * alpha,
		clamp01(c.b) * alpha,
		alpha,
	}
}

unpremultiply_rgba :: proc(c: RGBA) -> RGBA {
	alpha := clamp01(c.a)
	if alpha <= 0 {
		return {}
	}

	return {
		clamp01(c.r / alpha),
		clamp01(c.g / alpha),
		clamp01(c.b / alpha),
		alpha,
	}
}

add_rgba :: proc(a, b: RGBA) -> RGBA {
	return {
		a.r + b.r,
		a.g + b.g,
		a.b + b.b,
		a.a + b.a,
	}
}

sub_rgba :: proc(a, b: RGBA) -> RGBA {
	return {
		a.r - b.r,
		a.g - b.g,
		a.b - b.b,
		a.a - b.a,
	}
}

scale_rgba :: proc(v: RGBA, s: f32) -> RGBA {
	return {
		v.r * s,
		v.g * s,
		v.b * s,
		v.a * s,
	}
}

mix_rgba :: proc(a, b: RGBA, t: f32) -> RGBA {
	return mix_rgba_with_policy(a, b, t, .PREMULTIPLIED_ALPHA)
}

distance_rgba :: proc(a, b: RGBA) -> f32 {
	dr := b.r - a.r
	dg := b.g - a.g
	db := b.b - a.b
	da := b.a - a.a
	return math.sqrt(dr * dr + dg * dg + db * db + da * da)
}

add_rect :: proc(a, b: Rect) -> Rect {
	return {a.x + b.x, a.y + b.y, a.w + b.w, a.h + b.h}
}

sub_rect :: proc(a, b: Rect) -> Rect {
	return {a.x - b.x, a.y - b.y, a.w - b.w, a.h - b.h}
}

scale_rect :: proc(v: Rect, s: f32) -> Rect {
	return {v.x * s, v.y * s, v.w * s, v.h * s}
}

mix_rect :: proc(a, b: Rect, t: f32) -> Rect {
	return {
		lerp(a.x, b.x, t),
		lerp(a.y, b.y, t),
		lerp(a.w, b.w, t),
		lerp(a.h, b.h, t),
	}
}

distance_rect :: proc(a, b: Rect) -> f32 {
	dx := b.x - a.x
	dy := b.y - a.y
	dw := b.w - a.w
	dh := b.h - a.h
	return math.sqrt(dx * dx + dy * dy + dw * dw + dh * dh)
}

F32_Animatable :: proc() -> Animatable(f32) {
	return {
		zero = f32_zero,
		add = add_f32,
		sub = sub_f32,
		scale = scale_f32,
		mix = mix_f32,
		distance = distance_f32,
		velocity_support = .VALUE_TYPE,
	}
}

Vec2_Animatable :: proc() -> Animatable(Vec2) {
	return {
		zero = vec2_zero,
		add = add_vec2,
		sub = sub_vec2,
		scale = scale_vec2,
		mix = mix_vec2,
		distance = distance_vec2,
		velocity_support = .VALUE_TYPE,
	}
}

Vec3_Animatable :: proc() -> Animatable(Vec3) {
	return {
		zero = vec3_zero,
		add = add_vec3,
		sub = sub_vec3,
		scale = scale_vec3,
		mix = mix_vec3,
		distance = distance_vec3,
		velocity_support = .VALUE_TYPE,
	}
}

Vec4_Animatable :: proc() -> Animatable(Vec4) {
	return {
		zero = vec4_zero,
		add = add_vec4,
		sub = sub_vec4,
		scale = scale_vec4,
		mix = mix_vec4,
		distance = distance_vec4,
		velocity_support = .VALUE_TYPE,
	}
}

RGBA_Animatable :: proc() -> Animatable(RGBA) {
	return {
		zero = rgba_zero,
		add = add_rgba,
		sub = sub_rgba,
		scale = scale_rgba,
		mix = mix_rgba,
		distance = distance_rgba,
		velocity_support = .VALUE_TYPE,
	}
}

Rect_Animatable :: proc() -> Animatable(Rect) {
	return {
		zero = rect_zero,
		add = add_rect,
		sub = sub_rect,
		scale = scale_rect,
		mix = mix_rect,
		distance = distance_rect,
		velocity_support = .VALUE_TYPE,
	}
}

animatable_of :: proc {
	animatable_of_f32,
	animatable_of_vec2,
	animatable_of_vec3,
	animatable_of_vec4,
	animatable_of_rgba,
	animatable_of_rect,
}

animatable_of_f32 :: proc(_: f32) -> Animatable(f32) {
	return F32_Animatable()
}

animatable_of_vec2 :: proc(_: Vec2) -> Animatable(Vec2) {
	return Vec2_Animatable()
}

animatable_of_vec3 :: proc(_: Vec3) -> Animatable(Vec3) {
	return Vec3_Animatable()
}

animatable_of_vec4 :: proc(_: Vec4) -> Animatable(Vec4) {
	return Vec4_Animatable()
}

animatable_of_rgba :: proc(_: RGBA) -> Animatable(RGBA) {
	return RGBA_Animatable()
}

animatable_of_rect :: proc(_: Rect) -> Animatable(Rect) {
	return Rect_Animatable()
}

mix :: proc {
	mix_f32,
	mix_vec2,
	mix_vec3,
	mix_vec4,
	mix_rgba,
	mix_rect,
}

distance :: proc {
	distance_f32,
	distance_vec2,
	distance_vec3,
	distance_vec4,
	distance_rgba,
	distance_rect,
}

approx_eq :: proc {
	approx_eq_f32,
	approx_eq_vec2,
	approx_eq_vec3,
	approx_eq_vec4,
	approx_eq_rgba,
	approx_eq_rect,
}

approx_eq_f32 :: proc(a, b: f32, epsilon: f32 = DEFAULT_DISTANCE_EPSILON) -> bool {
	return distance_f32(a, b) <= epsilon
}

approx_eq_vec2 :: proc(a, b: Vec2, epsilon: f32 = DEFAULT_DISTANCE_EPSILON) -> bool {
	return distance_vec2(a, b) <= epsilon
}

approx_eq_vec3 :: proc(a, b: Vec3, epsilon: f32 = DEFAULT_DISTANCE_EPSILON) -> bool {
	return distance_vec3(a, b) <= epsilon
}

approx_eq_vec4 :: proc(a, b: Vec4, epsilon: f32 = DEFAULT_DISTANCE_EPSILON) -> bool {
	return distance_vec4(a, b) <= epsilon
}

approx_eq_rgba :: proc(a, b: RGBA, epsilon: f32 = DEFAULT_DISTANCE_EPSILON) -> bool {
	return distance_rgba(a, b) <= epsilon
}

approx_eq_rect :: proc(a, b: Rect, epsilon: f32 = DEFAULT_DISTANCE_EPSILON) -> bool {
	return distance_rect(a, b) <= epsilon
}
