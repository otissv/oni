package oni_vector

import "core:math"
import "core:mem"
import col "libs:colors"

Color :: col.RGBA
Color_Interpolation :: col.Color_Interpolation

Paint_Kind :: enum u8 {
	None,
	Solid,
	Current_Color,
	Linear_Gradient,
	Radial_Gradient,
}

Gradient_Spread :: enum u8 {
	Pad,
	Reflect,
	Repeat,
}

Gradient_Units :: enum u8 {
	User_Space,
	Object_Bounding_Box,
}

Gradient_Stop :: struct {
	offset: f64,
	color:  Color,
}

Linear_Gradient :: struct {
	x1, y1, x2, y2:       f64,
	units:                Gradient_Units,
	spread:               Gradient_Spread,
	transform:            Affine,
	stops:                []Gradient_Stop,
	color_interpolation:  Color_Interpolation,
}

Radial_Gradient :: struct {
	cx, cy, r:            f64,
	fx, fy, fr:           f64,
	units:                Gradient_Units,
	spread:               Gradient_Spread,
	transform:            Affine,
	stops:                []Gradient_Stop,
	color_interpolation:  Color_Interpolation,
}

Paint :: struct {
	kind:   Paint_Kind,
	solid:  Color,
	linear: Linear_Gradient,
	radial: Radial_Gradient,
}

Solid_Paint :: proc(color: Color) -> Paint {
	return {kind = .Solid, solid = color}
}

None_Paint :: proc() -> Paint {
	return {kind = .None}
}

Current_Color_Paint :: proc() -> Paint {
	return {kind = .Current_Color}
}

Linear_Paint :: proc(gradient: Linear_Gradient) -> Paint {
	g := gradient
	if g.transform == {} {
		g.transform = IDENTITY
	}

	return {kind = .Linear_Gradient, linear = g}
}

Radial_Paint :: proc(gradient: Radial_Gradient) -> Paint {
	g := gradient
	if g.transform == {} {
		g.transform = IDENTITY
	}

	return {kind = .Radial_Gradient, radial = g}
}

/*
Validates paint geometry, stop offsets and colour-space fields.
Gradient paints require at least one finite stop. Empty stop lists are invalid.
*/
Validate_Paint :: proc(paint: Paint) -> Error {
	switch paint.kind {
	case .None, .Current_Color:
		return .None
	case .Solid:
		return .None
	case .Linear_Gradient:
		return validate_linear_gradient(paint.linear)
	case .Radial_Gradient:
		return validate_radial_gradient(paint.radial)
	}

	return .Invalid_Value
}

/*
Copies borrowed gradient stop slices into allocator-owned storage.
Caller must Destroy_Paint the result. Solid/none/currentColor need no free.
*/
Clone_Paint :: proc(paint: Paint, allocator := context.allocator) -> (Paint, Error) {
	if err := Validate_Paint(paint); err != .None {
		return {}, err
	}

	out := paint
	switch paint.kind {
	case .None, .Solid, .Current_Color:
		return out, .None
	case .Linear_Gradient:
		stops, err := clone_stops(paint.linear.stops, allocator)
		if err != .None {
			return {}, err
		}

		out.linear.stops = stops
		return out, .None
	case .Radial_Gradient:
		stops, err := clone_stops(paint.radial.stops, allocator)
		if err != .None {
			return {}, err
		}

		out.radial.stops = stops
		return out, .None
	}

	return {}, .Invalid_Value
}

Destroy_Paint :: proc(paint: ^Paint) {
	if paint == nil {
		return
	}

	switch paint.kind {
	case .None, .Solid, .Current_Color:
	case .Linear_Gradient:
		delete(paint.linear.stops)
		paint.linear.stops = nil
	case .Radial_Gradient:
		delete(paint.radial.stops)
		paint.radial.stops = nil
	}

	paint^ = {}
}

/*
Applies SVG spreadMode to a raw gradient parameter.
*/
Spread_Parameter :: proc(t: f64, spread: Gradient_Spread) -> f64 {
	if !finite(t) {
		return 0
	}

	switch spread {
	case .Pad:
		return clamp(t, 0, 1)
	case .Repeat:
		return t - math.floor(t)
	case .Reflect:
		cycle := math.floor(t)
		frac := t - cycle
		if i64(cycle) & 1 != 0 {
			return 1 - frac
		}

		return frac
	}

	return clamp(t, 0, 1)
}

/*
Samples sorted gradient stops at parameter t in 0..1 after spread.
*/
Sample_Stops :: proc(
	stops: []Gradient_Stop,
	t: f64,
	space: Color_Interpolation = .sRGB,
) -> Color {
	if len(stops) == 0 {
		return {0, 0, 0, 0}
	}

	if len(stops) == 1 || t <= stops[0].offset {
		return stops[0].color
	}

	last := stops[len(stops) - 1]
	if t >= last.offset {
		return last.color
	}

	for i in 1 ..< len(stops) {
		right := stops[i]
		left := stops[i - 1]
		if t > right.offset {
			continue
		}

		span := right.offset - left.offset
		if span <= 0 {
			return right.color
		}

		local := (t - left.offset) / span
		return col.rgba_lerp(left.color, right.color, f32(local), space)
	}

	return last.color
}

/*
Builds a 256-texel straight-alpha ramp for GPU sampling.
*/
Build_Stop_Ramp :: proc(
	stops: []Gradient_Stop,
	space: Color_Interpolation,
	ramp: []Color,
) {
	if len(ramp) == 0 {
		return
	}

	if len(stops) == 0 {
		for i in 0 ..< len(ramp) {
			ramp[i] = {0, 0, 0, 0}
		}

		return
	}

	denom := f64(max(len(ramp) - 1, 1))
	for i in 0 ..< len(ramp) {
		ramp[i] = Sample_Stops(stops, f64(i) / denom, space)
	}
}

/*
Maps a path-space point into gradient definition space.

objectBoundingBox normalizes by the path-local AABB first. gradientTransform maps
gradient space onto that target space, so sampling applies its inverse.
*/
Gradient_Point :: proc(
	point: Point,
	units: Gradient_Units,
	transform: Affine,
	bbox: Bounds,
) -> Point {
	p := point
	if units == .Object_Bounding_Box {
		if bbox.empty || bbox.max.x <= bbox.min.x || bbox.max.y <= bbox.min.y {
			p = {0, 0}
		} else {
			p = {
				(point.x - bbox.min.x) / (bbox.max.x - bbox.min.x),
				(point.y - bbox.min.y) / (bbox.max.y - bbox.min.y),
			}
		}
	}

	xform := transform if transform != {} else IDENTITY
	if xform != IDENTITY {
		if inv, ok := Affine_Invert(xform); ok {
			p = Transform_Point(inv, p)
		}
	}

	return p
}

Linear_Parameter :: proc(gradient: Linear_Gradient, point: Point, bbox: Bounds) -> f64 {

	p := Gradient_Point(point, gradient.units, gradient.transform, bbox)
	scale := max(abs(p.x), abs(p.y), abs(gradient.x1), abs(gradient.y1), abs(gradient.x2), abs(gradient.y2))
	if scale == 0 { return 1 }
	x1, y1, x2, y2 := gradient.x1 / scale, gradient.y1 / scale, gradient.x2 / scale, gradient.y2 / scale
	dx, dy := x2 - x1, y2 - y1
	len_sq := dx * dx + dy * dy
	if len_sq == 0 { return 1 }
	return ((p.x / scale - x1) * dx + (p.y / scale - y1) * dy) / len_sq

}

Radial_Parameter :: proc(gradient: Radial_Gradient, point: Point, bbox: Bounds) -> f64 {
	p := Gradient_Point(point, gradient.units, gradient.transform, bbox)
	fx := gradient.fx
	fy := gradient.fy
	fr := gradient.fr
	if !finite(fx) || !finite(fy) {
		fx, fy = gradient.cx, gradient.cy
	}

	if !(fr >= 0 && finite(fr)) {
		fr = 0
	}

	if !(gradient.r >= 0 && finite(gradient.r)) {
		return 0
	}


	// Normalize before subtracting/squaring so finite extreme coordinates and
	// tiny radii do not overflow or fall into an absolute epsilon branch.
	scale := max(abs(p.x), abs(p.y), abs(fx), abs(fy), abs(gradient.cx), abs(gradient.cy), abs(gradient.r), abs(fr))
	if scale == 0 { return 1 }
	dx, dy := p.x / scale - fx / scale, p.y / scale - fy / scale
	dxr, dyr := gradient.cx / scale - fx / scale, gradient.cy / scale - fy / scale
	normalized_fr := fr / scale
	dr := gradient.r / scale - normalized_fr
	a := dxr * dxr + dyr * dyr - dr * dr
	b := -2 * (dx * dxr + dy * dyr + normalized_fr * dr)
	c := dx * dx + dy * dy - normalized_fr * normalized_fr
	if a == 0 {
		if b > 0 && gradient.r >= fr { return 1 }
		if b == 0 { return c > 0 ? 1 : 0 }
		return -c / b
	}
	discriminant := max(f64(0), b * b - 4 * a * c)
	q := -.5 * (b + (b < 0 ? -1 : 1) * math.sqrt(discriminant))
	if q == 0 { return -b / (2 * a) }
	return max(q / a, c / q)

}

/*
Resolves paint at a path-space point. `none` returns transparent and painted=false.
*/
Paint_Color_At :: proc(
	paint: Paint,
	point: Point,
	bbox: Bounds,
	current_color: Color = {0, 0, 0, 255},
) -> (
	color: Color,
	painted: bool,
) {
	switch paint.kind {
	case .None:
		return {0, 0, 0, 0}, false
	case .Solid:
		return paint.solid, paint.solid.a > 0
	case .Current_Color:
		return current_color, current_color.a > 0
	case .Linear_Gradient:
		if len(paint.linear.stops) == 0 {
			return {0, 0, 0, 0}, false
		}
		if paint.linear.x1 == paint.linear.x2 && paint.linear.y1 == paint.linear.y2 {
			color = paint.linear.stops[len(paint.linear.stops) - 1].color
			return color, color.a > 0
		}

		t := Spread_Parameter(
			Linear_Parameter(paint.linear, point, bbox),
			paint.linear.spread,
		)
		color = Sample_Stops(paint.linear.stops, t, paint.linear.color_interpolation)
		return color, color.a > 0
	case .Radial_Gradient:
		if len(paint.radial.stops) == 0 {
			return {0, 0, 0, 0}, false
		}

		t := Spread_Parameter(
			Radial_Parameter(paint.radial, point, bbox),
			paint.radial.spread,
		)
		color = Sample_Stops(paint.radial.stops, t, paint.radial.color_interpolation)
		return color, color.a > 0
	}

	return {0, 0, 0, 0}, false
}

@(private)
clone_stops :: proc(stops: []Gradient_Stop, allocator: mem.Allocator) -> ([]Gradient_Stop, Error) {
	if len(stops) == 0 {
		return nil, .Invalid_Value
	}

	out := make([]Gradient_Stop, len(stops), allocator)
	if out == nil && len(stops) > 0 {
		return nil, .Allocation_Failed
	}

	copy(out, stops)
	return out, .None
}

@(private)
validate_stops :: proc(stops: []Gradient_Stop) -> Error {
	if len(stops) == 0 {
		return .Invalid_Value
	}

	prev := -math.INF_F64
	for stop in stops {
		if !finite(stop.offset) || stop.offset < 0 || stop.offset > 1 {
			return .Invalid_Value
		}

		if stop.offset < prev {
			return .Invalid_Value
		}

		prev = stop.offset
	}

	return .None
}

@(private)
validate_affine :: proc(transform: Affine) -> Error {
	for value in transform {
		if !finite(value) {
			return .Invalid_Value
		}
	}

	xform := transform if transform != {} else IDENTITY
	if xform != IDENTITY {
		if _, ok := Affine_Invert(xform); !ok {
			return .Invalid_Value
		}
	}

	return .None
}

@(private)
validate_linear_gradient :: proc(gradient: Linear_Gradient) -> Error {
	if err := validate_stops(gradient.stops); err != .None {
		return err
	}

	if err := validate_affine(gradient.transform); err != .None {
		return err
	}

	for value in ([4]f64{gradient.x1, gradient.y1, gradient.x2, gradient.y2}) {
		if !finite(value) {
			return .Invalid_Value
		}
	}

	return .None
}

@(private)
validate_radial_gradient :: proc(gradient: Radial_Gradient) -> Error {
	if err := validate_stops(gradient.stops); err != .None {
		return err
	}

	if err := validate_affine(gradient.transform); err != .None {
		return err
	}

	for value in ([6]f64{gradient.cx, gradient.cy, gradient.r, gradient.fx, gradient.fy, gradient.fr}) {
		if !finite(value) {
			return .Invalid_Value
		}
	}

	if gradient.r < 0 || gradient.fr < 0 {
		return .Invalid_Value
	}

	return .None
}
