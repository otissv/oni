package oni_vector

// A nested pair of convex contours admits an exact angular zipper. Validate
// every spoke against the inner polygon's supporting edges before committing;
// other arrangements continue through the general sweep solver.
@(private)
ring_convex :: proc(points: []Integer_Point, work: ^Exact_Work) -> int {
	direction, first_x, first_y, last_x, last_y, changes_x, changes_y := 0, 0, 0, 0, 0, 0, 0
	for a, i in points {
		if !exact_charge(work, 8) { return 0 }
		b, c := points[(i + 1) % len(points)], points[(i + 2) % len(points)]
		turn := orientation(a, b, c)
		// Collinear runs are weakly convex; morph close-duplicates hit this.
		if turn == 0 { continue }
		sign := turn < 0 ? -1 : 1
		if direction != 0 && sign != direction { return 0 }
		direction = sign
		dx, dy := b.x - a.x, b.y - a.y
		x, y := dx < 0 ? -1 : dx > 0 ? 1 : 0, dy < 0 ? -1 : dy > 0 ? 1 : 0
		if x != 0 { if first_x == 0 { first_x = x } else if last_x != x { changes_x += 1 }; last_x = x }
		if y != 0 { if first_y == 0 { first_y = y } else if last_y != y { changes_y += 1 }; last_y = y }
	}
	if direction == 0 { return 0 }
	if changes_x + int(first_x != last_x) > 2 || changes_y + int(first_y != last_y) > 2 { return 0 }
	return direction
}

@(private)
ring_contains :: proc(outer, inner: []Integer_Point, sign: int, limits: Limits, pairs: ^int, work: ^Exact_Work) -> bool {
	for a, i in outer {
		b := outer[(i + 1) % len(outer)]
		for point in inner {
			if pairs^ >= limits.max_pair_tests { work.err = .Limit_Exceeded; return false }
			pairs^ += 1
			if !exact_charge(work, 8) { return false }
			side := orientation(a, b, point)
			if side == 0 || (side < 0) != (sign < 0) { return false }
		}
	}
	return true
}

@(private)
ring_angle_before :: proc(a, b: Integer_Point, work: ^Exact_Work) -> bool {
	if !exact_charge(work, 8) { return false }
	first_a, first_b := a.y > 0 || a.y == 0 && a.x >= 0, b.y > 0 || b.y == 0 && b.x >= 0
	if first_a != first_b { return first_a }
	return integer_cross(a, b) > 0
}

@(private)
ring_spoke :: proc(inner: []Integer_Point, vertex: int, outer: Integer_Point, work: ^Exact_Work) -> bool {
	if !exact_charge(work, 16) { return false }
	point := inner[vertex]
	previous, next := inner[(vertex + len(inner) - 1) % len(inner)], inner[(vertex + 1) % len(inner)]
	return orientation(previous, point, outer) < 0 || orientation(point, next, outer) < 0
}

@(private)
ring_area :: proc(points: []Integer_Point, work: ^Exact_Work) -> (area: i128) {
	for a, i in points {
		if !exact_charge(work, 8) { return 0 }
		area += integer_cross(a, points[(i + 1) % len(points)])
	}
	return
}

// Strict angular progression about a shared interior point proves a contour
// is simple and star-shaped; reject repeated rays and extra revolutions.
@(private)
ring_star :: proc(points: []Integer_Point, center: Integer_Point, count: i64, work: ^Exact_Work) -> bool {
	wraps := 0
	for p, i in points {
		a, b := p * count - center, points[(i + 1) % len(points)] * count - center
		if !exact_charge(work, 16) { return false }
		if integer_cross(a, b) <= 0 { return false }
		if !ring_angle_before(a, b, work) { wraps += 1 }
	}
	return wraps == 1 && work.err == .None
}

@(private)
ring_spoke_clear :: proc(polygon: []Integer_Point, a, b: Integer_Point, limits: Limits, pairs: ^int, work: ^Exact_Work) -> bool {
	for c, i in polygon {
		d := polygon[(i + 1) % len(polygon)]
		if a == c || a == d || b == c || b == d { continue }
		if pairs^ >= limits.max_pair_tests { work.err = .Limit_Exceeded; return false }
		pairs^ += 1
		if max(a.x, b.x) < min(c.x, d.x) || max(c.x, d.x) < min(a.x, b.x) || max(a.y, b.y) < min(c.y, d.y) || max(c.y, d.y) < min(a.y, b.y) { continue }
		if !exact_charge(work, 32) { return false }
		x, y, z, w := orientation(a, b, c), orientation(a, b, d), orientation(c, d, a), orientation(c, d, b)
		if (x == 0 || y == 0 || (x < 0) != (y < 0)) && (z == 0 || w == 0 || (z < 0) != (w < 0)) { return false }
	}
	return true
}

@(private)
ring_mesh :: proc(flat: Flat_Path, mesh: ^Mesh, rule: Fill_Rule, limits: Limits, pairs: ^int, work: ^Exact_Work) -> (handled: bool, err: Error) {
	if len(flat.contours) != 2 || len(flat.points) > 512 { return false, .None }
	storage: [512]Integer_Point
	polygons: [2][]Integer_Point
	used := 0
	for contour, n in flat.contours {
		start := used
		for point in flat.points[contour.first:][:contour.count] {
			p := Integer_Point{i64(point.x * 1024), i64(point.y * 1024)}
			if used == start || storage[used - 1] != p { storage[used] = p; used += 1 }
		}
		if used > start + 1 && storage[used - 1] == storage[start] { used -= 1 }
		if used - start < 3 { return false, .None }
		polygons[n] = storage[start:used]
	}
	signs := [2]int{ring_convex(polygons[0], work), ring_convex(polygons[1], work)}
	general := signs[0] == 0 || signs[1] == 0
	if general {
		areas := [2]i128{ring_area(polygons[0], work), ring_area(polygons[1], work)}
		if areas[0] == 0 || areas[1] == 0 { return work.err != .None, work.err }
		signs = {areas[0] < 0 ? -1 : 1, areas[1] < 0 ? -1 : 1}
		if abs(areas[0]) < abs(areas[1]) { polygons[0], polygons[1] = polygons[1], polygons[0]; signs[0], signs[1] = signs[1], signs[0] }
	}
	if work.err != .None { return true, work.err }
	if signs[0] == 0 || signs[1] == 0 || rule == .Nonzero && signs[0] == signs[1] { return false, .None }
	if !general && !ring_contains(polygons[0], polygons[1], signs[0], limits, pairs, work) {
		if work.err != .None { return true, work.err }
		if !ring_contains(polygons[1], polygons[0], signs[1], limits, pairs, work) { return work.err != .None, work.err }
		polygons[0], polygons[1] = polygons[1], polygons[0]
		signs[0], signs[1] = signs[1], signs[0]
	}
	for polygon, n in polygons {
		if signs[n] < 0 { for i in 0 ..< len(polygon) / 2 { polygon[i], polygon[len(polygon) - 1 - i] = polygon[len(polygon) - 1 - i], polygon[i] } }
	}
	outer, inner := polygons[0], polygons[1]
	center := Integer_Point{}
	for point in inner { center += point }
	// Center is a rational centroid. Scale vectors to keep polar ordering exact.
	count := i64(len(inner))
	if general && (!ring_star(outer, center, count, work) || !ring_star(inner, center, count, work)) { return work.err != .None, work.err }
	first_outer, first_inner := 0, 0
	for point, i in outer { if ring_angle_before(point * count - center, outer[first_outer] * count - center, work) { first_outer = i } }
	for point, i in inner { if ring_angle_before(point * count - center, inner[first_inner] * count - center, work) { first_inner = i } }
	if work.err != .None { return true, work.err }
	indices: [1536]u32
	index_count, a, b := 0, 0, 0
	for a < len(outer) || b < len(inner) {
		oi, ii := (first_outer + a) % len(outer), (first_inner + b) % len(inner)
		if !general && !ring_spoke(inner, ii, outer[oi], work) { return work.err != .None, work.err }
		if general && (!ring_spoke_clear(inner, inner[ii], outer[oi], limits, pairs, work) || !ring_spoke_clear(outer, inner[ii], outer[oi], limits, pairs, work)) { return work.err != .None, work.err }
		on, next_inner := (oi + 1) % len(outer), (ii + 1) % len(inner)
		advance_outer := b == len(inner) || a < len(outer) && ring_angle_before(outer[on] * count - center, inner[next_inner] * count - center, work)
		if a == len(outer) - 1 && b < len(inner) - 1 { advance_outer = false }
		if b == len(inner) - 1 && a < len(outer) - 1 { advance_outer = true }
		triangle := [3]u32{u32(oi), u32(len(outer) + next_inner), u32(len(outer) + ii)}
		if advance_outer { triangle = {u32(oi), u32(on), u32(len(outer) + ii)}; a += 1 } else { b += 1 }
		points := [3]Integer_Point{}
		for index, j in triangle { points[j] = int(index) < len(outer) ? outer[index] : inner[int(index) - len(outer)] }
		if !exact_charge(work, 8) { return true, .Limit_Exceeded }
		area := orientation(points[0], points[1], points[2])
		if area < 0 { return false, .None }
		if area == 0 { continue }
		copy(indices[index_count:][:3], triangle[:]); index_count += 3
	}
	if work.err != .None { return true, work.err }
	if index_count / 3 > limits.max_triangles { return true, .Limit_Exceeded }
	if reserve_error := mesh_reserve(mesh, len(outer) + len(inner), index_count, limits); reserve_error != .None { return true, reserve_error }
	resize(&mesh.vertices, len(outer) + len(inner))
	resize(&mesh.indices, index_count)
	for point, i in outer { mesh.vertices[i] = {f32(point.x) / 1024, f32(point.y) / 1024} }
	for point, i in inner { mesh.vertices[len(outer) + i] = {f32(point.x) / 1024, f32(point.y) / 1024} }
	copy(mesh.indices[:], indices[:index_count])
	return true, .None
}

// Uniform morph ring: same zipper as ring_mesh but without mid-path dedup so
// vertex slots stay stable across compatible control-point edits.
@(private)
stable_ring_mesh :: proc(flat: Flat_Path, mesh: ^Mesh, rule: Fill_Rule, limits: Limits, pairs: ^int, work: ^Exact_Work) -> (handled: bool, err: Error) {
	if len(flat.contours) != 2 || len(flat.points) > 512 {
		return false, .None
	}
	storage: [512]Integer_Point
	polygons: [2][]Integer_Point
	used := 0
	for contour, n in flat.contours {
		start := used
		for point in flat.points[contour.first:][:contour.count] {
			storage[used] = Integer_Point{i64(point.x * 1024), i64(point.y * 1024)}
			used += 1
		}
		// Strip only trailing copies of the start point (close duplicates).
		for used > start + 1 && storage[used - 1] == storage[start] {
			used -= 1
		}
		if used - start < 3 {
			return false, .None
		}
		polygons[n] = storage[start:used]
	}
	signs := [2]int{ring_convex(polygons[0], work), ring_convex(polygons[1], work)}
	general := signs[0] == 0 || signs[1] == 0
	if general {
		areas := [2]i128{ring_area(polygons[0], work), ring_area(polygons[1], work)}
		if areas[0] == 0 || areas[1] == 0 { return work.err != .None, work.err }
		signs = {areas[0] < 0 ? -1 : 1, areas[1] < 0 ? -1 : 1}
		if abs(areas[0]) < abs(areas[1]) { polygons[0], polygons[1] = polygons[1], polygons[0]; signs[0], signs[1] = signs[1], signs[0] }
	}
	if work.err != .None {
		return true, work.err
	}
	if signs[0] == 0 || signs[1] == 0 || rule == .Nonzero && signs[0] == signs[1] {
		return false, .None
	}
	if !general && !ring_contains(polygons[0], polygons[1], signs[0], limits, pairs, work) {
		if work.err != .None {
			return true, work.err
		}
		if !ring_contains(polygons[1], polygons[0], signs[1], limits, pairs, work) {
			return work.err != .None, work.err
		}
		polygons[0], polygons[1] = polygons[1], polygons[0]
		signs[0], signs[1] = signs[1], signs[0]
	}
	for polygon, n in polygons {
		if signs[n] < 0 {
			for i in 0 ..< len(polygon) / 2 {
				polygon[i], polygon[len(polygon) - 1 - i] = polygon[len(polygon) - 1 - i], polygon[i]
			}
		}
	}
	outer, inner := polygons[0], polygons[1]
	center := Integer_Point{}
	for point in inner {
		center += point
	}
	count := i64(len(inner))
	if general && (!ring_star(outer, center, count, work) || !ring_star(inner, center, count, work)) { return work.err != .None, work.err }
	first_outer, first_inner := 0, 0
	for point, i in outer {
		if ring_angle_before(point * count - center, outer[first_outer] * count - center, work) {
			first_outer = i
		}
	}
	for point, i in inner {
		if ring_angle_before(point * count - center, inner[first_inner] * count - center, work) {
			first_inner = i
		}
	}
	if work.err != .None {
		return true, work.err
	}
	indices: [1536]u32
	index_count, a, b := 0, 0, 0
	for a < len(outer) || b < len(inner) {
		oi, ii := (first_outer + a) % len(outer), (first_inner + b) % len(inner)
		if !general && !ring_spoke(inner, ii, outer[oi], work) {
			return work.err != .None, work.err
		}
		if general && (!ring_spoke_clear(inner, inner[ii], outer[oi], limits, pairs, work) || !ring_spoke_clear(outer, inner[ii], outer[oi], limits, pairs, work)) { return work.err != .None, work.err }
		on, next_inner := (oi + 1) % len(outer), (ii + 1) % len(inner)
		advance_outer := b == len(inner) || a < len(outer) && ring_angle_before(outer[on] * count - center, inner[next_inner] * count - center, work)
		if a == len(outer) - 1 && b < len(inner) - 1 {
			advance_outer = false
		}
		if b == len(inner) - 1 && a < len(outer) - 1 {
			advance_outer = true
		}
		triangle := [3]u32{u32(oi), u32(len(outer) + next_inner), u32(len(outer) + ii)}
		if advance_outer {
			triangle = {u32(oi), u32(on), u32(len(outer) + ii)}
			a += 1
		} else {
			b += 1
		}
		points := [3]Integer_Point{}
		for index, j in triangle {
			points[j] = int(index) < len(outer) ? outer[index] : inner[int(index) - len(outer)]
		}
		if !exact_charge(work, 8) {
			return true, .Limit_Exceeded
		}
		area := orientation(points[0], points[1], points[2])
		if area < 0 {
			return false, .None
		}
		if area == 0 {
			continue
		}
		copy(indices[index_count:][:3], triangle[:])
		index_count += 3
	}
	if work.err != .None {
		return true, work.err
	}
	if index_count / 3 > limits.max_triangles {
		return true, .Limit_Exceeded
	}
	if reserve_error := mesh_reserve(mesh, len(outer) + len(inner), index_count, limits); reserve_error != .None {
		return true, reserve_error
	}
	resize(&mesh.vertices, len(outer) + len(inner))
	resize(&mesh.indices, index_count)
	slots: [512]u32 = ---
	base := 0
	for polygon, n in polygons {
		first := int((uintptr(raw_data(polygon)) - uintptr(raw_data(storage[:]))) / size_of(Integer_Point))
		for point, i in polygon {
			slot := first + (signs[n] < 0 ? len(polygon) - 1 - i : i)
			slots[base + i] = u32(slot)
			mesh.vertices[slot] = {f32(point.x) / 1024, f32(point.y) / 1024}
		}
		base += len(polygon)
	}
	for index, i in indices[:index_count] { mesh.indices[i] = slots[index] }
	return true, .None
}
