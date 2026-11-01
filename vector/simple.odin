package oni_vector

@(private)
orientation :: proc(a, b, c: Integer_Point) -> i128 {
	return integer_cross(b - a, c - a)
}

@(private)
Simple_Edge :: struct {
	a, b, lo, hi: Integer_Point,
}

// Single simple contours admit exact ear clipping without constructing rational
// intersections. Any touching, crossing or overlapping nonadjacent edges fall
// back to the sweep arrangement, including stars and repeated boundaries.
@(private)
simple_mesh :: proc(flat: Flat_Path, mesh: ^Mesh, limits: Limits, pair_tests, work: ^int) -> (simple: bool, err: Error) {
	if len(flat.contours) != 1 || len(flat.points) > 256 { return false, .None }
	points: [256]Integer_Point = ---
	count := 0
	for point in flat.points {
		p := Integer_Point{i64(point.x * 1024), i64(point.y * 1024)}
		if count == 0 || points[count - 1] != p { points[count] = p; count += 1 }
	}
	if count > 1 && points[count - 1] == points[0] { count -= 1 }
	if count < 3 { return false, .None }
	edges: [256]Simple_Edge = ---
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
			c, d := edges[j].a, edges[j].b
			x, y := orientation(a, b, c), orientation(a, b, d)
			u, w := orientation(c, d, a), orientation(c, d, b)
			if (x == 0 || y == 0 || (x < 0) != (y < 0)) && (u == 0 || w == 0 || (u < 0) != (w < 0)) {
				return false, .None
			}
		}
	}
	area := i128(0)
	for i in 0 ..< count { area += integer_cross(points[i], points[i + 1 == count ? 0 : i + 1]) }
	if area == 0 { return false, .None }
	if count - 2 > limits.max_triangles { return true, .Limit_Exceeded }
	if reserve_error := mesh_reserve(mesh, count, (count - 2) * 3, limits); reserve_error != .None { return true, reserve_error }
	remaining: [256]int = ---
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
			// Exact degeneracies outside the fast path use the general solver.
			clear(&mesh.vertices)
			clear(&mesh.indices)
			return false, .None
		}
	}
	resize(&mesh.indices, index_count)
	return true, .None
}
