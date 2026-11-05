package oni_vector

import "base:intrinsics"

// Call after the coordinate-limit check: scaled coordinates fit signed i32.
@(private)
quantize_endpoint :: #force_inline proc(point: Point) -> Integer_Point {
	scaled := transmute(#simd[2]f64)point * 1024
	whole := cast(#simd[2]i32)scaled
	fraction := scaled - cast(#simd[2]f64)whole
	half: #simd[2]f64 = .5
	whole += cast(#simd[2]i32)intrinsics.simd_lanes_ge(fraction, half) & 1
	whole -= cast(#simd[2]i32)intrinsics.simd_lanes_le(fraction, -half) & 1
	values := transmute([2]i32)whole
	return {i64(values[0]), i64(values[1])}
}

#assert(offset_of(Command, radii) == offset_of(Command, points) + size_of([3]Point))

@(private)
cubic_identity_coordinates_valid :: #force_inline proc(command: ^Command, max_coordinate: f64) -> bool {
	bits := intrinsics.unaligned_load(cast(^#simd[8]u64)&command.points)
	abs_values := transmute(#simd[8]f64)(bits & 0x7fffffffffffffff)
	bounds := #simd[8]f64{max_coordinate, max_coordinate, max_coordinate, max_coordinate,
		max_coordinate, max_coordinate, max(f64), max(f64)}
	return intrinsics.simd_reduce_and(intrinsics.simd_lanes_le(abs_values, bounds)) != 0 && finite(command.rotation)
}

@(private)
orientation :: proc(a, b, c: Integer_Point) -> i128 {
	return integer_cross(b - a, c - a)
}

// Contour points with only closing duplicates stripped (no mid-path dedup).
// Uniform morph remesh needs fixed vertex slot counts across frames.
@(private)
flat_contour_points_stable :: proc(flat: Flat_Path, storage: []Integer_Point) -> (count: int, ok: bool) {
	if len(flat.contours) == 0 || len(flat.points) == 0 {
		return 0, false
	}
	count = 0
	for contour in flat.contours {
		if contour.count < 3 {
			return 0, false
		}
		start := count
		for point in flat.points[contour.first:][:contour.count] {
			if count >= len(storage) {
				return 0, false
			}
			storage[count] = Integer_Point{i64(point.x * 1024), i64(point.y * 1024)}
			count += 1
		}
		// Strip only trailing copies of the start point (close duplicates).
		// Avoid mid-path dedup so morph remesh keeps a stable vertex count.
		for count > start + 1 && storage[count - 1] == storage[start] {
			count -= 1
		}
		if count - start < 3 {
			return 0, false
		}
	}
	return count, true
}

@(private)
mesh_matches_contour_slots :: proc(flat: Flat_Path, mesh: Mesh) -> bool {
	storage: [512]Integer_Point = ---
	count, ok := flat_contour_points_stable(flat, storage[:])
	if !ok || count != len(mesh.vertices) { return false }
	for point, i in storage[:count] {
		if mesh.vertices[i] != ([2]f32{f32(point.x) / 1024, f32(point.y) / 1024}) { return false }
	}
	return true
}

@(private)
mesh_reposition_orientation_ok :: proc(#by_ptr mesh: Mesh, points: []Integer_Point) -> bool {
	if len(mesh.indices) % 3 != 0 { return false }
	for i := 0; i < len(mesh.indices); i += 3 {
		a, b, c := int(mesh.indices[i]), int(mesh.indices[i + 1]), int(mesh.indices[i + 2])
		if a >= len(points) || b >= len(points) || c >= len(points) ||
		   a >= len(mesh.vertices) || b >= len(mesh.vertices) || c >= len(mesh.vertices) { return false }
		pa, pb, pc := mesh.vertices[a], mesh.vertices[b], mesh.vertices[c]
		old_left := (f64(pb.x) - f64(pa.x)) * (f64(pc.y) - f64(pa.y))
		old_right := (f64(pb.y) - f64(pa.y)) * (f64(pc.x) - f64(pa.x))
		old_area := old_left - old_right
		// Quantization scales both axes by 1024, preserving the sign and the
		// relative error bound without per-triangle coordinate conversion.
		qa, qb, qc := points[a], points[b], points[c]
		next_left := (f64(qb.x) - f64(qa.x)) * (f64(qc.y) - f64(qa.y))
		next_right := (f64(qb.y) - f64(qa.y)) * (f64(qc.x) - f64(qa.x))
		next_area := next_left - next_right
		if !(abs(old_area) > (abs(old_left) + abs(old_right)) * 1e-14) ||
		   !(abs(next_area) > (abs(next_left) + abs(next_right)) * 1e-14) ||
		   (old_area < 0) != (next_area < 0) { return false }
	}
	return true
}

// Endpoint-uniform morph: sample Move / Cubic / Close ends in contour order
// (matching flatten_cubic with uniform_subdivision < 0) and rewrite verts.
@(private)
mesh_reposition_from_endpoint_commands :: proc(
	commands: []Command,
	transform: Affine,
	mesh: ^Mesh,
	work: ^Exact_Work,
	limits := DEFAULT_LIMITS,
) -> (ok: bool, err: Error) {
	if mesh == nil || len(mesh.indices) < 3 || len(mesh.vertices) < 3 {
		return false, .None
	}
	if limits.max_flattened_segments <= 0 || limits.max_subdivision <= 0 ||
	   limits.max_subdivision > DEFAULT_LIMITS.max_subdivision ||
	   !(flatten_tolerance(limits) > 0 && finite(limits.tolerance)) ||
	   !(limits.max_coordinate > 0 && limits.max_coordinate <= DEFAULT_LIMITS.max_coordinate) { return true, .Invalid_Value }
	if len(commands) > limits.max_commands || len(mesh.indices) / 3 > limits.max_triangles { return true, .Limit_Exceeded }
	if len(commands) > limits.max_flattened_segments { return false, .None }
	if reserve_error := mesh_reserve(mesh, len(mesh.vertices), len(mesh.indices), limits); reserve_error != .None { return true, reserve_error }
	for value in transform { if !finite(value) { return true, .Invalid_Value } }
	identity := transform == IDENTITY
	storage: [512]Integer_Point = ---
	count := 0
	contour_start := -1
	current, start := Point{}, Point{}
	have_contour := false
	for &command in commands {
		if command.kind < .Move || command.kind > .Close { return true, .Invalid_Path }
		if identity && command.kind == .Cubic {
			if !cubic_identity_coordinates_valid(&command, limits.max_coordinate) { return true, .Invalid_Value }
		} else {
			for point in command.points { if !finite(point.x) || !finite(point.y) { return true, .Invalid_Value } }
			if !finite(command.radii.x) || !finite(command.radii.y) || !finite(command.rotation) { return true, .Invalid_Value }
			point_count := command.kind == .Cubic ? 3 : command.kind == .Quadratic ? 2 : command.kind == .Close ? 0 : 1
			for source in command.points[:point_count] {
				point := source if identity else Transform_Point(transform, source)
				if !(abs(point.x) <= limits.max_coordinate && abs(point.y) <= limits.max_coordinate) { return true, .Invalid_Value }
			}
		}
		switch command.kind {
		case .Move:
			if have_contour {
				for count > contour_start + 1 && storage[count - 1] == storage[contour_start] {
					count -= 1
				}
				if count - contour_start < 3 {
					return false, .None
				}
			}
			p := command.points[0] if identity else Transform_Point(transform, command.points[0])
			ip := quantize_endpoint(p)
			if count >= len(storage) {
				return false, .None
			}
			contour_start = count
			storage[count] = ip
			count += 1
			current = command.points[0]
			start = current
			have_contour = true
		case .Line:
			if !have_contour {
				return false, .None
			}
			p := command.points[0] if identity else Transform_Point(transform, command.points[0])
			ip := quantize_endpoint(p)
			if count >= len(storage) {
				return false, .None
			}
			storage[count] = ip
			count += 1
			current = command.points[0]
		case .Quadratic:
			if !have_contour {
				return false, .None
			}
			p := command.points[1] if identity else Transform_Point(transform, command.points[1])
			ip := quantize_endpoint(p)
			if count >= len(storage) {
				return false, .None
			}
			storage[count] = ip
			count += 1
			current = command.points[1]
		case .Cubic:
			if !have_contour {
				return false, .None
			}
			p := command.points[2] if identity else Transform_Point(transform, command.points[2])
			ip := quantize_endpoint(p)
			if count >= len(storage) {
				return false, .None
			}
			storage[count] = ip
			count += 1
			current = command.points[2]
		case .Arc:
			return false, .None
		case .Close:
			if !have_contour {
				if count > 0 { continue }
				return false, .None
			}
			if current != start {
				p := start if identity else Transform_Point(transform, start)
				ip := quantize_endpoint(p)
				if count >= len(storage) {
					return false, .None
				}
				storage[count] = ip
				count += 1
			}
			for count > contour_start + 1 && storage[count - 1] == storage[contour_start] {
				count -= 1
			}
			if count - contour_start < 3 {
				return false, .None
			}
			current = start
			have_contour = false
			contour_start = -1
		}
	}
	if have_contour {
		for count > contour_start + 1 && storage[count - 1] == storage[contour_start] {
			count -= 1
		}
		if count - contour_start < 3 {
			return false, .None
		}
	}
	if count != len(mesh.vertices) {
		return false, .None
	}
	if !mesh_reposition_orientation_ok(mesh^, storage[:count]) { return false, .None }
	if !exact_charge(work, count) { return true, .Limit_Exceeded }
	for i in 0 ..< count {
		mesh.vertices[i] = {f32(storage[i].x) / 1024, f32(storage[i].y) / 1024}
	}
	return true, .None
}

// Compatible morph remesh: rewrite positions when the retained mesh used the
// same stable contour slots (uniform subdivision + close-strip only).
@(private)
mesh_reposition_from_flat :: proc(flat: Flat_Path, mesh: ^Mesh, work: ^Exact_Work) -> (ok: bool, err: Error) {
	if mesh == nil || len(mesh.indices) < 3 || len(mesh.vertices) < 3 {
		return false, .None
	}
	storage: [512]Integer_Point = ---
	count, have := flat_contour_points_stable(flat, storage[:])
	if !have {
		return false, .None
	}
	if count != len(mesh.vertices) {
		return false, .None
	}
	if !mesh_reposition_orientation_ok(mesh^, storage[:count]) { return false, .None }
	if !exact_charge(work, count) { return true, .Limit_Exceeded }
	for i in 0 ..< count {
		mesh.vertices[i] = {f32(storage[i].x) / 1024, f32(storage[i].y) / 1024}
	}
	return true, .None
}

@(private)
stable_earclip_contour :: proc(
	points: []Integer_Point,
	vertex_offset: int,
	mesh: ^Mesh,
	limits: Limits,
	work: ^int,
	exact: ^Exact_Work,
	index_count: ^int,
) -> (ok: bool, err: Error) {
	count := len(points)
	if count < 3 {
		return false, .None
	}
	area := i128(0)
	for i in 0 ..< count {
		if !exact_charge(exact, 8) {
			return true, .Limit_Exceeded
		}
		area += integer_cross(points[i], points[i + 1 == count ? 0 : i + 1])
	}
	if area == 0 {
		return false, .None
	}
	remaining: [512]int = ---
	for i in 0 ..< count {
		remaining[i] = i
	}
	active := count
	for active > 2 {
		found := false
		for i in 0 ..< active {
			if !exact_charge(exact, 8) {
				return true, .Limit_Exceeded
			}
			previous, current, next := remaining[i == 0 ? active - 1 : i - 1], remaining[i], remaining[i + 1 == active ? 0 : i + 1]
			a, b, c := points[previous], points[current], points[next]
			turn := orientation(a, b, c)
			if turn != 0 && (turn < 0) != (area < 0) {
				continue
			}
			blocked := false
			lo := Integer_Point{min(a.x, b.x, c.x), min(a.y, b.y, c.y)}
			hi := Integer_Point{max(a.x, b.x, c.x), max(a.y, b.y, c.y)}
			for j in 0 ..< active {
				work^ += 1
				if work^ > limits.max_work {
					return true, .Limit_Exceeded
				}
				index := remaining[j]
				if index == previous || index == current || index == next {
					continue
				}
				p := points[index]
				if p.x < lo.x || p.x > hi.x || p.y < lo.y || p.y > hi.y {
					continue
				}
				if !exact_charge(exact, 24) {
					return true, .Limit_Exceeded
				}
				x, y, z := orientation(a, b, p), orientation(b, c, p), orientation(c, a, p)
				if (x >= 0 && y >= 0 && z >= 0) || (x <= 0 && y <= 0 && z <= 0) {
					blocked = true
					break
				}
			}
			if blocked {
				continue
			}
			if turn != 0 {
				mesh.indices[index_count^ + 0] = u32(vertex_offset + previous)
				mesh.indices[index_count^ + 1] = u32(vertex_offset + current)
				mesh.indices[index_count^ + 2] = u32(vertex_offset + next)
				index_count^ += 3
			}
			for j in i ..< active - 1 {
				remaining[j] = remaining[j + 1]
			}
			active -= 1
			found = true
			break
		}
		if !found {
			return false, .None
		}
	}
	return true, .None
}

// Uniform-subdivision fill: keep every flattened sample (close-strip only) so
// subsequent compatible morph remeshes can reposition without retriangulating.
// Single-contour only — holes need the ring zipper (stable_ring_mesh).
@(private)
stable_contour_mesh :: proc(flat: Flat_Path, mesh: ^Mesh, limits: Limits, pair_tests, work: ^int, exact: ^Exact_Work) -> (ok: bool, err: Error) {
	_ = pair_tests
	if len(flat.contours) != 1 {
		return false, .None
	}
	storage: [512]Integer_Point = ---
	count, have := flat_contour_points_stable(flat, storage[:])
	if !have {
		return false, .None
	}
	if count - 2 > limits.max_triangles {
		return true, .Limit_Exceeded
	}
	if reserve_error := mesh_reserve(mesh, count, (count - 2) * 3, limits); reserve_error != .None {
		return true, reserve_error
	}
	resize(&mesh.vertices, count)
	resize(&mesh.indices, (count - 2) * 3)
	for i in 0 ..< count {
		mesh.vertices[i] = {f32(storage[i].x) / 1024, f32(storage[i].y) / 1024}
	}
	index_count := 0
	ok, err = stable_earclip_contour(storage[:count], 0, mesh, limits, work, exact, &index_count)
	if !ok || err != .None {
		clear(&mesh.vertices)
		clear(&mesh.indices)
		return ok, err
	}
	resize(&mesh.indices, index_count)
	return true, .None
}

@(private)
Simple_Edge :: struct {
	a, b, lo, hi: Integer_Point,
}

// Single simple contours admit exact ear clipping without constructing rational
// intersections. Any touching, crossing or overlapping nonadjacent edges fall
// back to the sweep arrangement, including stars and repeated boundaries.
@(private)
simple_mesh :: proc(flat: Flat_Path, mesh: ^Mesh, limits: Limits, pair_tests, work: ^int, exact: ^Exact_Work) -> (simple: bool, err: Error) {
	if len(flat.contours) != 1 || len(flat.points) > 512 { return false, .None }
	points: [512]Integer_Point = ---
	count := 0
	for point in flat.points {
		p := Integer_Point{i64(point.x * 1024), i64(point.y * 1024)}
		if count == 0 || points[count - 1] != p { points[count] = p; count += 1 }
	}
	if count > 1 && points[count - 1] == points[0] { count -= 1 }
	if count < 3 { return false, .None }
	edges: [512]Simple_Edge = ---
	for i in 0 ..< count {
		a, b := points[i], points[i + 1 == count ? 0 : i + 1]
		edges[i] = {a = a, b = b, lo = {min(a.x, b.x), min(a.y, b.y)}, hi = {max(a.x, b.x), max(a.y, b.y)}}
	}
	for i in 0 ..< count {
		a, b := edges[i].a, edges[i].b
		lo, hi := edges[i].lo, edges[i].hi
		for j in i + 1 ..< count {
			if j == i + 1 || (i == 0 && j == count - 1) { continue }
			pair_tests^ += 1
			if pair_tests^ > limits.max_pair_tests { return true, .Limit_Exceeded }
			if hi.x < edges[j].lo.x || edges[j].hi.x < lo.x || hi.y < edges[j].lo.y || edges[j].hi.y < lo.y { continue }
			if !exact_charge(exact, 32) { return true, .Limit_Exceeded }
			c, d := edges[j].a, edges[j].b
			x, y := orientation(a, b, c), orientation(a, b, d)
			u, w := orientation(c, d, a), orientation(c, d, b)
			if (x == 0 || y == 0 || (x < 0) != (y < 0)) && (u == 0 || w == 0 || (u < 0) != (w < 0)) {
				return false, .None
			}
		}
	}
	area := i128(0)
	for i in 0 ..< count {
		if !exact_charge(exact, 8) { return true, .Limit_Exceeded }
		area += integer_cross(points[i], points[i + 1 == count ? 0 : i + 1])
	}
	if area == 0 { return false, .None }
	if count - 2 > limits.max_triangles { return true, .Limit_Exceeded }
	if reserve_error := mesh_reserve(mesh, count, (count - 2) * 3, limits); reserve_error != .None { return true, reserve_error }
	remaining: [512]int = ---
	resize(&mesh.vertices, count)
	resize(&mesh.indices, (count - 2) * 3)
	for i in 0 ..< count {
		remaining[i] = i
		mesh.vertices[i] = {f32(points[i].x) / 1024, f32(points[i].y) / 1024}
	}
	index_count := 0
	active := count
	for active > 2 {
		found := false
		for i in 0 ..< active {
			if !exact_charge(exact, 8) { return true, .Limit_Exceeded }
			previous, current, next := remaining[i == 0 ? active - 1 : i - 1], remaining[i], remaining[i + 1 == active ? 0 : i + 1]
			a, b, c := points[previous], points[current], points[next]
			turn := orientation(a, b, c)
			if turn != 0 && (turn < 0) != (area < 0) { continue }
			blocked := false
			lo := Integer_Point{min(a.x, b.x, c.x), min(a.y, b.y, c.y)}
			hi := Integer_Point{max(a.x, b.x, c.x), max(a.y, b.y, c.y)}
			for j in 0 ..< active {
				work^ += 1
				if work^ > limits.max_work { return true, .Limit_Exceeded }
				index := remaining[j]
				if index == previous || index == current || index == next { continue }
				p := points[index]
				if p.x < lo.x || p.x > hi.x || p.y < lo.y || p.y > hi.y { continue }
				if !exact_charge(exact, 24) { return true, .Limit_Exceeded }
				x, y, z := orientation(a, b, p), orientation(b, c, p), orientation(c, a, p)
				if (x >= 0 && y >= 0 && z >= 0) || (x <= 0 && y <= 0 && z <= 0) { blocked = true; break }
			}
			if blocked { continue }
			if turn != 0 {
				mesh.indices[index_count + 0] = u32(previous)
				mesh.indices[index_count + 1] = u32(current)
				mesh.indices[index_count + 2] = u32(next)
				index_count += 3
			}
			for j in i ..< active - 1 { remaining[j] = remaining[j + 1] }
			active -= 1
			found = true
			break
		}
		if !found {
			clear(&mesh.vertices)
			clear(&mesh.indices)
			return false, .None
		}
	}
	resize(&mesh.indices, index_count)
	return true, .None
}
