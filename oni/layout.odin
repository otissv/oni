package oni


Layout_Measure :: struct {
	text:  string,
	max_w: f32,
}

Layout_Node :: struct {
	ui_id:         UI_Id,
	config:        Resolved_Widget_Style,
	padding:       Pd,
	border:        Bd,
	desired:       Vec2,
	rect:          Rect,
	parent:        int,
	child_indices: [dynamic]int,
	measure:       Layout_Measure,
}

Layout_State :: struct {
	nodes:         [dynamic]Layout_Node,
	node_stack:    [dynamic]int,
	bounds_stack:  [dynamic]Rect,
	space_markers: [dynamic]int,
	id_to_node:    map[UI_Id]int,
}

layout_reset :: proc() {
	clear(&state.ui.layout.nodes)
	clear(&state.ui.layout.node_stack)
	clear(&state.ui.layout.bounds_stack)
	clear(&state.ui.layout.space_markers)
	clear(&state.ui.layout.id_to_node)
}

layout_config_direction :: proc(config: Resolved_Widget_Style) -> Direction_Layout {
	return config.direction
}

layout_config_gap :: proc(config: Resolved_Widget_Style) -> f32 {
	return f32(config.gap)
}

layout_config_justify :: proc(config: Resolved_Widget_Style) -> Justify_Pos {
	return config.justify
}

layout_merge_justify :: proc(parent, self: Justify_Pos) -> Justify_Pos {
	result := parent
	if _, x_ok := resolve_justify_x(self.x); x_ok do result.x = self.x
	if _, y_ok := resolve_justify_y(self.y); y_ok do result.y = self.y
	return result
}
layout_clamp_axis :: proc(value, min_v, max_v: f32) -> f32 {
	result := value
	if min_v > 0 do result = max(result, min_v)
	if max_v > 0 do result = min(result, max_v)
	return result
}

layout_content_rect :: proc(outer: Rect, padding: Pd) -> Rect {
	return {
		x = outer.x + padding.l,
		y = outer.y + padding.t,
		w = max(0, outer.w - padding.l - padding.r),
		h = max(0, outer.h - padding.t - padding.b),
	}
}

layout_inner_rect :: proc(outer: Rect, border: Bd, padding: Pd) -> Rect {
	return layout_content_rect(
		outer,
		{
			t = border.t + padding.t,
			b = border.b + padding.b,
			l = border.l + padding.l,
			r = border.r + padding.r,
		},
	)
}

layout_measure_text :: proc(config: Resolved_Widget_Style, text: string, max_w: f32) -> Vec2 {
	if len(text) == 0 do return {}

	resolved_font, layout_scale, ok := font_resolve(config.font, config.font_size, config.space)
	if !ok do return {}

	face := font_face_from_handle(resolved_font)
	if face == nil do return {}

	shape_max_w := max_w > 0 ? max_w / layout_scale : max_w
	lines := font_shape_line_build(face, text, shape_max_w, config.text_direction)
	if len(lines) == 0 do return {}
	defer font_destroy_shaped_lines(lines)

	line_height := config.font_size * config.line_height
	if line_height <= 0 do line_height = 0
	return font_measure_lines(face, lines, line_height, layout_scale)
}

layout_measure_leaf :: proc(node: ^Layout_Node) -> Vec2 {
	config := node.config
	size: Vec2

	if len(node.measure.text) > 0 {
		max_w := node.measure.max_w
		if max_w <= 0 && node.config.width.kind == .Fixed do max_w = node.config.width.value
		if max_w <= 0 && node.config.max_w > 0 do max_w = node.config.max_w
		size = layout_measure_text(config, node.measure.text, max_w)
	} else {
		width := length_resolve(node.config.width, 0)
		height := length_resolve(node.config.height, 0)
		if width <= 0 do width = node.desired.x
		if height <= 0 do height = node.desired.y
		if width <= 0 do width = config.min_w
		if height <= 0 do height = config.min_h
		size = {
			layout_clamp_axis(width, config.min_w, config.max_w),
			layout_clamp_axis(height, config.min_h, config.max_h),
		}
	}

	if length_is_definite(node.config.width) {
		if width := length_resolve(node.config.width, 0); width > 0 {
			size.x = layout_clamp_axis(width, config.min_w, config.max_w)
		}
	}
	if length_is_definite(node.config.height) {
		if height := length_resolve(node.config.height, 0); height > 0 {
			size.y = layout_clamp_axis(height, config.min_h, config.max_h)
		}
	}

	return size
}

layout_measure :: proc(node: ^Layout_Node) -> Vec2 {
	padding := node.padding
	border := node.border
	gap := layout_config_gap(node.config)
	direction := layout_config_direction(node.config)

	if len(node.child_indices) > 0 {
		main_sum: f32
		cross_max: f32

		for child_index in node.child_indices {
			child := &state.ui.layout.nodes[child_index]
			child_size := child.desired
			child_main := direction == .Horizontal ? child.config.width : child.config.height

			if child.config.flex > 0 && !length_is_definite(child_main) do continue

			switch direction {
			case .Horizontal:
				main_sum += child_size.x
				cross_max = max(cross_max, child_size.y)
			case .Vertical:
				main_sum += child_size.y
				cross_max = max(cross_max, child_size.x)
			}
		}

		if len(node.child_indices) > 1 {
			main_sum += gap * f32(len(node.child_indices) - 1)
		}

		inset_w := padding.l + padding.r + border.l + border.r
		inset_h := padding.t + padding.b + border.t + border.b

		switch direction {
		case .Horizontal:
			width := length_resolve(node.config.width, 0)
			height := length_resolve(node.config.height, 0)
			if width <= 0 do width = main_sum + inset_w
			if height <= 0 do height = cross_max + inset_h
			return {
				layout_clamp_axis(width, node.config.min_w, node.config.max_w),
				layout_clamp_axis(height, node.config.min_h, node.config.max_h),
			}
		case .Vertical:
			width := length_resolve(node.config.width, 0)
			height := length_resolve(node.config.height, 0)
			if width <= 0 do width = cross_max + inset_w
			if height <= 0 do height = main_sum + inset_h
			return {
				layout_clamp_axis(width, node.config.min_w, node.config.max_w),
				layout_clamp_axis(height, node.config.min_h, node.config.max_h),
			}
		}
	}

	return layout_measure_leaf(node)
}

layout_push_node :: proc(ui_id: UI_Id, config: Resolved_Widget_Style) -> ^Layout_Node {
	parent_index := -1
	if len(state.ui.layout.node_stack) > 0 {
		parent_index = state.ui.layout.node_stack[len(state.ui.layout.node_stack) - 1]
	}

	padding, _ := resolve_padding_value(config.padding)
	border, _ := resolve_border_value(config.border)

	node := Layout_Node {
		ui_id   = ui_id,
		config  = config,
		padding = padding,
		border  = border,
		parent  = parent_index,
	}
	append(&state.ui.layout.nodes, node)
	node_index := len(state.ui.layout.nodes) - 1

	if parent_index >= 0 {
		append(&state.ui.layout.nodes[parent_index].child_indices, node_index)
	}

	append(&state.ui.layout.node_stack, node_index)
	state.ui.layout.id_to_node[ui_id] = node_index
	return &state.ui.layout.nodes[node_index]
}

layout_set_measure_text :: proc(node: ^Layout_Node, text: string, max_w: f32) {
	node.measure.text = text
	node.measure.max_w = max_w
}

layout_pop_node :: proc() {
	if len(state.ui.layout.node_stack) == 0 do return

	node_index := state.ui.layout.node_stack[len(state.ui.layout.node_stack) - 1]
	ordered_remove(&state.ui.layout.node_stack, len(state.ui.layout.node_stack) - 1)

	node := &state.ui.layout.nodes[node_index]
	node.desired = layout_measure(node)
}

layout_resolve_node_size :: proc(node: ^Layout_Node, bounds: Rect) -> Vec2 {
	desired := node.desired

	width := length_resolve(node.config.width, bounds.w)
	height := length_resolve(node.config.height, bounds.h)
	if width <= 0 do width = desired.x
	if height <= 0 do height = desired.y

	if width <= 0 && bounds.w > 0 do width = bounds.w
	if height <= 0 && bounds.h > 0 do height = bounds.h

	return {
		layout_clamp_axis(width, node.config.min_w, node.config.max_w),
		layout_clamp_axis(height, node.config.min_h, node.config.max_h),
	}
}

layout_apply_definite_size :: proc(node: ^Layout_Node, bounds: Rect, size: ^Vec2) {
	resolved := layout_resolve_node_size(node, bounds)
	if length_is_definite(node.config.width) do size.x = resolved.x
	if length_is_definite(node.config.height) do size.y = resolved.y
}

layout_child_main_size :: proc(
	child: ^Layout_Node,
	is_horizontal: bool,
	flex_unit: f32,
	parent_main: f32,
) -> f32 {
	main_len := is_horizontal ? child.config.width : child.config.height
	main_fixed := length_resolve(main_len, parent_main)
	if main_fixed > 0 do return main_fixed

	if child.config.flex > 0 && flex_unit > 0 {
		desired_main := is_horizontal ? child.desired.x : child.desired.y
		return max(desired_main, flex_unit * child.config.flex)
	}

	return is_horizontal ? child.desired.x : child.desired.y
}

layout_child_cross_size :: proc(
	child: ^Layout_Node,
	is_horizontal: bool,
	cross_available: f32,
	justify: Justify_Pos,
) -> f32 {
	cross_len := is_horizontal ? child.config.height : child.config.width
	cross_fixed := length_resolve(cross_len, cross_available)
	if cross_fixed > 0 do return cross_fixed

	cross_stretch := child.config.flex > 0
	if is_horizontal {
		cross_stretch ||= justify_axis_is_stretch_y(justify.y)
	} else {
		cross_stretch ||= justify_axis_is_stretch_x(justify.x)
	}

	if cross_stretch && cross_available > 0 {
		return cross_available
	}

	return is_horizontal ? child.desired.y : child.desired.x
}

layout_axis_main_offset :: proc(free_space, group_main: f32, align: i32) -> f32 {
	switch align {
	case 1:
		return max(0, (free_space - group_main) * 0.5)
	case 2:
		return max(0, free_space - group_main)
	}
	return 0
}

layout_axis_cross_offset :: proc(free_space, child_cross: f32, align: i32) -> f32 {
	switch align {
	case 1:
		return max(0, (free_space - child_cross) * 0.5)
	case 2:
		return max(0, free_space - child_cross)
	}
	return 0
}

layout_position_children :: proc(node: ^Layout_Node, content: Rect) {
	if len(node.child_indices) == 0 do return

	direction := layout_config_direction(node.config)
	gap := layout_config_gap(node.config)
	justify := layout_config_justify(node.config)
	is_horizontal := direction == .Horizontal

	main_available := is_horizontal ? content.w : content.h
	cross_available := is_horizontal ? content.h : content.w

	flex_total: f32
	fixed_total: f32

	child_sizes: [dynamic]Vec2
	defer delete(child_sizes)
	resize(&child_sizes, len(node.child_indices))

	for child_index in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		child_main := is_horizontal ? child.config.width : child.config.height

		if child.config.flex > 0 && !length_is_definite(child_main) {
			flex_total += child.config.flex
		} else {
			main := layout_child_main_size(child, is_horizontal, 0, main_available)
			fixed_total += main
		}
	}

	if len(node.child_indices) > 1 {
		fixed_total += gap * f32(len(node.child_indices) - 1)
	}

	remaining := max(0, main_available - fixed_total)
	flex_unit := flex_total > 0 ? remaining / flex_total : 0

	for child_index, i in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		child_justify := layout_merge_justify(justify, child.config.self)
		main := layout_child_main_size(child, is_horizontal, flex_unit, main_available)
		cross := layout_child_cross_size(child, is_horizontal, cross_available, child_justify)
		child_sizes[i] = is_horizontal ? Vec2{main, cross} : Vec2{cross, main}
		layout_apply_definite_size(child, content, &child_sizes[i])
	}

	total_main: f32
	for size in child_sizes {
		total_main += is_horizontal ? size.x : size.y
	}
	if len(node.child_indices) > 1 {
		total_main += gap * f32(len(node.child_indices) - 1)
	}

	main_free := max(0, main_available - total_main)
	main_start: f32
	if is_horizontal {
		main_start = layout_axis_main_offset(
			main_free,
			total_main,
			justify_axis_align_from_x(justify.x),
		)
	} else {
		main_start = layout_axis_main_offset(
			main_free,
			total_main,
			justify_axis_align_from_y(justify.y),
		)
	}

	main_cursor := main_start
	for child_index, i in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		child_justify := layout_merge_justify(justify, child.config.self)
		size := child_sizes[i]

		main := is_horizontal ? size.x : size.y
		cross := is_horizontal ? size.y : size.x

		x, y: f32
		if is_horizontal {
			x = content.x + main_cursor
			y =
				content.y +
				layout_axis_cross_offset(
					cross_available,
					cross,
					justify_axis_align_from_y(child_justify.y),
				)
		} else {
			x =
				content.x +
				layout_axis_cross_offset(
					cross_available,
					cross,
					justify_axis_align_from_x(child_justify.x),
				)
			y = content.y + main_cursor
		}

		x += child.config.x
		y += child.config.y

		child.rect = {
			x = x,
			y = y,
			w = size.x,
			h = size.y,
		}

		if len(child.child_indices) > 0 {
			layout_position_children(
				child,
				layout_inner_rect(child.rect, child.border, child.padding),
			)
		}

		main_cursor += main
		if i + 1 < len(node.child_indices) do main_cursor += gap
	}
}

layout_solve_node :: proc(node: ^Layout_Node, bounds: Rect) {
	size := layout_resolve_node_size(node, bounds)

	x := bounds.x
	y := bounds.y
	if node.config.x != 0 do x += node.config.x
	if node.config.y != 0 do y += node.config.y

	node.rect = {
		x = x,
		y = y,
		w = size.x,
		h = size.y,
	}

	if len(node.child_indices) > 0 {
		layout_position_children(node, layout_inner_rect(node.rect, node.border, node.padding))
	}
}

layout_solve :: proc(root: ^Layout_Node, bounds: Rect) {
	layout_solve_node(root, bounds)
}

layout_space_bounds :: proc(space: Draw_Space) -> Rect {
	logical_w := f32(state.dpi.logical_w)
	logical_h := f32(state.dpi.logical_h)

	if space == .Artboard {
		zoom := view_effective_zoom()
		if zoom <= 0 do zoom = 1
		return {0, 0, logical_w / zoom, logical_h / zoom}
	}

	return {0, 0, logical_w, logical_h}
}

layout_begin_space :: proc(space: Draw_Space) {
	append(&state.ui.layout.bounds_stack, layout_space_bounds(space))
	append(&state.ui.layout.space_markers, len(state.ui.layout.nodes))
}

layout_end_space :: proc() {
	if len(state.ui.layout.bounds_stack) == 0 do return

	bounds := state.ui.layout.bounds_stack[len(state.ui.layout.bounds_stack) - 1]
	marker := state.ui.layout.space_markers[len(state.ui.layout.space_markers) - 1]

	ordered_remove(&state.ui.layout.bounds_stack, len(state.ui.layout.bounds_stack) - 1)
	ordered_remove(&state.ui.layout.space_markers, len(state.ui.layout.space_markers) - 1)

	for node_index in marker ..< len(state.ui.layout.nodes) {
		node := &state.ui.layout.nodes[node_index]
		if node.parent >= 0 do continue
		layout_solve(node, bounds)
	}
}
