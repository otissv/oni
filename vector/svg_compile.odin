package oni_vector

import "core:fmt"
import "core:slice"
import "core:strings"

@(private)
svg_is_shape_element :: proc(name: string) -> bool {
	switch name {
	case "path", "rect", "circle", "ellipse", "line", "polyline", "polygon": return true
	}
	return false
}
@(private)
svg_collect_stylesheets :: proc(node: ^Xml_Node, ctx: ^Svg_Build_Ctx, order: ^int) -> bool {
	if node.kind != .Element || node.in_metadata { return true }
	if node.name == "style" {
		builder := strings.builder_make(context.temp_allocator)
		for child in node.children { if child.kind == .Text { strings.write_string(&builder, child.text) } }
		sheet, valid := Parse_Css_Stylesheet(strings.to_string(builder), ctx, order^)
		if !valid { return false }
		append(&ctx.css.sheets, sheet)
		order^ += len(sheet.rules)
	}
	for &child in node.children { if !svg_collect_stylesheets(&child, ctx, order) { return false } }
	return true
}
@(private)
svg_style_to_stroke :: proc(style: Computed_Style) -> Stroke {
	return {width = style.stroke_width, cap = style.stroke_cap, join = style.stroke_join, miter_limit = style.stroke_miter, dash = style.dash, dash_offset = style.dash_offset, path_length = style.path_length, non_scaling = style.non_scaling}
}
@(private)
svg_emit_shape :: proc(ctx: ^Svg_Build_Ctx, node: ^Xml_Node, style: Computed_Style, transform: Affine) -> bool {
	if style.visibility != .Visible { return true }
	path: Path
	limits := DEFAULT_LIMITS
	limits.max_commands = ctx.limits.max_path_commands - ctx.emitted_commands
	path_override, has_path := svg_find_override(ctx, node, .Path)
	if has_path { path.commands = make([dynamic]Command); append(&path.commands, ..path_override.commands) }
	if err := Error.None if has_path else svg_shape_path(node, &path, ctx.viewport, limits); err != .None {
		svg_push(ctx.result, err == .Limit_Exceeded ? .Limit_Exceeded : .Invalid_Value, "shape preparation failed", node.line, node.column, node.name)
		return false
	}
	if len(path.commands) == 0 { return true }
	ctx.emitted_commands += len(path.commands)
	if ctx.emitted_commands > ctx.limits.max_path_commands { svg_push(ctx.result, .Limit_Exceeded, fmt.tprintf("expanded commands consumed %d, allowed %d", ctx.emitted_commands, ctx.limits.max_path_commands), node.line, node.column, node.name); return false }
	fill, fill_ok := svg_resolve_shape_paint(ctx, style.fill_value, style.fill, style.color)
	stroke, stroke_ok := svg_resolve_shape_paint(ctx, style.stroke_value, style.stroke, style.color)
	if !fill_ok || !stroke_ok { svg_push(ctx.result, .Invalid_Value, "invalid gradient paint", node.line, node.column, node.name); return false }
	settings := svg_style_to_stroke(style)
	rule := style.fill_rule
	if ctx.clip_mode {
		fill, stroke, rule = Solid_Paint({255, 255, 255, 255}), None_Paint(), style.clip_rule
	}
	append(&ctx.roots, Svg_Draw_Node{kind = .Path, opacity = 1, item = {
		commands = path.commands[:], transform = transform, fill = fill, stroke = stroke,
		fill_rule = rule, opacity = 1, fill_opacity = ctx.clip_mode ? 1 : style.fill_opacity, stroke_opacity = style.stroke_opacity,
		stroke_settings = settings, draw_fill = fill.kind != .None, draw_stroke = stroke.kind != .None && settings.width > 0,
		paint_order = style.paint_order,
	}})
	return true
}
@(private)
svg_bounds_for_nodes :: proc(nodes: []Svg_Draw_Node, inverse: Affine) -> (bounds: Bounds, valid: bool) {
	bounds.empty = true
	for node in nodes {
		if node.kind == .Path {
			limits := DEFAULT_LIMITS
			limits.tolerance = 1.0 / 1024
			b, err := Geometry_Bounds(node.item.commands, Affine_Compose(inverse, node.item.transform), limits)
			if err != .None { return {}, false }
			if b.empty { continue }
			if bounds.empty { bounds = b } else { bounds.min = {min(bounds.min.x, b.min.x), min(bounds.min.y, b.min.y)}; bounds.max = {max(bounds.max.x, b.max.x), max(bounds.max.y, b.max.y)} }
		} else {
			b, ok := svg_bounds_for_nodes(node.children, inverse)
			if !ok { return {}, false }
			if b.empty { continue }
			if bounds.empty { bounds = b } else { bounds.min = {min(bounds.min.x, b.min.x), min(bounds.min.y, b.min.y)}; bounds.max = {max(bounds.max.x, b.max.x), max(bounds.max.y, b.max.y)} }
		}
	}
	return bounds, true
}
@(private)
svg_compile_definition :: proc(ctx: ^Svg_Build_Ctx, target: ^Xml_Node, transform: Affine, viewport: [2]f64, clip_mode: bool) -> (nodes: []Svg_Draw_Node, ok: bool) {
	saved_roots, saved_viewport, saved_clip := ctx.roots, ctx.viewport, ctx.clip_mode
	saved_target := ctx.definition_target
	ctx.definition_target = target
	defer ctx.definition_target = saved_target
	ctx.roots, ctx.viewport, ctx.clip_mode = nil, viewport, clip_mode
	defer { ctx.roots, ctx.viewport, ctx.clip_mode = saved_roots, saved_viewport, saved_clip }
	parent_style, valid := svg_source_style(ctx, ctx.parents[target], viewport)
	if !valid { return nil, false }
	ok = svg_compile_node(ctx, target, parent_style, transform)
	return ctx.roots[:], ok
}
@(private)
svg_wrap_effects :: proc(ctx: ^Svg_Build_Ctx, node: ^Xml_Node, style: Computed_Style, transform: Affine, before: int) -> bool {
	if len(ctx.roots) == before { return true }
	children := slice.clone(ctx.roots[before:])
	resize(&ctx.roots, before)
	if style.clip_path_id != "" {
		target := ctx.ids[style.clip_path_id]
		clip_transform := transform
		viewport := ctx.viewport
		if units, _ := svg_attr(target, "clipPathUnits"); units == "objectBoundingBox" {
			inverse, invertible := Affine_Invert(transform)
			if !invertible { return true }
			bounds, valid := svg_bounds_for_nodes(children, inverse)
			if !valid { return false }
			if bounds.empty || bounds.max.x == bounds.min.x || bounds.max.y == bounds.min.y { return true }
			size := bounds.max - bounds.min
			clip_transform = Affine_Compose(transform, {size.x, 0, 0, size.y, bounds.min.x, bounds.min.y})
			viewport = {1, 1}
		}
		clip_nodes, valid := svg_compile_definition(ctx, target, clip_transform, viewport, true)
		if !valid { return false }
		if len(clip_nodes) == 0 { return true }
		children = svg_single_node(Svg_Draw_Node{kind = .Clip, opacity = 1, children = children, clip_nodes = clip_nodes})
	}
	if style.mask_id != "" && !ctx.clip_mode {
		target := ctx.ids[style.mask_id]
		inverse, invertible := Affine_Invert(transform)
		if !invertible { return true }
		bounds, valid := svg_bounds_for_nodes(children, inverse)
		if !valid { return false }
		if bounds.empty { return true }
		size := bounds.max - bounds.min
		units, has_units := svg_attr(target, "maskUnits")
		object_units := !has_units || units == "objectBoundingBox"
		base := ctx.viewport
		if object_units { base = {1, 1} }
		x := svg_geometry_length(target, "x", base.x, -base.x * .1)
		y := svg_geometry_length(target, "y", base.y, -base.y * .1)
		w := svg_geometry_length(target, "width", base.x, base.x * 1.2)
		h := svg_geometry_length(target, "height", base.y, base.y * 1.2)
		if w == 0 || h == 0 { return true }
		region_transform := transform
		if object_units {
			if size.x == 0 || size.y == 0 { return true }
			region_transform = Affine_Compose(transform, {size.x, 0, 0, size.y, bounds.min.x, bounds.min.y})
		}
		mask_transform := transform
		mask_viewport := ctx.viewport
		if content_units, _ := svg_attr(target, "maskContentUnits"); content_units == "objectBoundingBox" {
			if size.x == 0 || size.y == 0 { return true }
			mask_transform = Affine_Compose(transform, {size.x, 0, 0, size.y, bounds.min.x, bounds.min.y})
			mask_viewport = {1, 1}
		}
		mask_nodes, mask_valid := svg_compile_definition(ctx, target, mask_transform, mask_viewport, false)
		if !mask_valid { return false }
		mask_style, style_valid := svg_source_style(ctx, target, mask_viewport)
		if !style_valid { return false }
		region: Path
		if Rectangle(&region, {x, y}, {w, h}) != .None { return false }
		mask_nodes = svg_single_node(Svg_Draw_Node{kind = .Clip, opacity = 1, children = mask_nodes, clip_items = slice.clone([]Svg_Path_Item{{commands = region.commands[:], transform = region_transform, fill_rule = .Nonzero}})})
		children = svg_single_node(Svg_Draw_Node{kind = .Mask, opacity = 1, children = children, mask_nodes = mask_nodes, mask_alpha = mask_style.mask_alpha})
	}
	if style.opacity != 1 && !ctx.clip_mode { children = svg_single_node(Svg_Draw_Node{kind = .Group, opacity = style.opacity, children = children}) }
	append(&ctx.roots, ..children)
	return !ctx.arena.failed
}
svg_compile_node :: proc(ctx: ^Svg_Build_Ctx, node: ^Xml_Node, inherited: Computed_Style, transform: Affine) -> bool {
	if node.kind != .Element || node.in_metadata { return true }
	if ctx.arena.failed { return false }
	ctx.expanded_nodes += 1
	if ctx.expanded_nodes > ctx.max_compile_nodes { svg_push(ctx.result, .Limit_Exceeded, fmt.tprintf("expanded nodes consumed %d, allowed %d", ctx.expanded_nodes, ctx.max_compile_nodes), node.line, node.column, node.name); return false }
	switch node.name {
	case "defs", "style", "title", "desc", "linearGradient", "radialGradient", "stop": return true
	case "symbol", "clipPath", "mask": if ctx.definition_target != node { return true }
	}
	style, valid := svg_resolve_element_style(node, inherited, ctx.viewport, ctx)
	if !valid { return false }
	if style.display == .None { return true }
	combined := Affine_Compose(transform, style.transform)
	for v in combined { if !finite(v) { svg_push(ctx.result, .Invalid_Value, "non-finite combined transform", node.line, node.column, node.name); return false } }
	if combined[0] * combined[3] - combined[1] * combined[2] == 0 { return true }
	before := len(ctx.roots)
	saved_viewport := ctx.viewport
	defer ctx.viewport = saved_viewport
	if node.name == "use" {
		ctx.ref_count += 1
		ctx.ref_depth += 1
		defer ctx.ref_depth -= 1
		if ctx.ref_count > ctx.limits.max_expanded_references || ctx.ref_depth > ctx.limits.max_reference_depth {
			svg_push(ctx.result, .Limit_Exceeded, fmt.tprintf("expanded references consumed %d, allowed %d", ctx.ref_count, ctx.limits.max_expanded_references), node.line, node.column, node.name)
			return false
		}
		id, _ := svg_attr_href(node)
		target := ctx.ids[id]
		if ctx.use_depth == len(ctx.use_chain) { svg_push(ctx.result, .Limit_Exceeded, "occurrence use depth exhausted", node.line, node.column, node.name); return false }
		ctx.use_chain[ctx.use_depth] = ctx.element_indices[node]
		ctx.use_depth += 1
		defer { ctx.use_depth -= 1; ctx.use_chain[ctx.use_depth] = 0 }
		x := svg_geometry_length(node, "x", ctx.viewport.x, 0)
		y := svg_geometry_length(node, "y", ctx.viewport.y, 0)
		use_transform := Affine_Compose(combined, {1, 0, 0, 1, x, y})
		if target.name == "symbol" || target.name == "svg" {
			// Instance sizing replaces the referenced viewport dimensions.
			w := svg_geometry_length(node, "width", ctx.viewport.x, svg_geometry_length(target, "width", ctx.viewport.x, ctx.viewport.x))
			h := svg_geometry_length(node, "height", ctx.viewport.y, svg_geometry_length(target, "height", ctx.viewport.y, ctx.viewport.y))
			if w == 0 || h == 0 { return true }
			ctx.viewport = {w, h}
		}
		saved_target, saved_instance := ctx.definition_target, ctx.instance_target
		ctx.definition_target, ctx.instance_target = target, target
		defer { ctx.definition_target, ctx.instance_target = saved_target, saved_instance }
		if !svg_compile_node(ctx, target, style, use_transform) { return false }
		return svg_wrap_effects(ctx, node, style, combined, before)
	}
	viewport_clip: Svg_Path_Item
	has_viewport_clip := false
	if node.name == "svg" || node.name == "symbol" {
		is_root := ctx.parents[node] == nil
		is_instance := ctx.instance_target == node
		w, h := ctx.viewport.x, ctx.viewport.y
		x, y := f64(0), f64(0)
		if !is_root { x, y = svg_geometry_length(node, "x", w, 0), svg_geometry_length(node, "y", h, 0) }
		if !is_root && !is_instance {
			x, y = svg_geometry_length(node, "x", w, 0), svg_geometry_length(node, "y", h, 0)
			w, h = svg_geometry_length(node, "width", w, w), svg_geometry_length(node, "height", h, h)
		}
		if w == 0 || h == 0 { return true }
		combined = Affine_Compose(combined, {1, 0, 0, 1, x, y})
		viewport_transform := combined
		ctx.viewport = {w, h}
		if value, found := svg_attr(node, "viewBox"); found {
			box, _ := svg_view_box(value)
			if box[2] == 0 || box[3] == 0 { return true }
			preserve, _ := svg_attr(node, "preserveAspectRatio")
			fit, _ := svg_fit_view_box(box, {w, h}, preserve)
			combined = Affine_Compose(combined, fit)
			ctx.viewport = {box[2], box[3]}
		}
		if !style.overflow_visible {
			clip: Path
			_ = Rectangle(&clip, {}, {w, h})
			viewport_clip = {commands = clip.commands[:], transform = viewport_transform, fill_rule = .Nonzero}
			has_viewport_clip = true
		}
	}
	if svg_is_shape_element(node.name) {
		if !svg_emit_shape(ctx, node, style, combined) { return false }
	} else {
		for &child in node.children { if !svg_compile_node(ctx, &child, style, combined) { return false } }
	}
	if !svg_wrap_effects(ctx, node, style, combined, before) { return false }
	if has_viewport_clip && len(ctx.roots) > before {
		children := slice.clone(ctx.roots[before:])
		resize(&ctx.roots, before)
		append(&ctx.roots, Svg_Draw_Node{kind = .Clip, opacity = 1, children = children, clip_items = slice.clone([]Svg_Path_Item{viewport_clip})})
	}
	return true
}


@(private)
svg_single_node :: proc(node: Svg_Draw_Node) -> []Svg_Draw_Node {
	return slice.clone([]Svg_Draw_Node{node})
}
