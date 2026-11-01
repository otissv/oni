package oni_vector

import "core:math"
import "core:strconv"
import "core:strings"

@(private)
parse_transform_number :: proc(data: string, i: ^int) -> (f64, bool) {
	xml_skip_ws(data, i)
	if i^ < len(data) && data[i^] == ',' {
		if i^ == 0 { return 0, false }
		i^ += 1
		xml_skip_ws(data, i)
	}
	start := i^
	if i^ < len(data) && (data[i^] == '+' || data[i^] == '-') { i^ += 1 }
	digits := 0
	for i^ < len(data) && data[i^] >= '0' && data[i^] <= '9' { i^ += 1; digits += 1 }
	if i^ < len(data) && data[i^] == '.' {
		i^ += 1
		for i^ < len(data) && data[i^] >= '0' && data[i^] <= '9' { i^ += 1; digits += 1 }
	}
	if digits == 0 { return 0, false }
	if i^ < len(data) && (data[i^] == 'e' || data[i^] == 'E') {
		i^ += 1
		if i^ < len(data) && (data[i^] == '+' || data[i^] == '-') { i^ += 1 }
		exp_start := i^
		for i^ < len(data) && data[i^] >= '0' && data[i^] <= '9' { i^ += 1 }
		if i^ == exp_start { return 0, false }
	}
	value, ok := strconv.parse_f64(data[start:i^])
	return value, ok && finite(value)
}

@(private)
svg_number_list :: proc(data: string, out: []f64) -> (count: int, ok: bool) {
	i := 0
	for {
		xml_skip_ws(data, &i)
		if i == len(data) { return count, true }
		if count == len(out) { return count, false }
		value, valid := parse_transform_number(data, &i)
		if !valid { return count, false }
		out[count] = value
		count += 1
	}
}

Parse_Path_Data :: proc(data: string, path: ^Path, limits := DEFAULT_LIMITS) -> (err: Error) {
	if path == nil { return .Invalid_Path }
	Destroy_Path(path)
	defer if err != .None { Destroy_Path(path) }
	i := 0
	cmd, previous: u8
	last, start, control: Point
	for {
		xml_skip_ws(data, &i)
		if i == len(data) { break }
		if len(path.commands) >= limits.max_commands { return .Limit_Exceeded }
		letter := data[i]
		if (letter >= 'A' && letter <= 'Z') || (letter >= 'a' && letter <= 'z') {
			cmd = letter
			i += 1
			xml_skip_ws(data, &i)
			if i < len(data) && data[i] == ',' { return .Invalid_Path }
		} else if cmd == 0 { return .Invalid_Path }
		relative := cmd >= 'a' && cmd <= 'z'
		upper := cmd
		if relative { upper -= 'a' - 'A' }
		if len(path.commands) == 0 && upper != 'M' { return .Invalid_Path }
		values: [7]f64
		count := 0
		switch upper {
		case 'M', 'L', 'T': count = 2
		case 'H', 'V': count = 1
		case 'Q', 'S': count = 4
		case 'C': count = 6
		case 'A': count = 7
		case 'Z':
		case: return .Invalid_Path
		}
		for n in 0 ..< count {
			if upper == 'A' && (n == 3 || n == 4) {
				xml_skip_ws(data, &i)
				if i < len(data) && data[i] == ',' { i += 1; xml_skip_ws(data, &i) }
				if i >= len(data) || (data[i] != '0' && data[i] != '1') { return .Invalid_Path }
				values[n] = f64(data[i] - '0')
				i += 1
			} else {
				value, ok := parse_transform_number(data, &i)
				if !ok { return .Invalid_Path }
				values[n] = value
			}
		}
		point := Point{values[0], values[1]}
		if relative { point += last }
		switch upper {
		case 'M':
			err = Move_To(path, point)
			start = point
			cmd = relative ? 'l' : 'L'
		case 'L': err = Line_To(path, point)
		case 'H': point = {values[0] + (relative ? last.x : 0), last.y}; err = Line_To(path, point)
		case 'V': point = {last.x, values[0] + (relative ? last.y : 0)}; err = Line_To(path, point)
		case 'C':
			c1, c2 := Point{values[0], values[1]}, Point{values[2], values[3]}
			point = {values[4], values[5]}
			if relative { c1 += last; c2 += last; point += last }
			err = Cubic_To(path, c1, c2, point)
			control = c2
		case 'S':
			c1 := last
			if previous == 'C' || previous == 'S' { c1 = 2 * last - control }
			c2 := point
			point = {values[2], values[3]}
			if relative { point += last }
			err = Cubic_To(path, c1, c2, point)
			control = c2
		case 'Q':
			control = point
			point = {values[2], values[3]}
			if relative { point += last }
			err = Quadratic_To(path, control, point)
		case 'T':
			c1 := last
			if previous == 'Q' || previous == 'T' { c1 = 2 * last - control }
			err = Quadratic_To(path, c1, point)
			control = c1
		case 'A':
			point = {values[5], values[6]}
			if relative { point += last }
			err = Arc_To(path, {abs(values[0]), abs(values[1])}, values[2], values[3] == 1, values[4] == 1, point)
		case 'Z': err = Close(path); point = start; cmd = 0
		}
		if err != .None { return err }
		last = point
		previous = upper
	}
	if len(path.commands) == 0 { return .None }
	return Validate_Commands(path.commands[:], limits)
}

Parse_Points_Attribute :: proc(data: string) -> ([dynamic]Point, Error) {
	points: [dynamic]Point
	success := false
	defer if !success { delete(points) }
	i := 0
	for {
		xml_skip_ws(data, &i)
		if i == len(data) { success = true; return points, .None }
		x, ok_x := parse_transform_number(data, &i)
		y, ok_y := parse_transform_number(data, &i)
		if !ok_x || !ok_y { return nil, .Invalid_Value }
		if _, alloc_err := append(&points, Point{x, y}); alloc_err != nil { return nil, .Allocation_Failed }
	}
}

Parse_Transform_List :: proc(data: string) -> (transform: Affine, err: Error) {
	transform = IDENTITY
	i := 0
	for {
		xml_skip_ws(data, &i)
		if i == len(data) { return transform, .None }
		if i > 0 && data[i] == ',' { i += 1; xml_skip_ws(data, &i) }
		start := i
		for i < len(data) && ((data[i] >= 'a' && data[i] <= 'z') || (data[i] >= 'A' && data[i] <= 'Z')) { i += 1 }
		name := data[start:i]
		xml_skip_ws(data, &i)
		if i == len(data) || data[i] != '(' { return {}, .Invalid_Value }
		i += 1
		end := strings.index_byte(data[i:], ')')
		if end < 0 { return {}, .Invalid_Value }
		args: [6]f64
		n, ok := svg_number_list(data[i:i + end], args[:])
		if !ok { return {}, .Invalid_Value }
		i += end + 1
		local := IDENTITY
		switch name {
		case "matrix":
			if n != 6 { return {}, .Invalid_Value }
			local = args
		case "translate", "scale":
			if n != 1 && n != 2 { return {}, .Invalid_Value }
			if name == "translate" {
				local[4] = args[0]
				if n == 2 { local[5] = args[1] }
			} else {
				local[0], local[3] = args[0], args[0]
				if n == 2 { local[3] = args[1] }
			}
		case "rotate":
			if n != 1 && n != 3 { return {}, .Invalid_Value }
			a := args[0] * math.PI / 180
			local = {math.cos(a), math.sin(a), -math.sin(a), math.cos(a), 0, 0}
			if n == 3 {
				local = Affine_Compose({1, 0, 0, 1, args[1], args[2]}, Affine_Compose(local, {1, 0, 0, 1, -args[1], -args[2]}))
			}
		case "skewX", "skewY":
			if n != 1 { return {}, .Invalid_Value }
			local[name == "skewX" ? 2 : 1] = math.tan(args[0] * math.PI / 180)
		case: return {}, .Invalid_Value
		}
		transform = Affine_Compose(transform, local)
		for value in transform { if !finite(value) { return {}, .Invalid_Value } }
	}
}
