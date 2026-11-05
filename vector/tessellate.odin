package oni_vector

import "core:math"
import "core:mem"
import "core:slice"

@(private)
Rational :: struct {
	num, den: i128,
}

@(private)
Integer_Point :: [2]i64

@(private)
Edge :: struct {
	a, b: Integer_Point,
	winding: int,
	operand: int,
}

@(private)
Crossing :: struct {
	x: Rational,
	edge: int,
}

Build_Usage :: struct {
	flattened_segments, triangles: int,
	pair_tests, exact_ops: int,
	// True when this build used stable uniform remesh or reposition so the
	// engine can keep forcing uniform subdivision on the next morph update.
	stable_remesh: bool,
}

@(private)
edge_before :: proc(a, b: Edge) -> bool {
	amin, bmin := min(a.a.y, a.b.y), min(b.a.y, b.b.y)
	if amin != bmin {
		return amin < bmin
	}
	if a.a.x != b.a.x {
		return a.a.x < b.a.x
	}
	if a.a.y != b.a.y {
		return a.a.y < b.a.y
	}
	if a.b.x != b.b.x {
		return a.b.x < b.b.x
	}
	return a.b.y < b.b.y
}

@(private)
edge_before_with_budget :: proc(a, b: Edge, data: rawptr) -> bool {
	budget := cast(^Sort_Context)data
	budget.remaining -= 1
	if budget.remaining < 0 { budget.err = .Limit_Exceeded; return false }
	return edge_before(a, b)
}

@(private)
mesh_reserve :: proc(mesh: ^Mesh, vertices, indices: int, limits: Limits) -> Error {
	vertex_capacity := max(cap(mesh.vertices), vertices)
	index_capacity := max(cap(mesh.indices), indices)
	if vertex_capacity > limits.max_mesh_bytes / size_of([2]f32) ||
	   index_capacity > (limits.max_mesh_bytes - vertex_capacity * size_of([2]f32)) / size_of(u32) {
		return .Mesh_Memory_Limit
	}
	if vertex_capacity == cap(mesh.vertices) && index_capacity == cap(mesh.indices) { return .None }
	// Grow geometrically when the budget permits, otherwise reserve exactly.
	grown_vertices := vertices > cap(mesh.vertices) ? max(vertex_capacity, cap(mesh.vertices) * 2) : vertex_capacity
	grown_indices := indices > cap(mesh.indices) ? max(index_capacity, cap(mesh.indices) * 2) : index_capacity
	if grown_vertices <= limits.max_mesh_bytes / size_of([2]f32) &&
	   grown_indices <= (limits.max_mesh_bytes - grown_vertices * size_of([2]f32)) / size_of(u32) {
		vertex_capacity, index_capacity = grown_vertices, grown_indices
	}
	if reserve(&mesh.vertices, vertex_capacity) != nil || reserve(&mesh.indices, index_capacity) != nil {
		return .Allocation_Failed
	}
	return .None
}

@(private)
Sort_Context :: struct {
	err: Error,
	remaining: int,
	exact: ^Exact_Work,
}

@(private)
rational_compare :: proc(a, b: Rational, work: ^Exact_Work = nil) -> (order: int, err: Error) {
	if !exact_charge(work, 4) { return 0, .Limit_Exceeded }
	if a.den <= 0 || b.den <= 0 {
		return 0, .Invalid_Value
	}
	if a.den == b.den {
		return a.num < b.num ? -1 : (a.num > b.num ? 1 : 0), .None
	}
	// Ordinary icon coordinates fit this exact, division-free filter. Larger
	// arrangements retain the checked wide-integer and bounded big-int paths.
	SMALL :: i128(1) << 62
	if abs(a.num) < SMALL && abs(b.num) < SMALL && a.den < SMALL && b.den < SMALL {
		l, r := a.num * b.den, b.num * a.den
		return l < r ? -1 : (l > r ? 1 : 0), .None
	}
	left := f64(a.num) / f64(a.den)
	right := f64(b.num) / f64(b.den)
	error_bound := max(abs(left), abs(right)) * (32 * 2.220446049250313e-16)
	if abs(left - right) > error_bound {
		return left < right ? -1 : 1, .None
	}
	MAX_INTEGER :: (i128(1) << 126) - 1 + (i128(1) << 126)
	if abs(a.num) <= MAX_INTEGER / b.den && abs(b.num) <= MAX_INTEGER / a.den {
		l := a.num * b.den
		r := b.num * a.den
		return l < r ? -1 : (l > r ? 1 : 0), .None
	}
	return exact_compare_products(a.num, b.den, b.num, a.den, work)
}

@(private)
event_before :: proc(a, b: Rational, data: rawptr) -> bool {
	context_data := cast(^Sort_Context)data
	if context_data.err != .None {
		return false
	}
	context_data.remaining -= 1
	if context_data.remaining < 0 {
		context_data.err = .Limit_Exceeded
		return false
	}
	order, err := rational_compare(a, b, context_data.exact)
	context_data.err = err
	return order < 0
}

@(private)
crossing_before :: proc(a, b: Crossing, data: rawptr) -> bool {
	context_data := cast(^Sort_Context)data
	if context_data.err != .None {
		return false
	}
	context_data.remaining -= 1
	if context_data.remaining < 0 {
		context_data.err = .Limit_Exceeded
		return false
	}
	order, err := rational_compare(a.x, b.x, context_data.exact)
	context_data.err = err
	if order == 0 {
		return a.edge < b.edge
	}
	return order < 0
}

// Small sweep lists dominate icon tessellation. Insertion sorting avoids the
// generic sorter and comparator calls; large arrangements keep O(n log n).
@(private)
sort_events :: proc(events: []Rational, budget: ^Sort_Context) {
	if len(events) > 128 {
		slice.sort_by_with_data(events, event_before, budget)
		return
	}
	for i in 1 ..< len(events) {
		value := events[i]
		j := i
		for j > 0 && #force_inline event_before(value, events[j - 1], budget) {
			events[j] = events[j - 1]
			j -= 1
		}
		events[j] = value
		if budget.err != .None { return }
	}
}

@(private)
sort_crossings :: proc(crossings: []Crossing, budget: ^Sort_Context) {
	if len(crossings) > 16 {
		slice.sort_by_with_data(crossings, crossing_before, budget)
		return
	}
	for i in 1 ..< len(crossings) {
		value := crossings[i]
		j := i
		for j > 0 && #force_inline crossing_before(value, crossings[j - 1], budget) {
			crossings[j] = crossings[j - 1]
			j -= 1
		}
		crossings[j] = value
		if budget.err != .None { return }
	}
}

@(private)
integer_cross :: proc(a, b: Integer_Point) -> i128 {
	if max(abs(a.x), abs(a.y), abs(b.x), abs(b.y)) <= 1 << 30 {
		return i128(a.x * b.y - a.y * b.x)
	}
	return i128(a.x) * i128(b.y) - i128(a.y) * i128(b.x)
}

@(private)
make_rational :: proc(num, den: i128, work: ^Exact_Work = nil) -> Rational {
	n, d := num, den
	if d < 0 {
		n, d = -n, -d
	}
	if d == 1 { return {num = n, den = d} }
	a, b := abs(n), d
	for b != 0 {
		if !exact_charge(work, 8) { return {den = 1} }
		a, b = b, a % b
	}
	if a > 0 {
		n /= a
		d /= a
	}
	return {num = n, den = d}
}

@(private)
edge_x :: proc(edge: Edge, y: Rational) -> Rational {
	dx := i128(edge.b.x - edge.a.x)
	dy := i128(edge.b.y - edge.a.y)
	// Crossings are compared exactly without requiring canonical reduction.
	// With quantized coordinates bounded by 2^30, even intersection-height
	// mediants keep these products below 2^127. Only event identities need GCD.
	n := i128(edge.a.x) * y.den * dy + dx * (y.num - i128(edge.a.y) * y.den)
	d := y.den * dy
	return d < 0 ? Rational{num = -n, den = -d} : Rational{num = n, den = d}
}

@(private)
rational_value :: proc(value: Rational) -> f64 {
	return f64(value.num) / f64(value.den) / 1024
}

@(private)
emit_trapezoid :: proc(mesh: ^Mesh, left, right: Edge, low, high: Rational, limits: Limits, work: ^Exact_Work) -> Error {
	if !exact_charge(work, 64) { return .Limit_Exceeded }
	l0, r0 := edge_x(left, low), edge_x(right, low)
	l1, r1 := edge_x(left, high), edge_x(right, high)
	bottom_order, err := rational_compare(l0, r0, work)
	if err != .None {
		return err
	}
	top_order, top_error := rational_compare(l1, r1, work)
	if top_error != .None {
		return top_error
	}
	triangles := int(bottom_order != 0) + int(top_order != 0)
	if triangles == 0 {
		return .None
	}
	if len(mesh.indices) / 3 + triangles > limits.max_triangles {
		return .Limit_Exceeded
	}
	base := u32(len(mesh.vertices))
	if reserve_error := mesh_reserve(mesh, len(mesh.vertices) + 4, len(mesh.indices) + triangles * 3, limits); reserve_error != .None {
		return reserve_error
	}
	if _, allocation_error := append(&mesh.vertices,
		[2]f32{f32(rational_value(l0)), f32(rational_value(low))},
		[2]f32{f32(rational_value(r0)), f32(rational_value(low))},
		[2]f32{f32(rational_value(r1)), f32(rational_value(high))},
		[2]f32{f32(rational_value(l1)), f32(rational_value(high))},
	); allocation_error != nil {
		return .Allocation_Failed
	}
	if bottom_order != 0 {
		if _, allocation_error := append(&mesh.indices, base, base + 1, base + 2); allocation_error != nil {
			return .Allocation_Failed
		}
	}
	if top_order != 0 {
		if _, allocation_error := append(&mesh.indices, base, base + 2, base + 3); allocation_error != nil {
			return .Allocation_Failed
		}
	}
	return .None
}

// Tessellate splits the arrangement at every vertex and intersection height.
// Winding is constant within each resulting strip; its filled intervals become
// disjoint trapezoids. Exact event comparisons keep coincident edges consistent.
Tessellate :: proc(commands: []Command, transform: Affine, rule: Fill_Rule, limits := DEFAULT_LIMITS, scratch_allocator: mem.Allocator = {}) -> (mesh: Mesh, err: Error) {
	err = Tessellate_Into(&mesh, commands, transform, rule, limits, scratch_allocator)
	if err != .None {
		Destroy_Mesh(&mesh)
	}
	return mesh, err
}

// Reuses output capacity. Supplied scratch must support bulk release by its
// caller; no scratch allocation is retained in the returned mesh.
Tessellate_Into :: proc(mesh: ^Mesh, commands: []Command, transform: Affine, rule: Fill_Rule, limits := DEFAULT_LIMITS, scratch_allocator: mem.Allocator = {}, usage: ^Build_Usage = nil) -> Error {
	if mesh == nil { return .Invalid_Path }
	if usage != nil {
		usage^ = {}
	}
	if rule < .Nonzero || rule > .Even_Odd || limits.max_mesh_bytes < 0 || limits.max_work < 0 ||
	   limits.max_triangles < 0 || limits.max_events < 0 || limits.max_intersections < 0 || limits.max_pair_tests < 0 ||
	   limits.max_exact_ops < 0 || limits.max_integer_bits <= 0 || limits.max_integer_bits > 4096 {
		clear(&mesh.vertices)
		clear(&mesh.indices)
		return .Invalid_Value
	}
	if mesh.contour_slots && limits.uniform_subdivision < 0 && len(mesh.indices) > 0 {
		work := Exact_Work{allowed = limits.max_exact_ops, width = limits.max_integer_bits}
		charged := exact_charge(&work, 1)
		ok, err := false, Error.Limit_Exceeded
		if charged { ok, err = mesh_reposition_from_endpoint_commands(commands, transform, mesh, &work, limits) }
		if ok || !charged {
			if usage != nil {
				usage^ = {triangles = len(mesh.indices) / 3, flattened_segments = len(mesh.vertices), exact_ops = work.used, stable_remesh = err == .None}
			}
			if err != .None { clear(&mesh.vertices); clear(&mesh.indices); mesh.contour_slots = false }
			return err
		}
	}
	arena := Scratch_Arena{backing = context.allocator}
	scratch := scratch_allocator
	if scratch.procedure == nil {
		scratch = {procedure = scratch_allocator_proc, data = &arena}
	}
	defer if scratch_allocator.procedure == nil {
		scratch_arena_destroy(&arena)
	}
	// Keep prior vertices/indices so compatible morph remesh can reposition.
	output, err := tessellate_impl(commands, transform, rule, limits, mesh^, scratch, usage)
	mesh^ = output
	if usage != nil {
		usage.triangles = len(mesh.indices) / 3
	}
	if err != .None {
		clear(&mesh.vertices)
		clear(&mesh.indices)
	}
	return err
}

@(private)
flatten_scratch :: proc(commands: []Command, transform: Affine, limits: Limits, allocator: mem.Allocator) -> (Flat_Path, Error) {
	context.allocator = allocator
	return flatten_impl(commands, transform, limits)
}

@(private)
convex_mesh :: proc(flat: Flat_Path, mesh: ^Mesh, limits: Limits, work: ^Exact_Work) -> (convex: bool, err: Error) {
	if len(flat.contours) != 1 {
		return false, .None
	}
	points := flat.points[:]
	if len(points) > 1 && points[0] == points[len(points) - 1] {
		points = points[:len(points) - 1]
	}
	if len(points) < 3 || len(points) > 512 {
		return false, .None
	}
	winding := i128(0)
	first_x, last_x, first_y, last_y := 0, 0, 0, 0
	x_reversals, y_reversals := 0, 0
	for point, i in points {
		if !exact_charge(work, 8) { return true, .Limit_Exceeded }
		a := Integer_Point{i64(point.x * 1024), i64(point.y * 1024)}
		next := points[(i + 1) % len(points)]
		after := points[(i + 2) % len(points)]
		b := Integer_Point{i64(next.x * 1024), i64(next.y * 1024)}
		c := Integer_Point{i64(after.x * 1024), i64(after.y * 1024)}
		u, v := b - a, c - b
		if u.x == 0 && u.y == 0 {
			return false, .None
		}
		turn := integer_cross(u, v)
		if turn != 0 {
			if winding != 0 && (turn < 0) != (winding < 0) {
				return false, .None
			}
			winding = turn
		} else if i128(u.x) * i128(v.x) + i128(u.y) * i128(v.y) < 0 {
			return false, .None
		}
		x_direction := u.x < 0 ? -1 : (u.x > 0 ? 1 : 0)
		y_direction := u.y < 0 ? -1 : (u.y > 0 ? 1 : 0)
		if x_direction != 0 {
			if first_x == 0 {
				first_x = x_direction
			} else if last_x != x_direction {
				x_reversals += 1
			}
			last_x = x_direction
		}
		if y_direction != 0 {
			if first_y == 0 {
				first_y = y_direction
			} else if last_y != y_direction {
				y_reversals += 1
			}
			last_y = y_direction
		}
	}
	x_reversals += int(first_x != last_x)
	y_reversals += int(first_y != last_y)
	// Consistent local turns alone admit stars. A convex boundary also makes
	// exactly one ascent/descent per axis; extra revolutions fail this check.
	if x_reversals > 2 || y_reversals > 2 {
		return false, .None
	}
	if len(points) - 2 > limits.max_triangles {
		return true, .Limit_Exceeded
	}
	if reserve_error := mesh_reserve(mesh, len(points), (len(points) - 2) * 3, limits); reserve_error != .None {
		return true, reserve_error
	}
	resize(&mesh.vertices, len(points))
	resize(&mesh.indices, (len(points) - 2) * 3)
	for point, i in points {
		mesh.vertices[i] = {f32(point.x), f32(point.y)}
	}
	index_count := 0
	for i in 1 ..< len(points) - 1 {
		if !exact_charge(work, 8) { return true, .Limit_Exceeded }
		a, b, c := points[0], points[i], points[i + 1]
		u := Integer_Point{i64((b.x - a.x) * 1024), i64((b.y - a.y) * 1024)}
		v := Integer_Point{i64((c.x - a.x) * 1024), i64((c.y - a.y) * 1024)}
		if integer_cross(u, v) != 0 {
			mesh.indices[index_count + 0] = 0
			mesh.indices[index_count + 1] = u32(i)
			mesh.indices[index_count + 2] = u32(i + 1)
			index_count += 3
		}
	}
	resize(&mesh.indices, index_count)
	return true, .None
}

@(private)
tessellate_impl :: proc(commands: []Command, transform: Affine, rule: Fill_Rule, limits: Limits, output: Mesh, scratch: mem.Allocator, usage: ^Build_Usage, clip_commands: []Command = nil) -> (mesh: Mesh, err: Error) {
	mesh = output
	work := Exact_Work{allowed = limits.max_exact_ops, width = limits.max_integer_bits}
	pair_tests := 0
	commit_usage := true
	defer if usage != nil && commit_usage {
		usage.pair_tests = pair_tests
		usage.exact_ops = work.used
	}
	if !exact_charge(&work, 1) { return mesh, .Limit_Exceeded }
	intersection := len(clip_commands) > 0
	simple_work := 0
	flat, flatten_error := flatten_scratch(commands, transform, limits, scratch)
	if usage != nil {
		usage.flattened_segments = len(flat.points)
	}
	if flatten_error != .None {
		return mesh, flatten_error
	}
	operand_start := len(flat.points)
	if intersection {
		other_limits := limits
		other_limits.max_flattened_segments -= len(flat.points)
		other, other_error := flatten_scratch(clip_commands, transform, other_limits, scratch)
		if usage != nil { usage.flattened_segments += len(other.points) }
		if other_error != .None { return mesh, other_error }
		if _, allocation_error := append(&flat.points, ..other.points[:]); allocation_error != nil { return mesh, .Allocation_Failed }
		for contour in other.contours {
			adjusted := contour
			adjusted.first += operand_start
			if _, allocation_error := append(&flat.contours, adjusted); allocation_error != nil { return mesh, .Allocation_Failed }
		}
	}
	if !intersection {
		if mesh.contour_slots && len(mesh.indices) > 0 {
			if ok, reposition_error := mesh_reposition_from_flat(flat, &mesh, &work); ok {
				if usage != nil {
					usage.triangles = len(mesh.indices) / 3
					usage.stable_remesh = true
				}
				return mesh, reposition_error
			}
		}
		clear(&mesh.vertices)
		clear(&mesh.indices)
		mesh.contour_slots = false
		if limits.uniform_subdivision != 0 {
			if stable, stable_error := stable_contour_mesh(flat, &mesh, limits, &pair_tests, &simple_work, &work); stable {
				mesh.contour_slots = stable_error == .None
				if usage != nil {
					usage.stable_remesh = true
				}
				return mesh, stable_error
			}
			if handled, ring_error := stable_ring_mesh(flat, &mesh, rule, limits, &pair_tests, &work); handled {
				mesh.contour_slots = ring_error == .None
				if usage != nil {
					usage.stable_remesh = true
				}
				return mesh, ring_error
			}
			// Convex close-strip layout matches mesh_reposition_from_flat.
			if convex, convex_error := convex_mesh(flat, &mesh, limits, &work); convex {
				if usage != nil {
					usage.stable_remesh = true
				}
				return mesh, convex_error
			}
			// Self-intersecting morphs (figure-8): keep the forced flatten and
			// fall through to sweep — cheaper than adaptive re-flatten.
		}
		if convex, convex_error := convex_mesh(flat, &mesh, limits, &work); convex {
			return mesh, convex_error
		}
		if handled, ring_error := ring_mesh(flat, &mesh, rule, limits, &pair_tests, &work); handled {
			return mesh, ring_error
		}
		if simple, simple_error := simple_mesh(flat, &mesh, limits, &pair_tests, &simple_work, &work); simple {
			mesh.contour_slots = simple_error == .None && limits.uniform_subdivision != 0 && mesh_matches_contour_slots(flat, mesh)
			return mesh, simple_error
		}
		if handled, split_error := split_mesh(flat, &mesh, limits, &pair_tests, &simple_work, &work, scratch); handled {
			mesh.contour_slots = split_error == .None && limits.uniform_subdivision != 0 && mesh_matches_contour_slots(flat, mesh)
			return mesh, split_error
		}
	} else {
		clear(&mesh.vertices)
		clear(&mesh.indices)
		mesh.contour_slots = false
	}
	edges: [dynamic]Edge
	events: [dynamic]Rational
	crossings: [dynamic]Crossing
	edges.allocator = scratch
	events.allocator = scratch
	crossings.allocator = scratch
	for contour in flat.contours {
		if contour.count < 2 {
			continue
		}
		for i in 0 ..< contour.count {
			a := flat.points[contour.first + i]
			b := flat.points[contour.first + (i + 1) % contour.count]
			if a.y == b.y {
				continue
			}
			edge := Edge{
				a = {i64(math.round(a.x * 1024)), i64(math.round(a.y * 1024))},
				b = {i64(math.round(b.x * 1024)), i64(math.round(b.y * 1024))},
				winding = a.y < b.y ? 1 : -1,
				operand = intersection && contour.first >= operand_start ? 1 : 0,
			}
			if len(events) + 2 > limits.max_events {
				return mesh, .Limit_Exceeded
			}
			if _, allocation_error := append(&edges, edge); allocation_error != nil {
				return mesh, .Allocation_Failed
			}
			if _, allocation_error := append(&events, Rational{num = i128(edge.a.y), den = 1}, Rational{num = i128(edge.b.y), den = 1}); allocation_error != nil {
				return mesh, .Allocation_Failed
			}
		}
	}
	sort_context := Sort_Context{remaining = limits.max_work - simple_work, exact = &work}
	slice.sort_by_with_data(edges[:], edge_before_with_budget, &sort_context)
	if sort_context.err != .None { return mesh, sort_context.err }
	intersections := 0
	for a, i in edges {
		for j in i + 1 ..< len(edges) {
			b := edges[j]
			if min(b.a.y, b.b.y) > max(a.a.y, a.b.y) {
				break
			}
			pair_tests += 1
			if pair_tests > limits.max_pair_tests {
				return mesh, .Limit_Exceeded
			}
			if max(a.a.x, a.b.x) < min(b.a.x, b.b.x) || max(b.a.x, b.b.x) < min(a.a.x, a.b.x) ||
			   max(a.a.y, a.b.y) < min(b.a.y, b.b.y) || max(b.a.y, b.b.y) < min(a.a.y, a.b.y) {
				continue
			}
			if !exact_charge(&work, 48) { return mesh, .Limit_Exceeded }
			r := a.b - a.a
			s := b.b - b.a
			q := b.a - a.a
			den := integer_cross(r, s)
			tnum, unum := integer_cross(q, s), integer_cross(q, r)
			if den < 0 {
				den, tnum, unum = -den, -tnum, -unum
			}
			if den == 0 || tnum <= 0 || tnum >= den || unum <= 0 || unum >= den {
				continue
			}
			intersections += 1
			if intersections > limits.max_intersections || len(events) >= limits.max_events {
				return mesh, .Limit_Exceeded
			}
			event := make_rational(i128(a.a.y) * den + i128(r.y) * tnum, den, &work)
			if work.err != .None { return mesh, work.err }
			if _, allocation_error := append(&events, event); allocation_error != nil {
				return mesh, .Allocation_Failed
			}
		}
	}
	sort_events(events[:], &sort_context)
	if sort_context.err != .None {
		return mesh, sort_context.err
	}
	unique := 0
	for event in events {
		if unique > 0 {
			order, comparison_error := rational_compare(events[unique - 1], event, &work)
			if comparison_error != .None {
				return mesh, comparison_error
			}
			if order == 0 {
				continue
			}
		}
		events[unique] = event
		unique += 1
	}
	resize(&events, unique)
	active, active_allocation_error := make([dynamic]int, 0, len(edges), scratch)
	if active_allocation_error != nil {
		return mesh, .Allocation_Failed
	}
	next_edge := 0
	for strip := 1; strip < unique; strip += 1 {
		low, high := events[strip - 1], events[strip]
		if !exact_charge(&work, 8) { return mesh, .Limit_Exceeded }
		middle := make_rational(low.num + high.num, low.den + high.den, &work)
		if work.err != .None { return mesh, work.err }
		clear(&crossings)
		for next_edge < len(edges) {
			below, comparison_error := rational_compare(Rational{num = i128(min(edges[next_edge].a.y, edges[next_edge].b.y)), den = 1}, middle, &work)
			if comparison_error != .None {
				return mesh, comparison_error
			}
			if below >= 0 {
				break
			}
			if _, allocation_error := append(&active, next_edge); allocation_error != nil {
				return mesh, .Allocation_Failed
			}
			next_edge += 1
		}
		active_count := 0
		for i in active {
			edge := edges[i]
			sort_context.remaining -= 1
			if sort_context.remaining < 0 {
				return mesh, .Limit_Exceeded
			}
			min_y := Rational{num = i128(min(edge.a.y, edge.b.y)), den = 1}
			max_y := Rational{num = i128(max(edge.a.y, edge.b.y)), den = 1}
			above, above_error := rational_compare(middle, min_y, &work)
			below, below_error := rational_compare(middle, max_y, &work)
			if above_error != .None || below_error != .None {
				return mesh, above_error != .None ? above_error : below_error
			}
			if above <= 0 || below >= 0 {
				continue
			}
			active[active_count] = i
			active_count += 1
			if !exact_charge(&work, 16) { return mesh, .Limit_Exceeded }
			if _, allocation_error := append(&crossings, Crossing{x = edge_x(edge, middle), edge = i}); allocation_error != nil {
				return mesh, .Allocation_Failed
			}
		}
		resize(&active, active_count)
		sort_crossings(crossings[:], &sort_context)
		if sort_context.err != .None {
			return mesh, sort_context.err
		}
		winding: [2]int
		previous := -1
		cursor := 0
		for cursor < len(crossings) {
			crossing := crossings[cursor]
			inside := rule == .Nonzero ? winding[0] != 0 : winding[0] & 1 != 0
			if intersection { inside = inside && winding[1] != 0 }
			if inside && previous >= 0 {
				if emit_error := emit_trapezoid(&mesh, edges[previous], edges[crossing.edge], low, high, limits, &work); emit_error != .None {
					return mesh, emit_error
				}
			}
			previous = crossing.edge
			for cursor < len(crossings) {
				order, comparison_error := rational_compare(crossing.x, crossings[cursor].x, &work)
				if comparison_error != .None {
					return mesh, comparison_error
				}
				if order != 0 {
					break
				}
				edge := edges[crossings[cursor].edge]
				winding[edge.operand] += edge.winding
				cursor += 1
			}
		}
	}
	return
}
