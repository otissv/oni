package oni_vector

import "core:strings"
import "core:math"


@(private)
svg_parse_url_reference :: proc(value: string) -> (id: string, ok: bool) {
	v := strings.trim_space(value)
	if len(v) < 5 || strings.to_lower(v[:4], context.temp_allocator) != "url(" || !strings.has_suffix(v, ")") { return "", false }
	v = strings.trim_space(v[4:len(v) - 1])
	if len(v) >= 2 && (v[0] == '"' && v[len(v) - 1] == '"' || v[0] == '\'' && v[len(v) - 1] == '\'') { v = v[1:len(v) - 1] }
	if len(v) < 2 || v[0] != '#' || strings.contains_any(v, " \t\r\n()\"'") { return "", false }
	return v[1:], true
}
@(private)
svg_gradient_attr :: proc(chain: []^Xml_Node, name, fallback: string) -> string {
	for node in chain { if value, found := svg_attr(node, name); found { return value } }
	return fallback
}
@(private)
svg_source_style :: proc(ctx: ^Svg_Build_Ctx, node: ^Xml_Node, viewport: [2]f64) -> (Computed_Style, bool) {
	if node == nil { return Default_Computed_Style(), true }
	inherited, valid := svg_source_style(ctx, ctx.parents[node], viewport)
	if !valid { return {}, false }
	return svg_resolve_element_style(node, inherited, viewport, ctx)
}
@(private)
svg_build_gradient :: proc(ctx: ^Svg_Build_Ctx, id: string, viewport: [2]f64) -> (paint: Paint, ok: bool) {
	target := ctx.ids[id]
	if target == nil { return {}, false }
	return svg_build_gradient_node(ctx, target, viewport)
}
@(private)
svg_build_gradient_node :: proc(ctx: ^Svg_Build_Ctx, target: ^Xml_Node, viewport: [2]f64) -> (paint: Paint, ok: bool) {
	chain := make([dynamic]^Xml_Node, context.temp_allocator)
	for node := target; node != nil; {
		if len(chain) > ctx.limits.max_reference_depth { return {}, false }
		append(&chain, node)
		if reference, found := svg_attr_href(node); found { node = ctx.ids[reference] } else { break }
	}
	style, valid := svg_source_style(ctx, target, viewport)
	if !valid { return {}, false }
	stops := make([dynamic]Gradient_Stop)
	for node in chain {
		stop_parent_style, parent_valid := svg_source_style(ctx, node, viewport)
		if !parent_valid { return {}, false }
		for &child in node.children {
			if child.kind != .Element || child.name != "stop" { continue }
			local, stop_valid := svg_resolve_element_style(&child, stop_parent_style, viewport, ctx)
			if !stop_valid { return {}, false }
			value, found := svg_attr(&child, "offset")
			if !found { value = "0" }
			offset, offset_valid := svg_parse_length(value, 1)
			if !offset_valid { return {}, false }
			offset = clamp(offset, 0, 1)
			if len(stops) > 0 { offset = max(offset, stops[len(stops) - 1].offset) }
			color := local.stop_color
			color.a = u8(f64(color.a) * local.stop_opacity + .5)
			append(&stops, Gradient_Stop{offset = offset, color = color})
		}
		if len(stops) > 0 { break }
	}
	units: Gradient_Units = .Object_Bounding_Box
	if svg_gradient_attr(chain[:], "gradientUnits", "objectBoundingBox") == "userSpaceOnUse" { units = .User_Space }
	spread: Gradient_Spread
	switch svg_gradient_attr(chain[:], "spreadMethod", "pad") {
	case "pad": spread = .Pad
	case "reflect": spread = .Reflect
	case "repeat": spread = .Repeat
	}
	transform, err := Parse_Transform_List(svg_gradient_attr(chain[:], "gradientTransform", ""))
	if err != .None { return {}, false }
	singular := transform[0] * transform[3] - transform[1] * transform[2] == 0
	bases := viewport
	if units == .Object_Bounding_Box { bases = {1, 1} }
	if target.name == "linearGradient" {
		x1, a := svg_parse_length(svg_gradient_attr(chain[:], "x1", "0%"), bases.x)
		y1, b := svg_parse_length(svg_gradient_attr(chain[:], "y1", "0%"), bases.y)
		x2, c := svg_parse_length(svg_gradient_attr(chain[:], "x2", "100%"), bases.x)
		y2, d := svg_parse_length(svg_gradient_attr(chain[:], "y2", "0%"), bases.y)
		if !a || !b || !c || !d { return {}, false }
		paint = Linear_Paint({x1 = x1, y1 = y1, x2 = x2, y2 = y2, units = units, spread = spread, transform = transform, stops = stops[:], color_interpolation = style.color_interpolation})
	} else {
		cx, a := svg_parse_length(svg_gradient_attr(chain[:], "cx", "50%"), bases.x)
		cy, b := svg_parse_length(svg_gradient_attr(chain[:], "cy", "50%"), bases.y)
		r, c := svg_parse_length(svg_gradient_attr(chain[:], "r", "50%"), svg_diagonal(bases))
		fx_value := svg_gradient_attr(chain[:], "fx", "")
		fy_value := svg_gradient_attr(chain[:], "fy", "")
		fx, fy := cx, cy
		if fx_value != "" { fx, a = svg_parse_length(fx_value, bases.x) }
		if fy_value != "" { fy, b = svg_parse_length(fy_value, bases.y) }
		fr, d := svg_parse_length(svg_gradient_attr(chain[:], "fr", "0"), svg_diagonal(bases))
		if !a || !b || !c || !d || r < 0 || fr < 0 || fr > r { return {}, false }
		if r == 0 {
			if len(stops) == 0 || singular { return None_Paint(), true }
			return Solid_Paint(stops[len(stops) - 1].color), true
		}
		dx, dy := fx - cx, fy - cy
		distance := math.sqrt(dx * dx + dy * dy)
		if !finite(distance) { return {}, false }
		if fr == 0 && distance > r { fx, fy = cx + dx * r / distance, cy + dy * r / distance }
		if fr > 0 && (fr >= r || distance + fr > r) { return {}, false }
		paint = Radial_Paint({cx = cx, cy = cy, r = r, fx = fx, fy = fy, fr = fr, units = units, spread = spread, transform = transform, stops = stops[:], color_interpolation = style.color_interpolation})
	}
	if len(stops) == 0 || singular { return None_Paint(), true }
	return paint, Validate_Paint(paint) == .None
}

@(private)
svg_validate_gradients :: proc(ctx: ^Svg_Build_Ctx, node: ^Xml_Node) -> bool {
	if node.kind != .Element || node.in_metadata { return true }
	if node.name == "linearGradient" || node.name == "radialGradient" {
		if _, valid := svg_build_gradient_node(ctx, node, ctx.viewport); !valid {
			svg_push(ctx.result, .Invalid_Value, "invalid gradient definition", node.line, node.column, node.name)
			return false
		}
	}
	for &child in node.children { if !svg_validate_gradients(ctx, &child) { return false } }
	return !ctx.arena.failed
}
@(private)
svg_resolve_shape_paint :: proc(ctx: ^Svg_Build_Ctx, value: string, paint: Paint, color: Color) -> (Paint, bool) {
	if id, found := svg_parse_url_reference(value); found { return svg_build_gradient(ctx, id, ctx.viewport) }
	if paint.kind == .Current_Color { return Solid_Paint(color), true }
	return paint, true
}

