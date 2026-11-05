package oni_vector

import "core:math"
import "core:strings"
import col "libs:colors"

Svg_Display :: enum { Inline, None }
Svg_Visibility :: enum { Visible, Hidden, Collapse }
Svg_Paint_Order :: enum { Normal, Stroke_Fill, Fill_Stroke }

Computed_Style :: struct {
	display: Svg_Display,
	visibility: Svg_Visibility,
	color: Color,
	fill, stroke: Paint,
	fill_value, stroke_value: string,
	fill_rule, clip_rule: Fill_Rule,
	opacity, fill_opacity, stroke_opacity: f64,
	stroke_width: f64,
	stroke_cap: Line_Cap,
	stroke_join: Line_Join,
	stroke_miter: f64,
	dash: []f64,
	dash_offset, path_length: f64,
	non_scaling: bool,
	transform: Affine,
	paint_order: Svg_Paint_Order,
	color_interpolation: col.Color_Interpolation,
	clip_path_id, mask_id: string,
	mask_alpha: bool,
	overflow_visible: bool,
	stop_color: Color,
	stop_opacity: f64,
}
Default_Computed_Style :: proc() -> Computed_Style {
	return {
		color = {0, 0, 0, 255}, fill = Solid_Paint({0, 0, 0, 255}), stroke = None_Paint(),
		opacity = 1, fill_opacity = 1, stroke_opacity = 1, stroke_width = 1,
		stroke_miter = 4, overflow_visible = true, transform = IDENTITY, stop_color = {0, 0, 0, 255}, stop_opacity = 1,
	}
}
@(private)
SVG_PROPERTIES :: []string{
	"color", "fill", "stroke", "fill-rule", "clip-rule", "opacity", "fill-opacity", "stroke-opacity",
	"stroke-width", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "stroke-dasharray",
	"stroke-dashoffset", "vector-effect", "display", "visibility", "transform", "clip-path", "mask",
	"mask-type", "overflow", "paint-order", "color-interpolation", "stop-color", "stop-opacity",
}
@(private)
svg_is_property :: proc(name: string) -> bool {
	for property in SVG_PROPERTIES { if property == name { return true } }
	return false
}
@(private)
svg_inherited_property :: proc(name: string) -> bool {
	switch name {
	case "opacity", "display", "transform", "clip-path", "mask", "mask-type", "overflow", "vector-effect", "stop-color", "stop-opacity": return false
	}
	return true
}
@(private)
svg_copy_property :: proc(dst: ^Computed_Style, src: Computed_Style, name: string) {
	switch name {
	case "color": dst.color = src.color
	case "fill": dst.fill, dst.fill_value = src.fill, src.fill_value
	case "stroke": dst.stroke, dst.stroke_value = src.stroke, src.stroke_value
	case "fill-rule": dst.fill_rule = src.fill_rule
	case "clip-rule": dst.clip_rule = src.clip_rule
	case "opacity": dst.opacity = src.opacity
	case "fill-opacity": dst.fill_opacity = src.fill_opacity
	case "stroke-opacity": dst.stroke_opacity = src.stroke_opacity
	case "stroke-width": dst.stroke_width = src.stroke_width
	case "stroke-linecap": dst.stroke_cap = src.stroke_cap
	case "stroke-linejoin": dst.stroke_join = src.stroke_join
	case "stroke-miterlimit": dst.stroke_miter = src.stroke_miter
	case "stroke-dasharray": dst.dash = src.dash
	case "stroke-dashoffset": dst.dash_offset = src.dash_offset
	case "vector-effect": dst.non_scaling = src.non_scaling
	case "display": dst.display = src.display
	case "visibility": dst.visibility = src.visibility
	case "transform": dst.transform = src.transform
	case "clip-path": dst.clip_path_id = src.clip_path_id
	case "mask": dst.mask_id = src.mask_id
	case "mask-type": dst.mask_alpha = src.mask_alpha
	case "overflow": dst.overflow_visible = src.overflow_visible
	case "paint-order": dst.paint_order = src.paint_order
	case "color-interpolation": dst.color_interpolation = src.color_interpolation
	case "stop-color": dst.stop_color = src.stop_color
	case "stop-opacity": dst.stop_opacity = src.stop_opacity
	}
}
Style_Inherit :: proc(child, parent: ^Computed_Style) {
	for name in SVG_PROPERTIES { if svg_inherited_property(name) { svg_copy_property(child, parent^, name) } }
}
@(private)
svg_parse_length :: proc(value: string, percent_base: f64) -> (f64, bool) {
	v := strings.trim_space(value)
	i := 0
	number, ok := parse_transform_number(v, &i)
	if !ok { return 0, false }
	unit := v[i:]
	scale := f64(1)
	switch unit {
	case "", "px":
	case "%": scale = percent_base / 100
	case "in": scale = 96
	case "cm": scale = 96 / 2.54
	case "mm": scale = 96 / 25.4
	case "pt": scale = 96 / 72.0
	case "pc": scale = 16
	case: return 0, false
	}
	number *= scale
	return number, finite(number)
}
@(private)
svg_parse_scalar :: proc(value: string) -> (f64, bool) {
	i := 0
	v, ok := parse_transform_number(strings.trim_space(value), &i)
	return v, ok && i == len(strings.trim_space(value))
}
@(private)
svg_diagonal :: proc(viewport: [2]f64) -> f64 {
	return math.sqrt((viewport.x * viewport.x + viewport.y * viewport.y) / 2)
}
@(private)
svg_parse_paint_keyword :: proc(value: string, current: Color) -> (Paint, bool) {
	switch value {
	case "none": return None_Paint(), true
	case "currentColor": return Current_Color_Paint(), true
	}
	color, ok := col.svg_color_parse(value)
	return Solid_Paint(color), ok
}
svg_merge_property :: proc(style: ^Computed_Style, name, value: string, viewport: [2]f64) -> bool {
	v := strings.trim_space(value)
	lower := strings.to_lower(v, context.temp_allocator)
	switch name {
	case "display", "visibility", "fill-rule", "clip-rule", "stroke-linecap", "stroke-linejoin", "vector-effect", "mask-type", "overflow", "paint-order": v = lower
	case "color-interpolation":
		if lower == "srgb" { v = "sRGB" }
		if lower == "linearrgb" { v = "linearRGB" }
	case "fill", "stroke", "color", "stop-color":
		if lower == "none" { v = "none" }
		if lower == "currentcolor" { v = "currentColor" }
	case "clip-path", "mask", "stroke-dasharray": if lower == "none" { v = "none" }
	}
	switch name {
	case "display":
		switch v {
		case "none": style.display = .None
		case "inline": style.display = .Inline
		case: return false
		}
	case "visibility":
		switch v {
		case "visible": style.visibility = .Visible
		case "hidden": style.visibility = .Hidden
		case "collapse": style.visibility = .Collapse
		case: return false
		}
	case "color", "stop-color":
		color: Color
		ok := true
		if v == "currentColor" { color = style.color } else { color, ok = col.svg_color_parse(v) }
		if !ok { return false }
		if name == "color" { style.color = color } else { style.stop_color = color }
	case "opacity", "fill-opacity", "stroke-opacity", "stop-opacity":
		number, ok := svg_parse_length(v, 1)
		if !ok { return false }
		number = clamp(number, 0, 1)
		switch name {
		case "opacity": style.opacity = number
		case "fill-opacity": style.fill_opacity = number
		case "stroke-opacity": style.stroke_opacity = number
		case "stop-opacity": style.stop_opacity = number
		}
	case "fill", "stroke":
		paint: Paint
		if _, ref := svg_parse_url_reference(v); ref { paint = None_Paint() }
		else {
			p, ok := svg_parse_paint_keyword(v, style.color)
			if !ok { return false }
			paint = p
		}
		if name == "fill" { style.fill, style.fill_value = paint, v } else { style.stroke, style.stroke_value = paint, v }
	case "fill-rule", "clip-rule":
		rule: Fill_Rule
		switch v {
		case "nonzero": rule = .Nonzero
		case "evenodd": rule = .Even_Odd
		case: return false
		}
		if name == "fill-rule" { style.fill_rule = rule } else { style.clip_rule = rule }
	case "stroke-width", "stroke-dashoffset":
		number, ok := svg_parse_length(v, svg_diagonal(viewport))
		if !ok || name == "stroke-width" && number < 0 { return false }
		if name == "stroke-width" { style.stroke_width = number } else { style.dash_offset = number }
	case "stroke-miterlimit":
		number, ok := svg_parse_scalar(v)
		if !ok || number < 1 { return false }
		style.stroke_miter = number
	case "stroke-linecap":
		switch v {
		case "butt": style.stroke_cap = .Butt
		case "round": style.stroke_cap = .Round
		case "square": style.stroke_cap = .Square
		case: return false
		}
	case "stroke-linejoin":
		switch v {
		case "miter": style.stroke_join = .Miter
		case "round": style.stroke_join = .Round
		case "bevel": style.stroke_join = .Bevel
		case: return false
		}
	case "stroke-dasharray":
		if v == "none" { style.dash = nil; return true }
		dash := make([dynamic]f64, context.temp_allocator)
		i := 0
		for {
			xml_skip_ws(v, &i)
			if i == len(v) { break }
			if i > 0 && v[i] == ',' { i += 1; xml_skip_ws(v, &i) }
			start := i
			_, ok := parse_transform_number(v, &i)
			if !ok { return false }
			for i < len(v) && ((v[i] >= 'a' && v[i] <= 'z') || v[i] == '%') { i += 1 }
			number, valid := svg_parse_length(v[start:i], svg_diagonal(viewport))
			if !valid || number < 0 { return false }
			append(&dash, number)
		}
		if len(dash) == 0 { return false }
		style.dash = dash[:]
	case "vector-effect":
		switch v {
		case "none": style.non_scaling = false
		case "non-scaling-stroke": style.non_scaling = true
		case: return false
		}
	case "transform":
		transform, err := Parse_Transform_List(v)
		if err != .None { return false }
		style.transform = transform
	case "clip-path", "mask":
		id := ""
		if v != "none" {
			ref, ok := svg_parse_url_reference(v)
			if !ok { return false }
			id = ref
		}
		if name == "clip-path" { style.clip_path_id = id } else { style.mask_id = id }
	case "mask-type":
		switch v {
		case "alpha": style.mask_alpha = true
		case "luminance": style.mask_alpha = false
		case: return false
		}
	case "overflow":
		switch v {
		case "visible": style.overflow_visible = true
		case "hidden", "scroll", "auto": style.overflow_visible = false
		case: return false
		}
	case "paint-order":
		if v == "normal" { style.paint_order = .Normal; return true }
		parts := strings.fields(v, context.temp_allocator)
		if len(parts) < 1 || len(parts) > 3 { return false }
		seen: [3]bool
		first := ""
		for part in parts {
			index := part == "fill" ? 0 : part == "stroke" ? 1 : part == "markers" ? 2 : -1
			if index < 0 || seen[index] { return false }
			seen[index] = true
			if part != "markers" && first == "" { first = part }
		}
		style.paint_order = first == "stroke" ? .Stroke_Fill : .Fill_Stroke
	case "color-interpolation":
		switch v {
		case "sRGB": style.color_interpolation = .sRGB
		case "linearRGB": style.color_interpolation = .Linear_RGB
		case: return false
		}
	case: return false
	}
	return true
}

@(private)
svg_css_wide :: proc(value: string) -> (string, bool) {
	trimmed := strings.trim_space(value)
	for keyword in ([]string{"inherit", "initial", "unset"}) {
		if strings.equal_fold(trimmed, keyword) { return keyword, true }
	}
	return "", false
}
svg_resolve_element_style :: proc(node: ^Xml_Node, inherited: Computed_Style, viewport: [2]f64, ctx: ^Svg_Build_Ctx) -> (style: Computed_Style, ok: bool) {
	style = Default_Computed_Style()
	inherited_copy := inherited
	Style_Inherit(&style, &inherited_copy)
	if node.name == "symbol" || node.name == "svg" && ctx.parents[node] != nil { style.overflow_visible = false }
	ok = Apply_Css_Cascade(node, &style, viewport, ctx, inherited)
	if ok {
		if value, found := svg_attr(node, "pathLength"); found { style.path_length, _ = svg_parse_scalar(value) }
		ok = svg_apply_overrides(ctx, node, &style)
	}
	return
}

