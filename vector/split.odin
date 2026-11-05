package oni_vector

import "core:mem"

@(private)
split_inside :: proc(point: Integer_Point, polygon: []Integer_Point, work: ^Exact_Work) -> bool {
	winding := 0
	for a, i in polygon {
		b := polygon[(i + 1) % len(polygon)]
		if !exact_charge(work, 8) { return true }
		side := orientation(a, b, point)
		if side == 0 && point.x >= min(a.x, b.x) && point.x <= max(a.x, b.x) && point.y >= min(a.y, b.y) && point.y <= max(a.y, b.y) { return true }
		if a.y <= point.y && b.y > point.y && side > 0 { winding += 1 }
		if a.y > point.y && b.y <= point.y && side < 0 { winding -= 1 }
	}
	return winding != 0
}

// Split a contour at an exact repeated vertex only when the two simple lobes
// have disjoint interiors and no other touching/crossing boundaries.
@(private)
split_mesh :: proc(flat: Flat_Path, mesh: ^Mesh, limits: Limits, pairs, simple_work: ^int, work: ^Exact_Work, scratch: mem.Allocator) -> (handled: bool, err: Error) {
	if len(flat.contours) != 1 || len(flat.points) > 512 { return false, .None }
	points: [512]Integer_Point
	count := 0
	for point in flat.points {
		p := Integer_Point{i64(point.x * 1024), i64(point.y * 1024)}
		if count == 0 || points[count - 1] != p { points[count] = p; count += 1 }
	}
	if count > 1 && points[0] == points[count - 1] { count -= 1 }
	first, second := -1, -1
	for i in 0 ..< count {
		for j in i + 3 ..< count {
			if !exact_charge(work, 2) { return true, .Limit_Exceeded }
			if points[i] == points[j] && count - (j - i) >= 3 { first, second = i, j; break }
		}
		if first >= 0 { break }
	}
	if first < 0 { return false, .None }
	other: [512]Integer_Point
	n := copy(other[:], points[second:count])
	n += copy(other[n:], points[:first])
	a, b := points[first:second], other[:n]
	if split_inside(a[1], b, work) || split_inside(b[1], a, work) { return work.err != .None, work.err }
	for p, i in a {
		q := a[(i + 1) % len(a)]
		for r, j in b {
			s := b[(j + 1) % len(b)]
			if pairs^ >= limits.max_pair_tests { return true, .Limit_Exceeded }
			pairs^ += 1
			if max(p.x, q.x) < min(r.x, s.x) || max(r.x, s.x) < min(p.x, q.x) || max(p.y, q.y) < min(r.y, s.y) || max(r.y, s.y) < min(p.y, q.y) { continue }
			if !exact_charge(work, 32) { return true, .Limit_Exceeded }
			shared := p == r || p == s || q == r || q == s
			x, y, z, w := orientation(p, q, r), orientation(p, q, s), orientation(r, s, p), orientation(r, s, q)
			if shared {
				if x == 0 && y == 0 {
					common := p == r || p == s ? p : q
					u, v := (p == common ? q : p) - common, (r == common ? s : r) - common
					if !exact_charge(work, 8) { return true, .Limit_Exceeded }
					if i128(u.x) * i128(v.x) + i128(u.y) * i128(v.y) > 0 { return false, .None }
				}
				continue
			}
			if (x == 0 || y == 0 || (x < 0) != (y < 0)) && (z == 0 || w == 0 || (z < 0) != (w < 0)) { return false, .None }
		}
	}
	submeshes: [2]Mesh
	triangles := 0
	for polygon, index in ([2][]Integer_Point{a, b}) {
		subflat := Flat_Path{points = make([dynamic]Point, scratch), contours = make([dynamic]Contour, scratch)}
		if reserve(&subflat.points, len(polygon)) != nil { return true, .Allocation_Failed }
		for point in polygon { append(&subflat.points, Point{f64(point.x) / 1024, f64(point.y) / 1024}) }
		if _, allocation_error := append(&subflat.contours, Contour{count = len(polygon), closed = true}); allocation_error != nil { return true, .Allocation_Failed }
		submeshes[index] = {vertices = make([dynamic][2]f32, scratch), indices = make([dynamic]u32, scratch)}
		sublimits := limits
		sublimits.max_triangles -= triangles
		simple, suberr := simple_mesh(subflat, &submeshes[index], sublimits, pairs, simple_work, work)
		if suberr != .None { return true, suberr }
		if !simple { return false, .None }
		triangles += len(submeshes[index].indices) / 3
	}
	vertices := len(submeshes[0].vertices) + len(submeshes[1].vertices)
	if reserve_error := mesh_reserve(mesh, vertices, triangles * 3, limits); reserve_error != .None { return true, reserve_error }
	stable := vertices == count
	cursor := 0
	for submesh in submeshes {
		for point in submesh.vertices {
			original := points[(first + cursor) % count]
			stable = stable && point == ([2]f32{f32(original.x) / 1024, f32(original.y) / 1024})
			cursor += 1
		}
	}
	if stable {
		resize(&mesh.vertices, vertices)
		base := 0
		for submesh in submeshes {
			for point, i in submesh.vertices { mesh.vertices[(first + base + i) % count] = point }
			for index in submesh.indices { append(&mesh.indices, u32((first + base + int(index)) % count)) }
			base += len(submesh.vertices)
		}
		return true, .None
	}
	for submesh in submeshes {
		base := u32(len(mesh.vertices))
		append(&mesh.vertices, ..submesh.vertices[:])
		for index in submesh.indices { append(&mesh.indices, base + index) }
	}
	return true, .None
}
