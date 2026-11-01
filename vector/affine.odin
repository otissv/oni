package oni_vector

// Composes transforms so Apply(Compose(a, b), p) == Apply(a, Apply(b, p)).
Affine_Compose :: proc(a, b: Affine) -> Affine {
	return {
		a[0] * b[0] + a[2] * b[1],
		a[1] * b[0] + a[3] * b[1],
		a[0] * b[2] + a[2] * b[3],
		a[1] * b[2] + a[3] * b[3],
		a[0] * b[4] + a[2] * b[5] + a[4],
		a[1] * b[4] + a[3] * b[5] + a[5],
	}
}

// Inverts an affine with a non-singular linear part.
Affine_Invert :: proc(transform: Affine) -> (Affine, bool) {
	det := transform[0] * transform[3] - transform[1] * transform[2]
	if det == 0 || !finite(det) {
		return {}, false
	}
	inv := 1 / det
	linear := Affine{
		transform[3] * inv,
		-transform[1] * inv,
		-transform[2] * inv,
		transform[0] * inv,
		0,
		0,
	}
	translation := Transform_Point(linear, {-transform[4], -transform[5]})
	linear[4] = translation.x
	linear[5] = translation.y
	return linear, true
}

@(private)
command_point_count :: proc(kind: Command_Kind) -> int {
	switch kind {
	case .Move, .Line, .Arc:
		return 1
	case .Quadratic:
		return 2
	case .Cubic:
		return 3
	case .Close:
		return 0
	}
	return 0
}

// True when both slices share command kinds, arc flags and radii/rotation.
Commands_Same_Structure :: proc(old_commands, new_commands: []Command) -> bool {
	if len(old_commands) != len(new_commands) {
		return false
	}
	for command, i in old_commands {
		other := new_commands[i]
		if command.kind != other.kind ||
		   command.large_arc != other.large_arc ||
		   command.sweep != other.sweep ||
		   command.radii != other.radii ||
		   command.rotation != other.rotation {
			return false
		}
	}
	return true
}

// Solves for an affine mapping every control/end point in old_commands onto new_commands.
// Compatible topology that is not a single affine returns ok=false.
Commands_Affine :: proc(old_commands, new_commands: []Command) -> (transform: Affine, ok: bool) {
	if len(old_commands) != len(new_commands) {
		return {}, false
	}
	src: [3]Point
	dst: [3]Point
	basis := 0
	fitted := false
	tolerance := 1.0 / 1024
	for command, command_index in old_commands {
		other := new_commands[command_index]
		if command.kind != other.kind ||
		   command.large_arc != other.large_arc ||
		   command.sweep != other.sweep ||
		   command.radii != other.radii ||
		   command.rotation != other.rotation {
			return {}, false
		}
		count := command_point_count(command.kind)
		for point_index in 0 ..< count {
			from := command.points[point_index]
			to := other.points[point_index]
			if !finite(from.x) || !finite(from.y) || !finite(to.x) || !finite(to.y) {
				return {}, false
			}
			if fitted {
				mapped := Transform_Point(transform, from)
				if abs(mapped.x - to.x) > tolerance || abs(mapped.y - to.y) > tolerance {
					return {}, false
				}
				continue
			}
			duplicate := false
			for i in 0 ..< basis {
				if src[i] == from {
					if dst[i] != to {
						return {}, false
					}
					duplicate = true
					break
				}
			}
			if duplicate {
				continue
			}
			src[basis] = from
			dst[basis] = to
			basis += 1
			if basis < 3 {
				continue
			}
			u := src[1] - src[0]
			v := src[2] - src[0]
			if u.x * v.y - u.y * v.x == 0 {
				basis = 2
				src[1] = src[2]
				dst[1] = dst[2]
				continue
			}
			ok_fit: bool
			transform, ok_fit = affine_from_triangles(src, dst)
			if !ok_fit {
				return {}, false
			}
			fitted = true
		}
	}
	if !fitted {
		switch basis {
		case 0:
			transform = IDENTITY
		case 1:
			transform = {1, 0, 0, 1, dst[0].x - src[0].x, dst[0].y - src[0].y}
		case 2:
			u := src[1] - src[0]
			d := dst[1] - dst[0]
			length := u.x * u.x + u.y * u.y
			if length == 0 {
				return {}, false
			}
			transform = {
				(d.x * u.x + d.y * u.y) / length,
				(d.y * u.x - d.x * u.y) / length,
				-(d.y * u.x - d.x * u.y) / length,
				(d.x * u.x + d.y * u.y) / length,
				0,
				0,
			}
			translation := dst[0] - Transform_Point(transform, src[0])
			transform[4] = translation.x
			transform[5] = translation.y
		case:
			return {}, false
		}
		for command, command_index in old_commands {
			count := command_point_count(command.kind)
			for point_index in 0 ..< count {
				from := command.points[point_index]
				to := new_commands[command_index].points[point_index]
				mapped := Transform_Point(transform, from)
				if abs(mapped.x - to.x) > tolerance || abs(mapped.y - to.y) > tolerance {
					return {}, false
				}
			}
		}
	}
	return transform, true
}

@(private)
affine_from_triangles :: proc(src, dst: [3]Point) -> (Affine, bool) {
	x0, y0 := src[0].x, src[0].y
	x1, y1 := src[1].x, src[1].y
	x2, y2 := src[2].x, src[2].y
	det := x0 * (y1 - y2) + x1 * (y2 - y0) + x2 * (y0 - y1)
	if det == 0 || !finite(det) {
		return {}, false
	}
	inv := 1 / det
	i0 := (y1 - y2) * inv
	i1 := (y2 - y0) * inv
	i2 := (y0 - y1) * inv
	j0 := (x2 - x1) * inv
	j1 := (x0 - x2) * inv
	j2 := (x1 - x0) * inv
	k0 := (x1 * y2 - x2 * y1) * inv
	k1 := (x2 * y0 - x0 * y2) * inv
	k2 := (x0 * y1 - x1 * y0) * inv
	a := dst[0].x * i0 + dst[1].x * i1 + dst[2].x * i2
	c := dst[0].x * j0 + dst[1].x * j1 + dst[2].x * j2
	e := dst[0].x * k0 + dst[1].x * k1 + dst[2].x * k2
	b := dst[0].y * i0 + dst[1].y * i1 + dst[2].y * i2
	d := dst[0].y * j0 + dst[1].y * j1 + dst[2].y * j2
	f := dst[0].y * k0 + dst[1].y * k1 + dst[2].y * k2
	if !finite(a) || !finite(b) || !finite(c) || !finite(d) || !finite(e) || !finite(f) {
		return {}, false
	}
	return {a, b, c, d, e, f}, true
}

Mesh_Transform_Into :: proc(mesh: ^Mesh, transform: Affine) {
	if mesh == nil {
		return
	}
	for &vertex in mesh.vertices {
		point := Transform_Point(transform, {f64(vertex.x), f64(vertex.y)})
		vertex = {f32(point.x), f32(point.y)}
	}
}

// Copies vertex positions from src into dst, preserving dst index topology when lengths match.
Mesh_Copy_Vertices_From :: proc(dst: ^Mesh, src: Mesh) -> bool {
	if dst == nil || len(dst.vertices) != len(src.vertices) || len(dst.indices) != len(src.indices) {
		return false
	}
	copy(dst.vertices[:], src.vertices[:])
	return true
}
