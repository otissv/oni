package oni_vector

Bounds :: struct {
	min, max: Point,
	empty: bool,
}

// Conservative transformed curve bounds, within the flattening tolerance of
// the snapped contour. Empty paths return empty = true.
Path_Bounds :: proc(commands: []Command, transform := IDENTITY, limits := DEFAULT_LIMITS) -> (bounds: Bounds, err: Error) {
	flat, flatten_error := Flatten(commands, transform, limits)
	defer Destroy_Flat_Path(&flat)
	if flatten_error != .None {
		return {empty = true}, flatten_error
	}
	if len(flat.points) == 0 {
		return {empty = true}, .None
	}
	bounds.min, bounds.max = flat.points[0], flat.points[0]
	for point in flat.points[1:] {
		bounds.min = {min(bounds.min.x, point.x), min(bounds.min.y, point.y)}
		bounds.max = {max(bounds.max.x, point.x), max(bounds.max.y, point.y)}
	}
	bounds.min -= Point{limits.tolerance, limits.tolerance}
	bounds.max += Point{limits.tolerance, limits.tolerance}
	return bounds, .None
}

// Appends one contour transactionally; a failed helper preserves earlier commands.
Rectangle :: proc(path: ^Path, origin, size: Point, radii := Point{}) -> (err: Error) {
	if path == nil || !(size.x >= 0 && size.y >= 0 && radii.x >= 0 && radii.y >= 0) ||
	   !finite(size.x) || !finite(size.y) || !finite(radii.x) || !finite(radii.y) {
		return .Invalid_Value
	}
	before := len(path.commands)
	defer if err != .None { resize(&path.commands, before) }
	rx, ry := min(radii.x, size.x * 0.5), min(radii.y, size.y * 0.5)
	x, y := origin.x, origin.y
	w, h := size.x, size.y
	commands := [10]Command{
		{kind = .Move, points = {{x + rx, y}, {}, {}}},
		{kind = .Line, points = {{x + w - rx, y}, {}, {}}},
		{kind = .Arc, points = {{x + w, y + ry}, {}, {}}, radii = {rx, ry}, sweep = true},
		{kind = .Line, points = {{x + w, y + h - ry}, {}, {}}},
		{kind = .Arc, points = {{x + w - rx, y + h}, {}, {}}, radii = {rx, ry}, sweep = true},
		{kind = .Line, points = {{x + rx, y + h}, {}, {}}},
		{kind = .Arc, points = {{x, y + h - ry}, {}, {}}, radii = {rx, ry}, sweep = true},
		{kind = .Line, points = {{x, y + ry}, {}, {}}},
		{kind = .Arc, points = {{x + rx, y}, {}, {}}, radii = {rx, ry}, sweep = true},
		{kind = .Close},
	}
	for command in commands {
		if err = append_command(path, command); err != .None { return err }
	}
	return .None
}

Ellipse :: proc(path: ^Path, centre, radii: Point) -> (err: Error) {
	if path == nil || !(radii.x >= 0 && radii.y >= 0) || !finite(radii.x) || !finite(radii.y) {
		return .Invalid_Value
	}
	before := len(path.commands)
	defer if err != .None { resize(&path.commands, before) }
	commands := [4]Command{
		{kind = .Move, points = {{centre.x + radii.x, centre.y}, {}, {}}},
		{kind = .Arc, points = {{centre.x - radii.x, centre.y}, {}, {}}, radii = radii, sweep = true},
		{kind = .Arc, points = {{centre.x + radii.x, centre.y}, {}, {}}, radii = radii, sweep = true},
		{kind = .Close},
	}
	for command in commands {
		if err = append_command(path, command); err != .None { return err }
	}
	return .None
}

Circle :: proc(path: ^Path, centre: Point, radius: f64) -> Error {
	return Ellipse(path, centre, {radius, radius})
}

Polyline :: proc(path: ^Path, points: []Point, closed := false) -> (err: Error) {
	if path == nil { return .Invalid_Path }
	before := len(path.commands)
	defer if err != .None { resize(&path.commands, before) }
	for point, i in points {
		if err = append_command(path, {kind = i == 0 ? .Move : .Line, points = {point, {}, {}}}); err != .None { return err }
	}
	if closed && len(points) > 0 { return Close(path) }
	return .None
}
