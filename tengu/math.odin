package tengu

import "core:math"

Color_Interpolation_Policy :: enum {
	PREMULTIPLIED_ALPHA,
}

Bezier :: struct {
	x1, y1, x2, y2: f32,
}

EASE :: Bezier{0.25, 0.1, 0.25, 1.0}
EASE_IN :: Bezier{0.42, 0.0, 1.0, 1.0}
EASE_OUT :: Bezier{0.0, 0.0, 0.58, 1.0}
EASE_IN_OUT :: Bezier{0.42, 0.0, 0.58, 1.0}

Ease :: enum {
	LINEAR,
	IN_SINE,
	OUT_SINE,
	IN_OUT_SINE,
	IN_QUAD,
	OUT_QUAD,
	IN_OUT_QUAD,
	IN_CUBIC,
	OUT_CUBIC,
	IN_OUT_CUBIC,
	IN_QUART,
	OUT_QUART,
	IN_OUT_QUART,
	IN_QUINT,
	OUT_QUINT,
	IN_OUT_QUINT,
	IN_EXPO,
	OUT_EXPO,
	IN_OUT_EXPO,
	IN_CIRC,
	OUT_CIRC,
	IN_OUT_CIRC,
	IN_BACK,
	OUT_BACK,
	IN_OUT_BACK,
	IN_BOUNCE,
	OUT_BOUNCE,
	IN_OUT_BOUNCE,
	IN_ELASTIC,
	OUT_ELASTIC,
	IN_OUT_ELASTIC,
	EASE,
	EASE_IN,
	EASE_OUT,
	EASE_IN_OUT,
}

Mix_RGBA_With_Policy_Params :: struct {
	a, b:   RGBA,
	t:      f32,
	policy: Color_Interpolation_Policy,
}

Bezier_Sample_1D_Params :: struct {
	p1, p2, t: f32,
}

Bezier_Slope_1D_Params :: struct {
	p1, p2, t: f32,
}

clamp :: proc(p: Clamp_Params) -> f32 {
	return math.clamp(p.v, p.lo, p.hi)
}

wrap :: proc(v, upper: f32) -> f32 {
	if upper == 0 do return 0
	result := math.mod(v, upper)
	if result < 0 do result += upper
	return result
}

wrap_range :: proc(p: Wrap_Range_Params) -> f32 {
	span := p.hi - p.lo
	if span == 0 do return p.lo
	return p.lo + wrap(p.v - p.lo, span)
}

inverse_lerp :: proc(p: Inverse_Lerp_Params) -> f32 {
	denom := p.b - p.a
	if denom == 0 do return 0
	return (p.value - p.a) / denom
}

progress :: proc(p: Progress_Params) -> f32 {
	return clamp({v = inverse_lerp({a = p.a, b = p.b, value = p.value}), lo = 0, hi = 1})
}

lerp :: proc(p: Lerp_Params) -> f32 {
	return p.a + (p.b - p.a) * clamp01(p.t)
}

shortest_angle_delta_deg :: proc(a, b: f32) -> f32 {
	delta := wrap_range({v = b - a, lo = -180, hi = 180})
	if delta == -180 && b - a > 0 {
		return 180
	}
	return delta
}

shortest_angle_delta_rad :: proc(a, b: f32) -> f32 {
	pi := f32(math.PI)
	delta := wrap_range({v = b - a, lo = -pi, hi = pi})
	if delta == -pi && b - a > 0 {
		return pi
	}
	return delta
}

mix_angle_deg :: proc(p: Mix_Angle_Params) -> f32 {
	return p.a + shortest_angle_delta_deg(p.a, p.b) * clamp01(p.t)
}

mix_angle_rad :: proc(p: Mix_Angle_Params) -> f32 {
	return p.a + shortest_angle_delta_rad(p.a, p.b) * clamp01(p.t)
}

mix_rgba_with_policy :: proc(p: Mix_RGBA_With_Policy_Params) -> RGBA {
	alpha := clamp01(p.t)

	#partial switch p.policy {
	case .PREMULTIPLIED_ALPHA:
		a_premul := premultiply_rgba(p.a)
		b_premul := premultiply_rgba(p.b)
		mixed := RGBA {
			r = lerp({a = a_premul.r, b = b_premul.r, t = alpha}),
			g = lerp({a = a_premul.g, b = b_premul.g, t = alpha}),
			b = lerp({a = a_premul.b, b = b_premul.b, t = alpha}),
			a = lerp({a = a_premul.a, b = b_premul.a, t = alpha}),
		}
		return unpremultiply_rgba(mixed)
	}

	unreachable()
}

bezier_sample_1d :: proc(p: Bezier_Sample_1D_Params) -> f32 {
	u := 1 - p.t
	return 3 * u * u * p.t * p.p1 + 3 * u * p.t * p.t * p.p2 + p.t * p.t * p.t
}

bezier_slope_1d :: proc(p: Bezier_Slope_1D_Params) -> f32 {
	u := 1 - p.t
	return 3 * u * u * p.p1 + 6 * u * p.t * (p.p2 - p.p1) + 3 * p.t * p.t * (1 - p.p2)
}

bezier_solve_t_for_x :: proc(curve: Bezier, x: f32) -> f32 {
	target := clamp01(x)
	t := target

	for _ in 0 ..< 6 {
		value := bezier_sample_1d({p1 = curve.x1, p2 = curve.x2, t = t}) - target
		slope := bezier_slope_1d({p1 = curve.x1, p2 = curve.x2, t = t})
		if math.abs(slope) < 1e-6 do break
		next_t := t - value / slope
		if next_t < 0 || next_t > 1 do break
		t = next_t
	}

	lo := f32(0)
	hi := f32(1)
	for _ in 0 ..< 16 {
		value := bezier_sample_1d({p1 = curve.x1, p2 = curve.x2, t = t})
		if math.abs(value - target) <= 1e-5 {
			return t
		}
		if value < target {
			lo = t
		} else {
			hi = t
		}
		t = (lo + hi) * 0.5
	}

	return t
}

bezier_ease :: proc(curve: Bezier, x: f32) -> f32 {
	if x <= 0 do return 0
	if x >= 1 do return 1
	t := bezier_solve_t_for_x(curve, x)
	return bezier_sample_1d({p1 = curve.y1, p2 = curve.y2, t = t})
}

ease_out_bounce :: proc(t: f32) -> f32 {
	x := clamp01(t)

	n1 :: f32(7.5625)
	d1 :: f32(2.75)

	if x < 1 / d1 {
		return n1 * x * x
	}
	if x < 2 / d1 {
		x -= 1.5 / d1
		return n1 * x * x + 0.75
	}
	if x < 2.5 / d1 {
		x -= 2.25 / d1
		return n1 * x * x + 0.9375
	}

	x -= 2.625 / d1
	return n1 * x * x + 0.984375
}

ease :: proc(kind: Ease, t: f32) -> f32 {
	x := clamp01(t)

	#partial switch kind {
	case .LINEAR:
		return x
	case .IN_SINE:
		return 1 - math.cos((x * f32(math.PI)) * 0.5)
	case .OUT_SINE:
		return math.sin((x * f32(math.PI)) * 0.5)
	case .IN_OUT_SINE:
		return -(math.cos(f32(math.PI) * x) - 1) * 0.5
	case .IN_QUAD:
		return x * x
	case .OUT_QUAD:
		return 1 - (1 - x) * (1 - x)
	case .IN_OUT_QUAD:
		if x < 0.5 {
			return 2 * x * x
		}
		return 1 - math.pow(-2 * x + 2, 2) * 0.5
	case .IN_CUBIC:
		return x * x * x
	case .OUT_CUBIC:
		return 1 - math.pow(1 - x, 3)
	case .IN_OUT_CUBIC:
		if x < 0.5 {
			return 4 * x * x * x
		}
		return 1 - math.pow(-2 * x + 2, 3) * 0.5
	case .IN_QUART:
		return x * x * x * x
	case .OUT_QUART:
		return 1 - math.pow(1 - x, 4)
	case .IN_OUT_QUART:
		if x < 0.5 {
			return 8 * x * x * x * x
		}
		return 1 - math.pow(-2 * x + 2, 4) * 0.5
	case .IN_QUINT:
		return x * x * x * x * x
	case .OUT_QUINT:
		return 1 - math.pow(1 - x, 5)
	case .IN_OUT_QUINT:
		if x < 0.5 {
			return 16 * x * x * x * x * x
		}
		return 1 - math.pow(-2 * x + 2, 5) * 0.5
	case .IN_EXPO:
		if x == 0 do return 0
		return math.pow(2, 10 * x - 10)
	case .OUT_EXPO:
		if x == 1 do return 1
		return 1 - math.pow(2, -10 * x)
	case .IN_OUT_EXPO:
		if x == 0 do return 0
		if x == 1 do return 1
		if x < 0.5 {
			return math.pow(2, 20 * x - 10) * 0.5
		}
		return (2 - math.pow(2, -20 * x + 10)) * 0.5
	case .IN_CIRC:
		return 1 - math.sqrt(1 - x * x)
	case .OUT_CIRC:
		return math.sqrt(1 - math.pow(x - 1, 2))
	case .IN_OUT_CIRC:
		if x < 0.5 {
			return (1 - math.sqrt(1 - math.pow(2 * x, 2))) * 0.5
		}
		return (math.sqrt(1 - math.pow(-2 * x + 2, 2)) + 1) * 0.5
	case .IN_BACK:
		c1 :: f32(1.70158)
		c3 := c1 + 1
		return c3 * x * x * x - c1 * x * x
	case .OUT_BACK:
		c1 :: f32(1.70158)
		c3 := c1 + 1
		y := x - 1
		return 1 + c3 * y * y * y + c1 * y * y
	case .IN_OUT_BACK:
		c1 :: f32(1.70158)
		c2 := c1 * 1.525
		if x < 0.5 {
			return math.pow(2 * x, 2) * ((c2 + 1) * 2 * x - c2) * 0.5
		}
		y := 2 * x - 2
		return (math.pow(y, 2) * ((c2 + 1) * y + c2) + 2) * 0.5
	case .IN_BOUNCE:
		return 1 - ease_out_bounce(1 - x)
	case .OUT_BOUNCE:
		return ease_out_bounce(x)
	case .IN_OUT_BOUNCE:
		if x < 0.5 {
			return (1 - ease_out_bounce(1 - 2 * x)) * 0.5
		}
		return (1 + ease_out_bounce(2 * x - 1)) * 0.5
	case .IN_ELASTIC:
		if x == 0 do return 0
		if x == 1 do return 1
		c4 := (2 * f32(math.PI)) / 3
		return -math.pow(2, 10 * x - 10) * math.sin((x * 10 - 10.75) * c4)
	case .OUT_ELASTIC:
		if x == 0 do return 0
		if x == 1 do return 1
		c4 := (2 * f32(math.PI)) / 3
		return math.pow(2, -10 * x) * math.sin((x * 10 - 0.75) * c4) + 1
	case .IN_OUT_ELASTIC:
		if x == 0 do return 0
		if x == 1 do return 1
		c5 := (2 * f32(math.PI)) / 4.5
		if x < 0.5 {
			return -(math.pow(2, 20 * x - 10) * math.sin((20 * x - 11.125) * c5)) * 0.5
		}
		return math.pow(2, -20 * x + 10) * math.sin((20 * x - 11.125) * c5) * 0.5 + 1
	case .EASE:
		return bezier_ease(EASE, x)
	case .EASE_IN:
		return bezier_ease(EASE_IN, x)
	case .EASE_OUT:
		return bezier_ease(EASE_OUT, x)
	case .EASE_IN_OUT:
		return bezier_ease(EASE_IN_OUT, x)
	}

	unreachable()
}
