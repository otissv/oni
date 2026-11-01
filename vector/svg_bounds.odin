package oni_vector

import "core:math"

@(private)
Arc_Geometry :: struct {
	center, a, b: Point,
	begin, sweep: f64,
	line: bool,
}
@(private)
arc_geometry :: proc(start: Point, command: Command, transform: Affine) -> (g: Arc_Geometry, err: Error) {
	end := command.points[0]
	rx, ry := abs(command.radii.x), abs(command.radii.y)
	if start == end { return g, .None }
	if rx == 0 || ry == 0 { g.line = true; return g, .None }
	angle := command.rotation * math.PI / 180
	c, s := math.cos(angle), math.sin(angle)
	delta := (start - end) * .5
	x, y := c * delta.x + s * delta.y, -s * delta.x + c * delta.y
	scale := x * x / (rx * rx) + y * y / (ry * ry)
	if scale > 1 { factor := math.sqrt(scale); rx *= factor; ry *= factor }
	denominator := rx * rx * y * y + ry * ry * x * x
	if denominator <= 0 || !finite(denominator) { return {}, .Invalid_Value }
	factor := math.sqrt(max(f64(0), (rx * rx * ry * ry - denominator) / denominator))
	if command.large_arc == command.sweep { factor = -factor }
	cx, cy := factor * rx * y / ry, -factor * ry * x / rx
	midpoint := (start + end) * .5
	center := Point{c * cx - s * cy + midpoint.x, s * cx + c * cy + midpoint.y}
	u, v := Point{(x - cx) / rx, (y - cy) / ry}, Point{(-x - cx) / rx, (-y - cy) / ry}
	g.begin = math.atan2(u.y, u.x)
	g.sweep = math.atan2(u.x * v.y - u.y * v.x, u.x * v.x + u.y * v.y)
	if !command.sweep && g.sweep > 0 { g.sweep -= 2 * math.PI }
	if command.sweep && g.sweep < 0 { g.sweep += 2 * math.PI }
	g.center = Transform_Point(transform, center)
	g.a = {transform[0] * c * rx + transform[2] * s * rx, transform[1] * c * rx + transform[3] * s * rx}
	g.b = {-transform[0] * s * ry + transform[2] * c * ry, -transform[1] * s * ry + transform[3] * c * ry}
	return g, .None
}
@(private)
geometry_bounds_add :: proc(bounds: ^Bounds, point: Point) {
	if bounds.empty { bounds.min, bounds.max, bounds.empty = point, point, false; return }
	bounds.min = {min(bounds.min.x, point.x), min(bounds.min.y, point.y)}
	bounds.max = {max(bounds.max.x, point.x), max(bounds.max.y, point.y)}
}
@(private)
geometry_bezier :: proc(a, b, c, d: Point, t: f64, cubic: bool) -> Point {
	ab, bc := a * (1 - t) + b * t, b * (1 - t) + c * t
	if !cubic { return ab * (1 - t) + bc * t }
	cd := c * (1 - t) + d * t
	return (ab * (1 - t) + bc * t) * (1 - t) + (bc * (1 - t) + cd * t) * t
}
// Tight geometric bounds exclude stroke expansion and antialiasing padding.
// Curve extrema are analytic so gradient/mask objectBoundingBox units do not
// depend on the renderer's tessellation tolerance.
Geometry_Bounds :: proc(commands: []Command, transform := IDENTITY, limits := DEFAULT_LIMITS) -> (bounds: Bounds, err: Error) {
	bounds.empty = true
	if err = Validate_Commands(commands, limits); err != .None { return }
	for value in transform { if !finite(value) { return bounds, .Invalid_Value } }
	last, start: Point
	for command in commands {
		switch command.kind {
		case .Move:
			last, start = command.points[0], command.points[0]
		case .Line, .Close:
			end := command.kind == .Close ? start : command.points[0]
			geometry_bounds_add(&bounds, Transform_Point(transform, last))
			geometry_bounds_add(&bounds, Transform_Point(transform, end))
			last = end
		case .Quadratic, .Cubic:
			cubic := command.kind == .Cubic
			a := Transform_Point(transform, last)
			b := Transform_Point(transform, command.points[0])
			c := Transform_Point(transform, command.points[1])
			d := cubic ? Transform_Point(transform, command.points[2]) : c
			geometry_bounds_add(&bounds, a)
			geometry_bounds_add(&bounds, d)
			for axis in 0 ..< 2 {
				roots: [2]f64
				count := 0
				if cubic {
					aa := -a[axis] + 3 * b[axis] - 3 * c[axis] + d[axis]
					bb := 2 * (a[axis] - 2 * b[axis] + c[axis])
					cc := b[axis] - a[axis]
					if aa == 0 {
						if bb != 0 { roots[0] = -cc / bb; count = 1 }
					} else {
						discriminant := bb * bb - 4 * aa * cc
						if discriminant >= 0 {
							q := -.5 * (bb + (bb < 0 ? -1 : 1) * math.sqrt(discriminant))
							if q == 0 { roots[0] = -bb / (2 * aa); count = 1 }
							else { roots = {q / aa, cc / q}; count = 2 }
						}
					}
				} else {
					denominator := a[axis] - 2 * b[axis] + c[axis]
					if denominator != 0 { roots[0] = (a[axis] - b[axis]) / denominator; count = 1 }
				}
				for t in roots[:count] { if t > 0 && t < 1 { geometry_bounds_add(&bounds, geometry_bezier(a, b, c, d, t, cubic)) } }
			}
			last = command.points[cubic ? 2 : 1]
		case .Arc:
			end := command.points[0]
			if last == end { continue }
			geometry_bounds_add(&bounds, Transform_Point(transform, last))
			geometry_bounds_add(&bounds, Transform_Point(transform, end))
			g, arc_err := arc_geometry(last, command, transform)
			if arc_err != .None { return bounds, arc_err }
			if !g.line {
				for axis in 0 ..< 2 {
					theta := math.atan2(g.b[axis], g.a[axis])
					for angle in ([2]f64{theta, theta + math.PI}) {
						distance := g.sweep >= 0 ? angle - g.begin : g.begin - angle
						distance -= math.floor(distance / (2 * math.PI)) * (2 * math.PI)
						if distance <= abs(g.sweep) { geometry_bounds_add(&bounds, g.center + g.a * math.cos(angle) + g.b * math.sin(angle)) }
					}
				}
			}
			last = end
		}
	}
	if !bounds.empty && (!finite(bounds.min.x) || !finite(bounds.min.y) || !finite(bounds.max.x) || !finite(bounds.max.y)) { return bounds, .Invalid_Value }
	return bounds, .None
}

