package oni_vector

import "core:math"

Point :: [2]f64
Affine :: [6]f64
IDENTITY :: Affine{1, 0, 0, 1, 0, 0}

Error :: enum {
	None,
	Invalid_Path,
	Invalid_Value,
	Limit_Exceeded,
	Mesh_Memory_Limit,
	Allocation_Failed,
}

Limits :: struct {
	max_commands: int,
	max_flattened_segments: int,
	max_intersections: int,
	max_events: int,
	max_triangles: int,
	max_pair_tests: int,
	max_work: int,
	max_exact_ops: int,
	max_integer_bits: int,
	max_mesh_bytes: int,
	max_coordinate: f64,
	tolerance: f64,
	max_subdivision: int,
	// 0 = adaptive tolerance; >0 forces this many subdivision levels for curves
	// so compatible morph remeshes keep stable vertex counts; <0 emits only
	// each curve's endpoint (stable, cheapest morph remesh).
	uniform_subdivision: int,
}

DEFAULT_LIMITS :: Limits{
	max_commands = 1_000_000, max_flattened_segments = 262_144,
	max_intersections = 262_144, max_events = 1_000_000, max_triangles = 1_000_000,
	max_pair_tests = 16_000_000, max_coordinate = 1 << 20,
	max_work = 16_000_000, max_mesh_bytes = 64 * 1024 * 1024,
	max_exact_ops = 16_000_000, max_integer_bits = 4096,
	tolerance = 0.25, max_subdivision = 32,
}

Command_Kind :: enum {
	Move,
	Line,
	Quadratic,
	Cubic,
	Arc,
	Close,
}

Command :: struct {
	kind: Command_Kind,
	points: [3]Point,
	radii: Point,
	rotation: f64,
	large_arc, sweep: bool,
}

Path :: struct {
	commands: [dynamic]Command,
}

Contour :: struct {
	first, count: int,
	closed: bool,
}

Flat_Path :: struct {
	points: [dynamic]Point,
	contours: [dynamic]Contour,
}

Fill_Rule :: enum {
	Nonzero,
	Even_Odd,
}

Mesh :: struct {
	vertices: [dynamic][2]f32,
	indices: [dynamic]u32,
	// Internal: vertices follow the original close-stripped contour slots.
	contour_slots: bool,
}

Destroy_Path :: proc(path: ^Path) {
	delete(path.commands)
	path^ = {}
}

Destroy_Flat_Path :: proc(path: ^Flat_Path) {
	delete(path.points)
	delete(path.contours)
	path^ = {}
}

Destroy_Mesh :: proc(mesh: ^Mesh) {
	delete(mesh.vertices)
	delete(mesh.indices)
	mesh^ = {}
}

Transform_Point :: proc(transform: Affine, point: Point) -> Point {
	return {
		transform[0] * point.x + transform[2] * point.y + transform[4],
		transform[1] * point.x + transform[3] * point.y + transform[5],
	}
}

@(private)
finite :: proc(value: f64) -> bool {
	return (transmute(u64)value & 0x7ff0000000000000) != 0x7ff0000000000000
}

@(private)
append_command :: proc(path: ^Path, command: Command) -> Error {
	if path == nil || (len(path.commands) == 0 && command.kind != .Move) {
		return .Invalid_Path
	}
	if command.kind < .Move || command.kind > .Close {
		return .Invalid_Path
	}
	if len(path.commands) >= DEFAULT_LIMITS.max_commands {
		return .Limit_Exceeded
	}
	for point in command.points {
		if !finite(point.x) || !finite(point.y) {
			return .Invalid_Value
		}
	}
	if !finite(command.radii.x) || !finite(command.radii.y) || !finite(command.rotation) {
		return .Invalid_Value
	}
	if _, err := append(&path.commands, command); err != nil {
		return .Allocation_Failed
	}
	return .None
}

Validate_Commands :: proc(commands: []Command, limits := DEFAULT_LIMITS) -> Error {
	if len(commands) > limits.max_commands {
		return .Limit_Exceeded
	}
	if len(commands) > 0 && commands[0].kind != .Move {
		return .Invalid_Path
	}
	for command in commands {
		if command.kind < .Move || command.kind > .Close {
			return .Invalid_Path
		}
		for point in command.points {
			if !finite(point.x) || !finite(point.y) {
				return .Invalid_Value
			}
		}
		if !finite(command.radii.x) || !finite(command.radii.y) || !finite(command.rotation) {
			return .Invalid_Value
		}
	}
	return .None
}

Move_To :: proc(path: ^Path, point: Point) -> Error {
	return append_command(path, {kind = .Move, points = {point, {}, {}}})
}

Line_To :: proc(path: ^Path, point: Point) -> Error {
	return append_command(path, {kind = .Line, points = {point, {}, {}}})
}

Quadratic_To :: proc(path: ^Path, control, point: Point) -> Error {
	return append_command(path, {kind = .Quadratic, points = {control, point, {}}})
}

Cubic_To :: proc(path: ^Path, control_a, control_b, point: Point) -> Error {
	return append_command(path, {kind = .Cubic, points = {control_a, control_b, point}})
}

Arc_To :: proc(path: ^Path, radii: Point, rotation: f64, large_arc, sweep: bool, point: Point) -> Error {
	return append_command(path, {kind = .Arc, points = {point, {}, {}}, radii = radii, rotation = rotation, large_arc = large_arc, sweep = sweep})
}

Close :: proc(path: ^Path) -> Error {
	return append_command(path, {kind = .Close})
}

@(private)
point_segment_distance :: proc(point, a, b: Point) -> f64 {
	return math.sqrt(point_segment_distance_squared(point, a, b))
}

@(private)
point_segment_distance_squared :: proc(point, a, b: Point) -> f64 {
	d := b - a
	length_squared := d.x * d.x + d.y * d.y
	if length_squared == 0 {
		v := point - a
		return v.x * v.x + v.y * v.y
	}
	t := clamp(((point.x - a.x) * d.x + (point.y - a.y) * d.y) / length_squared, f64(0), f64(1))
	v := point - (a + d * t)
	return v.x * v.x + v.y * v.y
}

@(private)
flat_append :: proc(flat: ^Flat_Path, point: Point, limits: Limits) -> Error {
	if !(abs(point.x) <= limits.max_coordinate && abs(point.y) <= limits.max_coordinate) {
		return .Invalid_Value
	}
	if len(flat.points) >= limits.max_flattened_segments {
		return .Limit_Exceeded
	}
	quantized := Point{math.round(point.x * 1024) / 1024, math.round(point.y * 1024) / 1024}
	if _, err := append(&flat.points, quantized); err != nil {
		return .Allocation_Failed
	}
	return .None
}

@(private)
flatten_tolerance :: proc(limits: Limits) -> f64 {
	// Reserve the worst-case displacement caused by snapping both coordinates.
	return limits.tolerance - 1.4142135623730951 / 2048
}

@(private)
flatten_quadratic :: proc(flat: ^Flat_Path, a, b, c: Point, limits: Limits, depth: int) -> Error {
	if limits.uniform_subdivision < 0 {
		return flat_append(flat, c, limits)
	}
	if limits.uniform_subdivision > 0 {
		if depth >= limits.uniform_subdivision {
			return flat_append(flat, c, limits)
		}
	} else {
		tolerance := flatten_tolerance(limits)
		if point_segment_distance_squared(b, a, c) <= tolerance * tolerance {
			return flat_append(flat, c, limits)
		}
	}
	if depth >= limits.max_subdivision {
		return .Limit_Exceeded
	}
	ab := (a + b) * 0.5
	bc := (b + c) * 0.5
	mid := (ab + bc) * 0.5
	if err := flatten_quadratic(flat, a, ab, mid, limits, depth + 1); err != .None {
		return err
	}
	return flatten_quadratic(flat, mid, bc, c, limits, depth + 1)
}

@(private)
flatten_cubic :: proc(flat: ^Flat_Path, a, b, c, d: Point, limits: Limits, depth: int) -> Error {
	if limits.uniform_subdivision < 0 {
		return flat_append(flat, d, limits)
	}
	if limits.uniform_subdivision > 0 {
		if depth >= limits.uniform_subdivision {
			return flat_append(flat, d, limits)
		}
	} else {
		tolerance := flatten_tolerance(limits)
		if max(point_segment_distance_squared(b, a, d), point_segment_distance_squared(c, a, d)) <= tolerance * tolerance {
			return flat_append(flat, d, limits)
		}
	}
	if depth >= limits.max_subdivision {
		return .Limit_Exceeded
	}
	ab := (a + b) * 0.5
	bc := (b + c) * 0.5
	cd := (c + d) * 0.5
	abc := (ab + bc) * 0.5
	bcd := (bc + cd) * 0.5
	mid := (abc + bcd) * 0.5
	if err := flatten_cubic(flat, a, ab, abc, mid, limits, depth + 1); err != .None {
		return err
	}
	return flatten_cubic(flat, mid, bcd, cd, d, limits, depth + 1)
}

@(private)
flatten_arc :: proc(flat: ^Flat_Path, start: Point, command: Command, transform: Affine, limits: Limits) -> Error {
	end := command.points[0]
	if start == end { return .None }
	g, err := arc_geometry(start, command, transform)
	if err != .None { return err }
	if g.line { return flat_append(flat, Transform_Point(transform, end), limits) }
	radius_bound := math.sqrt(g.a.x * g.a.x + g.a.y * g.a.y) + math.sqrt(g.b.x * g.b.x + g.b.y * g.b.y)
	tolerance := flatten_tolerance(limits)
	step := radius_bound > tolerance ? 2 * math.acos(clamp(1 - tolerance / radius_bound, f64(-1), f64(1))) : math.PI
	if !finite(step) || step <= 0 { return .Limit_Exceeded }
	segment_count := math.ceil(abs(g.sweep) / min(step, math.PI * .5))
	if segment_count > f64(limits.max_flattened_segments - len(flat.points)) { return .Limit_Exceeded }
	for i in 1 ..= int(segment_count) {
		t := g.begin + g.sweep * f64(i) / segment_count
		point := g.center + g.a * math.cos(t) + g.b * math.sin(t)
		if i == int(segment_count) { point = Transform_Point(transform, end) }
		if append_err := flat_append(flat, point, limits); append_err != .None { return append_err }
	}
	return .None
}

// Flatten owns its returned buffers. Failure returns an empty result, and the
// tolerance is measured after the supplied transform in physical device pixels.
Flatten :: proc(commands: []Command, transform: Affine, limits := DEFAULT_LIMITS) -> (flat: Flat_Path, err: Error) {
	flat, err = flatten_impl(commands, transform, limits)
	if err != .None {
		Destroy_Flat_Path(&flat)
	}
	return flat, err
}

@(private)
flatten_impl :: proc(commands: []Command, transform: Affine, limits: Limits) -> (flat: Flat_Path, err: Error) {
	if limits.max_flattened_segments <= 0 || limits.max_subdivision <= 0 ||
	   limits.max_subdivision > DEFAULT_LIMITS.max_subdivision ||
	   !(flatten_tolerance(limits) > 0 && finite(limits.tolerance)) ||
	   !(limits.max_coordinate > 0 && limits.max_coordinate <= DEFAULT_LIMITS.max_coordinate) {
		return {}, .Invalid_Value
	}
	for value in transform {
		if !finite(value) {
			return {}, .Invalid_Value
		}
	}
	if len(commands) > limits.max_commands {
		return {}, .Limit_Exceeded
	}
	if len(commands) > 0 {
		points, points_error := make([dynamic]Point, 0, min(len(commands), limits.max_flattened_segments))
		if points_error != nil { return flat, .Allocation_Failed }
		flat.points = points
		contours, contours_error := make([dynamic]Contour, 0, 1)
		if contours_error != nil { return flat, .Allocation_Failed }
		flat.contours = contours
	}
	current, start := Point{}, Point{}
	contour := -1
	for command in commands {
		if command.kind < .Move || command.kind > .Close {
			return flat, .Invalid_Path
		}
		for point in command.points {
			if !finite(point.x) || !finite(point.y) {
				return flat, .Invalid_Value
			}
		}
		point_count := command.kind == .Cubic ? 3 : (command.kind == .Quadratic ? 2 : (command.kind == .Close ? 0 : 1))
		points: [3]Point
		for i in 0 ..< point_count {
			p := Transform_Point(transform, command.points[i])
			if !(abs(p.x) <= limits.max_coordinate && abs(p.y) <= limits.max_coordinate) {
				return flat, .Invalid_Value
			}
			points[i] = p
		}
		if contour >= 0 && flat.contours[contour].closed && command.kind != .Move && command.kind != .Close {
			flat.contours[contour].count = len(flat.points) - flat.contours[contour].first
			contour = len(flat.contours)
			if _, allocation_error := append(&flat.contours, Contour{first = len(flat.points)}); allocation_error != nil {
				return flat, .Allocation_Failed
			}
			if err = flat_append(&flat, Transform_Point(transform, current), limits); err != .None {
				return flat, err
			}
		}
		if command.kind == .Move {
			if contour >= 0 {
				flat.contours[contour].count = len(flat.points) - flat.contours[contour].first
			}
			contour = len(flat.contours)
			if _, allocation_error := append(&flat.contours, Contour{first = len(flat.points)}); allocation_error != nil {
				return flat, .Allocation_Failed
			}
			current = command.points[0]
			start = current
			err = flat_append(&flat, points[0], limits)
		} else {
			if contour < 0 {
				return flat, .Invalid_Path
			}
			switch command.kind {
			case .Move:
			case .Line:
				err = flat_append(&flat, points[0], limits)
				current = command.points[0]
			case .Quadratic:
				err = flatten_quadratic(&flat, Transform_Point(transform, current), points[0], points[1], limits, 0)
				current = command.points[1]
			case .Cubic:
				err = flatten_cubic(&flat, Transform_Point(transform, current), points[0], points[1], points[2], limits, 0)
				current = command.points[2]
			case .Arc:
				if !finite(command.radii.x) || !finite(command.radii.y) || !finite(command.rotation) {
					return flat, .Invalid_Value
				}
				err = flatten_arc(&flat, current, command, transform, limits)
				current = command.points[0]
			case .Close:
				// Depth-uniform morph remesh needs a fixed sample count; always
				// emit the close vertex. Endpoint mode (-1) only emits when the
				// curve end did not already land on the move point.
				if limits.uniform_subdivision > 0 || current != start {
					err = flat_append(&flat, Transform_Point(transform, start), limits)
				}
				flat.contours[contour].closed = true
				current = start
			}
		}
		if err != .None {
			return flat, err
		}
	}
	if contour >= 0 {
		flat.contours[contour].count = len(flat.points) - flat.contours[contour].first
	}
	return
}
