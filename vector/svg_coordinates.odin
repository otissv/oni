package oni_vector

import "core:strings"

@(private)
svg_view_box :: proc(value: string) -> (box: [4]f64, ok: bool) {
	n, valid := svg_number_list(value, box[:])
	return box, valid && n == 4 && box[2] >= 0 && box[3] >= 0
}
@(private)
svg_fit_view_box :: proc(box: [4]f64, viewport: [2]f64, value: string) -> (transform: Affine, ok: bool) {
	parts := strings.fields(value, context.temp_allocator)
	align := "xMidYMid"
	mode := "meet"
	if len(parts) > 0 && parts[0] == "defer" { parts = parts[1:] }
	if len(parts) > 0 { align = parts[0] }
	if len(parts) > 1 { mode = parts[1] }
	if len(parts) > 2 || (mode != "meet" && mode != "slice") { return {}, false }
	if align != "none" && align != "xMinYMin" && align != "xMidYMin" && align != "xMaxYMin" && align != "xMinYMid" && align != "xMidYMid" && align != "xMaxYMid" && align != "xMinYMax" && align != "xMidYMax" && align != "xMaxYMax" { return {}, false }
	if box[2] == 0 || box[3] == 0 { return IDENTITY, true }
	sx, sy := viewport.x / box[2], viewport.y / box[3]
	x, y := f64(0), f64(0)
	if align != "none" {
		scale := mode == "slice" ? max(sx, sy) : min(sx, sy)
		sx, sy = scale, scale
		if align[1:4] == "Mid" { x = (viewport.x - box[2] * scale) / 2 }
		if align[1:4] == "Max" { x = viewport.x - box[2] * scale }
		if align[5:8] == "Mid" { y = (viewport.y - box[3] * scale) / 2 }
		if align[5:8] == "Max" { y = viewport.y - box[3] * scale }
	}
	return {sx, 0, 0, sy, x - box[0] * sx, y - box[1] * sy}, true
}
@(private)
svg_root_size :: proc(node: ^Xml_Node) -> (width, height: f64, box: [4]f64, ok: bool) {
	width, height = 300, 150
	w, has_w := svg_attr(node, "width")
	h, has_h := svg_attr(node, "height")
	has_w = has_w && !strings.has_suffix(w, "%")
	has_h = has_h && !strings.has_suffix(h, "%")
	if has_w { width, ok = svg_parse_length(w, 300); if !ok { return } }
	if has_h { height, ok = svg_parse_length(h, 150); if !ok { return } }
	if v, has_box := svg_attr(node, "viewBox"); has_box {
		box, ok = svg_view_box(v)
		if !ok { return }
		if box[2] > 0 && box[3] > 0 {
			ratio := box[2] / box[3]
			if has_w && !has_h { height = width / ratio }
			else if has_h && !has_w { width = height * ratio }
			else if !has_w && !has_h { width = min(f64(300), 150 * ratio); height = width / ratio }
		}
	} else { box = {0, 0, width, height} }
	return width, height, box, width >= 0 && height >= 0 && finite(width) && finite(height)
}
@(private)
svg_geometry_length :: proc(node: ^Xml_Node, name: string, base, fallback: f64) -> f64 {
	if value, found := svg_attr(node, name); found { v, _ := svg_parse_length(value, base); return v }
	return fallback
}
@(private)
svg_shape_path :: proc(node: ^Xml_Node, path: ^Path, viewport := [2]f64{}, limits := DEFAULT_LIMITS) -> Error {
	switch node.name {
	case "path":
		if value, found := svg_attr(node, "d"); found { return Parse_Path_Data(value, path, limits) }
		return .None
	case "rect":
		x := svg_geometry_length(node, "x", viewport.x, 0)
		y := svg_geometry_length(node, "y", viewport.y, 0)
		w := svg_geometry_length(node, "width", viewport.x, 0)
		h := svg_geometry_length(node, "height", viewport.y, 0)
		rx := svg_geometry_length(node, "rx", viewport.x, -1)
		ry := svg_geometry_length(node, "ry", viewport.y, -1)
		if rx < 0 { rx = max(f64(0), ry) }
		if ry < 0 { ry = rx }
		if w == 0 || h == 0 { return .None }
		return Rectangle(path, {x, y}, {w, h}, {min(rx, w / 2), min(ry, h / 2)})
	case "circle":
		r := svg_geometry_length(node, "r", svg_diagonal(viewport), 0)
		if r == 0 { return .None }
		return Circle(path, {svg_geometry_length(node, "cx", viewport.x, 0), svg_geometry_length(node, "cy", viewport.y, 0)}, r)
	case "ellipse":
		rx := svg_geometry_length(node, "rx", viewport.x, 0)
		ry := svg_geometry_length(node, "ry", viewport.y, 0)
		if rx == 0 || ry == 0 { return .None }
		return Ellipse(path, {svg_geometry_length(node, "cx", viewport.x, 0), svg_geometry_length(node, "cy", viewport.y, 0)}, {rx, ry})
	case "line":
		if err := Move_To(path, {svg_geometry_length(node, "x1", viewport.x, 0), svg_geometry_length(node, "y1", viewport.y, 0)}); err != .None { return err }
		return Line_To(path, {svg_geometry_length(node, "x2", viewport.x, 0), svg_geometry_length(node, "y2", viewport.y, 0)})
	case "polygon", "polyline":
		value, _ := svg_attr(node, "points")
		points, err := Parse_Points_Attribute(value)
		defer delete(points)
		if err != .None { return err }
		if len(points) == 0 { return .None }
		return Polyline(path, points[:], node.name == "polygon")
	}
	return .Invalid_Path
}

