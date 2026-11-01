package oni_vector

import "core:math"
import "core:mem"

Line_Cap :: enum {
	Butt,
	Round,
	Square,
}

Line_Join :: enum {
	Miter,
	Round,
	Bevel,
}

Stroke :: struct {
	width:       f64,
	cap:         Line_Cap,
	join:        Line_Join,
	miter_limit: f64,
	dash:        []f64,
	dash_offset: f64,
	path_length: f64,
	non_scaling: bool,
}

DEFAULT_STROKE :: Stroke {
	width       = 1,
	cap         = .Butt,
	join        = .Miter,
	miter_limit = 4,
}

Validate_Stroke :: proc(stroke: Stroke) -> Error {
	if !(stroke.width >= 0 && finite(stroke.width)) {
		return .Invalid_Value
	}

	if !(stroke.miter_limit >= 1 && finite(stroke.miter_limit)) {
		return .Invalid_Value
	}

	if !finite(stroke.dash_offset) || !(stroke.path_length >= 0 && finite(stroke.path_length)) {
		return .Invalid_Value
	}

	for value in stroke.dash {
		if !(value >= 0 && finite(value)) {
			return .Invalid_Value
		}
	}

	return .None
}

Stroke_Bounds :: proc(
	commands: []Command,
	transform := IDENTITY,
	stroke := DEFAULT_STROKE,
	limits := DEFAULT_LIMITS,
) -> (
	bounds: Bounds,
	err: Error,
) {
	if err = Validate_Stroke(stroke); err != .None {
		return {empty = true}, err
	}

	if stroke.width == 0 {
		return Path_Bounds(commands, transform, limits)
	}

	outline: Path
	defer Destroy_Path(&outline)
	if err = stroke_build_outline(&outline, commands, transform, stroke, limits); err != .None {
		return {empty = true}, err
	}

	return Path_Bounds(outline.commands[:], IDENTITY, limits)
}

Tessellate_Stroke :: proc(
	commands: []Command,
	transform: Affine,
	stroke: Stroke,
	limits := DEFAULT_LIMITS,
	scratch_allocator: mem.Allocator = {},
) -> (
	mesh: Mesh,
	err: Error,
) {
	err = Tessellate_Stroke_Into(&mesh, commands, transform, stroke, limits, scratch_allocator)

	return
}

Tessellate_Stroke_Into :: proc(
	mesh: ^Mesh,
	commands: []Command,
	transform: Affine,
	stroke: Stroke,
	limits := DEFAULT_LIMITS,
	scratch_allocator: mem.Allocator = {},
	usage: ^Build_Usage = nil,
) -> Error {
	if mesh == nil {
		return .Invalid_Path
	}

	clear(&mesh.vertices)
	clear(&mesh.indices)
	if usage != nil {
		usage^ = {}
	}

	if err := Validate_Stroke(stroke); err != .None {
		return err
	}

	if stroke.width == 0 || len(commands) == 0 {
		return .None
	}

	outline: Path
	defer Destroy_Path(&outline)
	if err := stroke_build_outline(&outline, commands, transform, stroke, limits); err != .None {
		return err
	}

	if len(outline.commands) == 0 {
		return .None
	}

	return Tessellate_Into(mesh, outline.commands[:], IDENTITY, .Nonzero, limits, scratch_allocator, usage)
}

@(private)
stroke_len :: proc(v: Point) -> f64 {
	return math.sqrt(v.x * v.x + v.y * v.y)
}

@(private)
stroke_norm :: proc(v: Point) -> (Point, bool) {
	length := stroke_len(v)
	if length == 0 || !finite(length) {
		return {}, false
	}

	return {v.x / length, v.y / length}, true
}

@(private)
stroke_perp :: proc(v: Point) -> Point {
	return {-v.y, v.x}
}

@(private)
stroke_dot :: proc(a, b: Point) -> f64 {
	return a.x * b.x + a.y * b.y
}

@(private)
stroke_cross :: proc(a, b: Point) -> f64 {
	return a.x * b.y - a.y * b.x
}

@(private)
stroke_linear_scale :: proc(transform: Affine) -> f64 {
	sx := stroke_len({transform[0], transform[1]})
	sy := stroke_len({transform[2], transform[3]})
	return max(sx, sy, 1e-12)
}

@(private)
stroke_arc_steps :: proc(radius, sweep, tolerance: f64) -> int {
	if !(radius > 0 && finite(radius) && finite(sweep) && tolerance > 0) {
		return max(8, int(math.ceil(abs(sweep) / (math.PI / 8))))
	}

	// Chord error r*(1-cos(θ/2)) ≤ tolerance.
	ratio := clamp(1 - tolerance / radius, f64(-1), f64(1))
	theta := 2 * math.acos(ratio)
	if !(theta > 0 && finite(theta)) {
		theta = math.PI / 8
	}

	// Keep a dense floor so small radii still approximate the circle well.
	floor := abs(sweep) >= 2 * math.PI - 1e-6 ? 16 : (abs(sweep) >= math.PI - 1e-6 ? 8 : 4)

	return max(floor, int(math.ceil(abs(sweep) / theta)))
}

@(private)
stroke_map :: proc(point: Point, stroke: Stroke, transform: Affine) -> Point {
	if stroke.non_scaling {
		return point
	}

	return Transform_Point(transform, point)
}

@(private)
stroke_outline_limit :: proc(outline: ^Path, limits: Limits) -> Error {
	if outline == nil {
		return .Invalid_Path
	}

	if len(outline.commands) > limits.max_commands {
		return .Limit_Exceeded
	}

	return .None
}

@(private)
stroke_move_to :: proc(outline: ^Path, point: Point, limits: Limits) -> Error {
	if len(outline.commands) >= limits.max_commands {
		return .Limit_Exceeded
	}

	if err := Move_To(outline, point); err != .None {
		return err
	}

	return stroke_outline_limit(outline, limits)
}

@(private)
stroke_line_to :: proc(outline: ^Path, point: Point, limits: Limits) -> Error {
	if len(outline.commands) >= limits.max_commands {
		return .Limit_Exceeded
	}

	if err := Line_To(outline, point); err != .None {
		return err
	}

	return stroke_outline_limit(outline, limits)
}

@(private)
stroke_close :: proc(outline: ^Path, limits: Limits) -> Error {
	if len(outline.commands) >= limits.max_commands {
		return .Limit_Exceeded
	}

	if err := Close(outline); err != .None {
		return err
	}

	return stroke_outline_limit(outline, limits)
}

@(private)
stroke_arc_tolerance :: proc(stroke: Stroke, transform: Affine, limits: Limits) -> f64 {
	if stroke.non_scaling {
		return limits.tolerance
	}

	// Caps/joins are built in user space then transformed; keep device error ≤ tolerance.
	return limits.tolerance / stroke_linear_scale(transform)
}

@(private)
stroke_build_outline :: proc(
	outline: ^Path,
	commands: []Command,
	transform: Affine,
	stroke: Stroke,
	limits: Limits,
) -> Error {
	flatten_limits := limits
	flatten_transform := transform
	if stroke.non_scaling {
		// Device-space centreline; width stays in device units.
		flatten_transform = transform
	} else {
		// SVG model: stroke in user space, then transform the outline. Tighten
		// flattening so post-transform device error stays within limits.tolerance.
		flatten_transform = IDENTITY
		scale := stroke_linear_scale(transform)
		flatten_limits.tolerance = limits.tolerance / scale
		if !(flatten_tolerance(flatten_limits) > 0) {
			return .Invalid_Value
		}
	}

	flat, err := Flatten(commands, flatten_transform, flatten_limits)
	defer Destroy_Flat_Path(&flat)
	if err != .None {
		return err
	}

	total_geom: f64
	for contour in flat.contours {
		if contour.count <= 0 {
			continue
		}

		points := flat.points[contour.first:contour.first + contour.count]
		total_geom += stroke_poly_length(points, contour.closed)
	}

	// pathLength normalizes the whole path, not each contour independently.
	path_scale: f64 = 1
	if stroke.path_length > 0 && total_geom > 0 {
		path_scale = stroke.path_length / total_geom
	}

	dash_state: Stroke_Dash_State
	use_dash := false
	if len(stroke.dash) > 0 {
		pattern, cycle_len := stroke_dash_pattern(stroke.dash)
		if pattern > 0 {
			use_dash = true
			dash_state = stroke_dash_begin(stroke, pattern, cycle_len)
		}
	}

	for contour in flat.contours {
		if contour.count <= 0 {
			continue
		}

		points := flat.points[contour.first:contour.first + contour.count]
		if use_dash {
			if err = stroke_dash_contour(outline, points, contour.closed, stroke, transform, limits, path_scale, &dash_state); err != .None {
				return err
			}
		} else if err = stroke_solid_contour(outline, points, contour.closed, stroke, transform, limits); err != .None {
			return err
		}

		if err = stroke_outline_limit(outline, limits); err != .None {
			return err
		}
	}

	return .None
}

@(private)
stroke_poly_length :: proc(points: []Point, closed: bool) -> f64 {
	total: f64
	for i in 1 ..< len(points) {
		total += stroke_len(points[i] - points[i - 1])
	}

	if closed && len(points) > 1 {
		total += stroke_len(points[0] - points[len(points) - 1])
	}

	return total
}

// SVG repeats an odd-length dash array to form an even pattern; the period is that full cycle.
@(private)
stroke_dash_pattern :: proc(dash: []f64) -> (pattern: f64, cycle_len: int) {
	for value in dash {
		pattern += value
	}

	cycle_len = len(dash)
	if cycle_len > 0 && cycle_len % 2 == 1 {
		pattern *= 2
		cycle_len *= 2
	}

	return
}

@(private)
stroke_dash_value :: proc(dash: []f64, index: int) -> f64 {
	return dash[index % len(dash)]
}

@(private)
Stroke_Dash_State :: struct {
	pattern_index:  int,
	remaining_path: f64,
	on:             bool,
	cycle_len:      int,
}

@(private)
stroke_dash_begin :: proc(stroke: Stroke, pattern: f64, cycle_len: int) -> Stroke_Dash_State {
	state := Stroke_Dash_State{
		pattern_index = 0,
		remaining_path = stroke.dash[0],
		on = true,
		cycle_len = cycle_len,
	}
	offset := math.mod(stroke.dash_offset, pattern)
	if offset < 0 {
		offset += pattern
	}

	cursor := offset
	for cursor > 1e-12 {
		step := min(cursor, state.remaining_path)
		cursor -= step
		state.remaining_path -= step
		if state.remaining_path <= 1e-12 {
			state.pattern_index = (state.pattern_index + 1) % state.cycle_len
			state.remaining_path = stroke_dash_value(stroke.dash, state.pattern_index)
			state.on = !state.on
		}
	}

	return state
}

@(private)
stroke_dash_advance :: proc(state: ^Stroke_Dash_State, dash: []f64) {
	state.pattern_index = (state.pattern_index + 1) % state.cycle_len
	state.remaining_path = stroke_dash_value(dash, state.pattern_index)
	state.on = !state.on
}

@(private)
Stroke_Fragment :: struct {
	points: [dynamic]Point,
	closed: bool,
}

@(private)
stroke_fragment_destroy :: proc(fragment: ^Stroke_Fragment) {
	delete(fragment.points)
	fragment^ = {}
}

@(private)
stroke_dash_contour :: proc(
	outline: ^Path,
	points: []Point,
	closed: bool,
	stroke: Stroke,
	transform: Affine,
	limits: Limits,
	path_scale: f64,
	state: ^Stroke_Dash_State,
) -> Error {
	if state == nil || state.cycle_len <= 0 || path_scale <= 0 || !finite(path_scale) {
		return stroke_solid_contour(outline, points, closed, stroke, transform, limits)
	}

	geom := stroke_poly_length(points, closed)
	if geom == 0 {
		return stroke_solid_contour(outline, points, closed, stroke, transform, limits)
	}

	segment_count := closed ? len(points) : len(points) - 1
	if segment_count <= 0 {
		return stroke_solid_contour(outline, points, closed, stroke, transform, limits)
	}

	fragments: [dynamic]Stroke_Fragment
	defer {
		for &fragment in fragments {
			stroke_fragment_destroy(&fragment)
		}

		delete(fragments)
	}

	started_on_at_origin := state.on
	active: [dynamic]Point
	defer delete(active)
	push_active :: proc(active: ^[dynamic]Point, point: Point, limits: Limits) -> Error {
		if len(active) >= limits.max_flattened_segments {
			return .Limit_Exceeded
		}

		if _, alloc_err := append(active, point); alloc_err != nil {
			return .Allocation_Failed
		}

		return .None
	}

	if state.on {
		if err := push_active(&active, points[0], limits); err != .None {
			return err
		}
	}

	emit_open :: proc(fragments: ^[dynamic]Stroke_Fragment, active: ^[dynamic]Point, limits: Limits) -> Error {
		if len(active) == 0 {
			return .None
		}

		if len(active) > limits.max_flattened_segments {
			return .Limit_Exceeded
		}

		fragment: Stroke_Fragment
		if _, err := append(&fragment.points, ..active[:]); err != nil {
			stroke_fragment_destroy(&fragment)

			return .Allocation_Failed
		}

		if _, err := append(fragments, fragment); err != nil {
			stroke_fragment_destroy(&fragment)

			return .Allocation_Failed
		}

		clear(active)

		return .None
	}

	for seg in 0 ..< segment_count {
		a := points[seg % len(points)]
		b := points[(seg + 1) % len(points)]
		delta := b - a
		seg_len := stroke_len(delta)
		if seg_len == 0 {
			continue
		}

		dir := delta * (1 / seg_len)
		consumed: f64
		for consumed < seg_len - 1e-12 {
			// Convert remaining path-distance budget into geometric length.
			remaining_geom := state.remaining_path / path_scale
			step := min(remaining_geom, seg_len - consumed)
			from := a + dir * consumed
			to := a + dir * (consumed + step)
			path_step := step * path_scale
			if state.on {
				if len(active) == 0 {
					if err := push_active(&active, from, limits); err != .None {
						return err
					}
				}

				if err := push_active(&active, to, limits); err != .None {
					return err
				}
			} else if len(active) > 0 {
				if err := emit_open(&fragments, &active, limits); err != .None {
					return err
				}
			}

			consumed += step
			state.remaining_path -= path_step
			if state.remaining_path > 1e-12 {
				continue
			}

			was_on := state.on
			stroke_dash_advance(state, stroke.dash)
			if was_on && len(active) > 0 {
				if err := emit_open(&fragments, &active, limits); err != .None {
					return err
				}
			}

			if state.on {
				if err := push_active(&active, to, limits); err != .None {
					return err
				}
			}
		}
	}

	if len(active) > 0 {
		if err := emit_open(&fragments, &active, limits); err != .None {
			return err
		}
	}

	if len(fragments) == 0 {
		return .None
	}

	// Closed contour: a dash that stays on across the seam must keep corner joins,
	// not open-path caps. A single full-loop fragment is closed; a seam-wrapped pair
	// merges into one open polyline so the ends are not joined by a diagonal.
	if closed && started_on_at_origin && len(fragments) > 0 {
		first_points := fragments[0].points
		last_index := len(fragments) - 1
		last_points := fragments[last_index].points
		starts_at_origin := len(first_points) > 0 && first_points[0] == points[0]
		ends_at_origin := len(last_points) > 0 && last_points[len(last_points) - 1] == points[0]
		if starts_at_origin && ends_at_origin {
			if len(fragments) == 1 {
				fragments[0].closed = true
			} else if len(first_points) + len(last_points) - 1 > limits.max_flattened_segments {
				return .Limit_Exceeded
			} else if _, err := append(&fragments[last_index].points, ..first_points[1:]); err != nil {
				return .Allocation_Failed
			} else {
				stroke_fragment_destroy(&fragments[0])
				ordered_remove(&fragments, 0)
			}
		}
	}

	for &fragment in fragments {
		if err := stroke_solid_contour(outline, fragment.points[:], fragment.closed, stroke, transform, limits); err != .None {
			return err
		}

		if err := stroke_outline_limit(outline, limits); err != .None {
			return err
		}
	}

	return .None
}

@(private)
stroke_dedupe :: proc(points: []Point, closed: bool) -> ([dynamic]Point, Error) {
	out: [dynamic]Point
	for point, i in points {
		if i > 0 && point == out[len(out) - 1] {
			continue
		}

		if _, err := append(&out, point); err != nil {
			delete(out)

			return nil, .Allocation_Failed
		}
	}

	if closed && len(out) > 1 && out[0] == out[len(out) - 1] {
		pop(&out)
	}

	return out, .None
}

@(private)
stroke_solid_contour :: proc(
	outline: ^Path,
	points: []Point,
	closed: bool,
	stroke: Stroke,
	transform: Affine,
	limits: Limits,
) -> Error {
	half := stroke.width * 0.5
	if half == 0 || len(points) == 0 {
		return .None
	}

	deduped, dedupe_err := stroke_dedupe(points, closed)
	defer delete(deduped)
	if dedupe_err != .None {
		return dedupe_err
	}

	if len(deduped) == 0 {
		return .None
	}

	if len(deduped) == 1 {
		return stroke_point_cap(outline, deduped[0], stroke.cap, half, stroke, transform, limits)
	}

	n := len(deduped)
	segment_count := closed ? n : n - 1
	if segment_count <= 0 {
		return stroke_point_cap(outline, deduped[0], stroke.cap, half, stroke, transform, limits)
	}

	tangents, tangents_err := make([]Point, segment_count)
	if tangents_err != nil || len(tangents) != segment_count {
		return .Allocation_Failed
	}

	defer delete(tangents)
	valid_segments := 0
	for i in 0 ..< segment_count {
		a := deduped[i]
		b := deduped[(i + 1) % n]
		if tangent, ok := stroke_norm(b - a); ok {
			tangents[i] = tangent
			valid_segments += 1
		}
	}

	if valid_segments == 0 {
		return stroke_point_cap(outline, deduped[0], stroke.cap, half, stroke, transform, limits)
	}

	arc_tol := stroke_arc_tolerance(stroke, transform, limits)
	left: [dynamic]Point
	right: [dynamic]Point
	defer {
		delete(left)
		delete(right)
	}

	push_side :: proc(side: ^[dynamic]Point, point: Point, limits: Limits) -> Error {
		if len(side) >= limits.max_flattened_segments {
			return .Limit_Exceeded
		}

		if _, err := append(side, point); err != nil {
			return .Allocation_Failed
		}

		return .None
	}

	for i in 0 ..< n {
		prev_seg := -1
		next_seg := -1
		if closed {
			prev_seg = (i + n - 1) % n
			next_seg = i % n
		} else if i == 0 {
			next_seg = 0
		} else if i == n - 1 {
			prev_seg = n - 2
		} else {
			prev_seg = i - 1
			next_seg = i
		}

		tin := prev_seg >= 0 ? tangents[prev_seg] : Point{}
		tout := next_seg >= 0 ? tangents[next_seg] : Point{}
		if tin == (Point{}) && tout == (Point{}) {
			continue
		}

		if tin == (Point{}) {
			tin = tout
		}

		if tout == (Point{}) {
			tout = tin
		}

		if !closed && (i == 0 || i == n - 1) {
			normal := stroke_perp(i == 0 ? tout : tin)
			if err := push_side(&left, deduped[i] + normal * half, limits); err != .None {
				return err
			}

			if err := push_side(&right, deduped[i] - normal * half, limits); err != .None {
				return err
			}

			continue
		}

		if err := stroke_join_offsets(&left, &right, deduped[i], tin, tout, stroke.join, stroke.miter_limit, half, arc_tol, limits); err != .None {
			return err
		}
	}

	if len(left) == 0 || len(right) == 0 {
		return .None
	}

	if len(left) > limits.max_flattened_segments || len(right) > limits.max_flattened_segments {
		return .Limit_Exceeded
	}

	before := len(outline.commands)
	if closed {
		// Closed strokes emit outer + inner contours so the ring remains a single
		// coverage region under nonzero fill (avoids a self-overlapping strip).
		signed: f64
		for i in 0 ..< n {
			signed += stroke_cross(deduped[i], deduped[(i + 1) % n])
		}

		outer, inner := right[:], left[:]
		if signed < 0 {
			outer, inner = left[:], right[:]
		}

		if err := stroke_append_closed_ring(outline, outer, inner, stroke, transform, limits); err != .None {
			resize(&outline.commands, before)

			return err
		}

		return .None
	}

	if err := stroke_move_to(outline, stroke_map(left[0], stroke, transform), limits); err != .None {
		resize(&outline.commands, before)

		return err
	}

	for point in left[1:] {
		if err := stroke_line_to(outline, stroke_map(point, stroke, transform), limits); err != .None {
			resize(&outline.commands, before)

			return err
		}
	}

	start_tangent := tangents[0]
	end_tangent := tangents[segment_count - 1]
	if start_tangent == (Point{}) || end_tangent == (Point{}) {
		for t in tangents {
			if t == (Point{}) {
				continue
			}

			if start_tangent == (Point{}) {
				start_tangent = t
			}

			end_tangent = t
		}
	}

	if err := stroke_cap_points(outline, deduped[n - 1], end_tangent, stroke.cap, half, stroke, transform, true, arc_tol, limits); err != .None {
		resize(&outline.commands, before)

		return err
	}

	for i := len(right) - 1; i >= 0; i -= 1 {
		if err := stroke_line_to(outline, stroke_map(right[i], stroke, transform), limits); err != .None {
			resize(&outline.commands, before)

			return err
		}
	}

	if err := stroke_cap_points(outline, deduped[0], start_tangent, stroke.cap, half, stroke, transform, false, arc_tol, limits); err != .None {
		resize(&outline.commands, before)

		return err
	}

	if err := stroke_close(outline, limits); err != .None {
		resize(&outline.commands, before)

		return err
	}

	return .None
}

@(private)
stroke_append_poly :: proc(
	outline: ^Path,
	points: []Point,
	stroke: Stroke,
	transform: Affine,
	reverse: bool,
	limits: Limits,
) -> Error {
	if len(points) == 0 {
		return .None
	}

	if reverse {
		if err := stroke_move_to(outline, stroke_map(points[len(points) - 1], stroke, transform), limits); err != .None {
			return err
		}

		for i := len(points) - 2; i >= 0; i -= 1 {
			if err := stroke_line_to(outline, stroke_map(points[i], stroke, transform), limits); err != .None {
				return err
			}
		}
	} else {
		if err := stroke_move_to(outline, stroke_map(points[0], stroke, transform), limits); err != .None {
			return err
		}

		for point in points[1:] {
			if err := stroke_line_to(outline, stroke_map(point, stroke, transform), limits); err != .None {
				return err
			}
		}
	}

	return stroke_close(outline, limits)
}

@(private)
stroke_append_closed_ring :: proc(
	outline: ^Path,
	outer, inner: []Point,
	stroke: Stroke,
	transform: Affine,
	limits: Limits,
) -> Error {
	// `right` offsets are outside a CCW centreline; emit outer CCW and inner CW.
	if err := stroke_append_poly(outline, outer, stroke, transform, false, limits); err != .None {
		return err
	}

	return stroke_append_poly(outline, inner, stroke, transform, true, limits)
}

@(private)
stroke_join_offsets :: proc(
	left, right: ^[dynamic]Point,
	vertex, tin, tout: Point,
	join: Line_Join,
	miter_limit: f64,
	half: f64,
	tolerance: f64,
	limits: Limits,
) -> Error {
	nin := stroke_perp(tin)
	nout := stroke_perp(tout)
	cross := stroke_cross(tin, tout)
	dot := stroke_dot(tin, tout)

	push :: proc(side: ^[dynamic]Point, point: Point, limits: Limits) -> Error {
		if len(side) >= limits.max_flattened_segments {
			return .Limit_Exceeded
		}

		if _, err := append(side, point); err != nil {
			return .Allocation_Failed
		}

		return .None
	}

	if abs(cross) <= 1e-12 && dot >= 0 {
		if err := push(left, vertex + nin * half, limits); err != .None {
			return err
		}

		return push(right, vertex - nin * half, limits)
	}

	// Left-side normals are inside a left turn and outside a right turn.
	turning_left := cross > 0
	inner_n0 := turning_left ? nin : -nin
	inner_n1 := turning_left ? nout : -nout
	outer_n0 := -inner_n0
	outer_n1 := -inner_n1

	append_inner_bevel :: proc(side: ^[dynamic]Point, vertex, n0, n1: Point, half: f64, limits: Limits) -> Error {
		if err := push(side, vertex + n0 * half, limits); err != .None {
			return err
		}

		return push(side, vertex + n1 * half, limits)
	}

	use_miter := join == .Miter
	miter: Point
	if use_miter {
		denom := stroke_cross(tin, tout)
		if abs(denom) > 1e-12 {
			p0 := vertex + outer_n0 * half
			p1 := vertex + outer_n1 * half
			s := stroke_cross(p1 - p0, tout) / denom
			candidate := p0 + tin * s
			ratio := stroke_len(candidate - vertex) / half
			if finite(ratio) && ratio <= miter_limit {
				miter = candidate
			} else {
				use_miter = false
			}
		} else {
			use_miter = false
		}
	}

	if use_miter {
		if turning_left {
			if err := push(right, miter, limits); err != .None {
				return err
			}

			return append_inner_bevel(left, vertex, nin, nout, half, limits)
		}

		if err := push(left, miter, limits); err != .None {
			return err
		}

		return append_inner_bevel(right, vertex, -nin, -nout, half, limits)
	}

	if join == .Round {
		start_angle := math.atan2(outer_n0.y, outer_n0.x)
		end_angle := math.atan2(outer_n1.y, outer_n1.x)
		sweep := end_angle - start_angle
		// Take the shorter arc between outer normals — that is the exterior join.
		for sweep <= -math.PI {
			sweep += 2 * math.PI
		}

		for sweep > math.PI {
			sweep -= 2 * math.PI
		}

		outer := turning_left ? right : left
		if err := push(outer, vertex + outer_n0 * half, limits); err != .None {
			return err
		}

		steps := stroke_arc_steps(half, sweep, tolerance)
		for step in 1 ..< steps {
			angle := start_angle + sweep * f64(step) / f64(steps)
			offset := Point{math.cos(angle), math.sin(angle)} * half
			if err := push(outer, vertex + offset, limits); err != .None {
				return err
			}
		}

		if err := push(outer, vertex + outer_n1 * half, limits); err != .None {
			return err
		}

		if turning_left {
			return append_inner_bevel(left, vertex, nin, nout, half, limits)
		}

		return append_inner_bevel(right, vertex, -nin, -nout, half, limits)
	}

	// Bevel (and miter-limit fallback): connect both outer and inner offsets.
	if err := push(left, vertex + nin * half, limits); err != .None {
		return err
	}

	if err := push(left, vertex + nout * half, limits); err != .None {
		return err
	}

	if err := push(right, vertex - nin * half, limits); err != .None {
		return err
	}

	return push(right, vertex - nout * half, limits)
}

@(private)
stroke_cap_points :: proc(
	outline: ^Path,
	point, tangent: Point,
	cap: Line_Cap,
	half: f64,
	stroke: Stroke,
	transform: Affine,
	at_end: bool,
	tolerance: f64,
	limits: Limits,
) -> Error {
	if tangent == (Point{}) {
		return .None
	}

	dir := at_end ? tangent : -tangent
	normal := stroke_perp(tangent)
	switch cap {
	case .Butt:
		return .None
	case .Square:
		out := point + dir * half
		a := stroke_map(out + normal * half, stroke, transform)
		b := stroke_map(out - normal * half, stroke, transform)
		if at_end {
			if err := stroke_line_to(outline, a, limits); err != .None {
				return err
			}

			return stroke_line_to(outline, b, limits)
		}

		if err := stroke_line_to(outline, b, limits); err != .None {
			return err
		}

		return stroke_line_to(outline, a, limits)
	case .Round:
		start_n := at_end ? normal : -normal
		start_angle := math.atan2(start_n.y, start_n.x)
		sweep := -math.PI
		steps := stroke_arc_steps(half, sweep, tolerance)
		for step in 1 ..= steps {
			angle := start_angle + sweep * f64(step) / f64(steps)
			p := stroke_map(point + Point{math.cos(angle), math.sin(angle)} * half, stroke, transform)
			if err := stroke_line_to(outline, p, limits); err != .None {
				return err
			}
		}

		return .None
	}

	return .None
}

@(private)
stroke_point_cap :: proc(
	outline: ^Path,
	point: Point,
	cap: Line_Cap,
	half: f64,
	stroke: Stroke,
	transform: Affine,
	limits: Limits,
) -> Error {
	arc_tol := stroke_arc_tolerance(stroke, transform, limits)
	switch cap {
	case .Butt:
		return .None
	case .Square:
		corners := [4]Point{
			point + {-half, -half},
			point + {half, -half},
			point + {half, half},
			point + {-half, half},
		}
		before := len(outline.commands)
		if err := stroke_move_to(outline, stroke_map(corners[0], stroke, transform), limits); err != .None {
			resize(&outline.commands, before)

			return err
		}

		for corner in corners[1:] {
			if err := stroke_line_to(outline, stroke_map(corner, stroke, transform), limits); err != .None {
				resize(&outline.commands, before)

				return err
			}
		}

		if err := stroke_close(outline, limits); err != .None {
			resize(&outline.commands, before)

			return err
		}

		return .None
	case .Round:
		before := len(outline.commands)
		steps := stroke_arc_steps(half, 2 * math.PI, arc_tol)
		for i in 0 ..= steps {
			angle := f64(i) * 2 * math.PI / f64(steps)
			p := stroke_map(point + Point{math.cos(angle), math.sin(angle)} * half, stroke, transform)
			if i == 0 {
				if err := stroke_move_to(outline, p, limits); err != .None {
					resize(&outline.commands, before)

					return err
				}
			} else {
				if err := stroke_line_to(outline, p, limits); err != .None {
					resize(&outline.commands, before)

					return err
				}
			}
		}

		if err := stroke_close(outline, limits); err != .None {
			resize(&outline.commands, before)

			return err
		}

		return .None
	}

	return .None
}
