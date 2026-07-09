package oni


/*
Optional text and wrap width used to measure a layout node intrinsically.
*/
Layout_Measure :: struct {
	text:  string,
	max_w: f32,
}

/*
One node in the flex layout tree with resolved style, geometry, and children.
*/
Layout_Node :: struct {
	ui_id:         UI_Id,
	kind:          Widget_Kind,
	config:        Resolved_Widget_Style,
	padding:       Pd,
	border:        Bd,
	desired:       Vec2,
	rect:          Rect,
	parent:        int,
	child_indices: [dynamic]int,
	measure:       Layout_Measure,
}

/*
Column widths and row heights computed for a table with TABLE_CELL alignment.
*/
Layout_Table_Tracks :: struct {
	rows:        [dynamic]int,
	col_widths:  [dynamic]f32,
	row_heights: [dynamic]f32,
}

/*
Per-frame flex layout tree, stacks, and UI_Id to node index map.
*/
Layout_State :: struct {
	nodes:         [dynamic]Layout_Node,
	node_stack:    [dynamic]int,
	bounds_stack:  [dynamic]Rect,
	space_markers: [dynamic]int,
	id_to_node:    map[UI_Id]int,
	table_tracks:  map[int]Layout_Table_Tracks,
}

@(private)
layout_release_node_children :: proc(layout: ^Layout_State) {
	for &node in layout.nodes {
		delete(node.child_indices)
	}
}

/*
Clears all layout nodes, stacks, and id-to-node mappings.

Called at the start of each UI frame.
*/
layout_reset :: proc() {
	for _, tracks in state.ui.layout.table_tracks {
		delete(tracks.rows)
		delete(tracks.col_widths)
		delete(tracks.row_heights)
	}
	clear(&state.ui.layout.table_tracks)
	layout_release_node_children(&state.ui.layout)
	clear(&state.ui.layout.nodes)
	clear(&state.ui.layout.node_stack)
	clear(&state.ui.layout.bounds_stack)
	clear(&state.ui.layout.space_markers)
	clear(&state.ui.layout.id_to_node)
}

/*
Releases all heap-owned layout storage.

Call during UI shutdown after the final layout_reset.
*/
layout_shutdown :: proc() {
	delete(state.ui.layout.nodes)
	state.ui.layout.nodes = nil
	delete(state.ui.layout.node_stack)
	state.ui.layout.node_stack = nil
	delete(state.ui.layout.bounds_stack)
	state.ui.layout.bounds_stack = nil
	delete(state.ui.layout.space_markers)
	state.ui.layout.space_markers = nil
}

/*
Returns the flex direction from a resolved widget style.
*/
layout_config_direction :: proc(config: Resolved_Widget_Style) -> Direction_Layout {
	return config.direction
}

/*
Derived axis, wrap, and reverse flags for a Direction_Layout value.
*/
Layout_Direction_Info :: struct {
	is_horizontal:    bool,
	is_wrap:          bool,
	is_main_reverse:  bool,
	is_cross_reverse: bool,
}

/*
Derives axis, wrap, and reverse flags from a layout direction enum.
*/
layout_direction_info :: proc(direction: Direction_Layout) -> Layout_Direction_Info {
	switch direction {
	case .HORIZONTAL:
		return {is_horizontal = true}
	case .VERTICAL:
		return {}
	case .HORIZONTAL_WRAP:
		return {is_horizontal = true, is_wrap = true}
	case .VERTICAL_WRAP:
		return {is_wrap = true}
	case .HORIZONTAL_REVERSE:
		return {is_horizontal = true, is_main_reverse = true}
	case .VERTICAL_REVERSE:
		return {is_main_reverse = true}
	case .HORIZONTAL_WRAP_REVERSE:
		return {
			is_horizontal = true,
			is_wrap = true,
			is_main_reverse = true,
			is_cross_reverse = true,
		}
	case .VERTICAL_WRAP_REVERSE:
		return {is_wrap = true, is_main_reverse = true, is_cross_reverse = true}
	}
	unreachable()
}

/*
Returns whether a layout direction flows horizontally.
*/
layout_direction_is_horizontal :: proc(direction: Direction_Layout) -> bool {
	return layout_direction_info(direction).is_horizontal
}

/*
Returns whether a layout direction enables line wrapping.
*/
layout_direction_is_wrap :: proc(direction: Direction_Layout) -> bool {
	return layout_direction_info(direction).is_wrap
}

/*
Mirrors a position within available space for reverse flow axes.
*/
layout_mirror_in_available :: proc(pos, size, available: f32) -> f32 {
	return available - pos - size
}

/*
One wrapped line segment within a flex container during layout.
*/
Layout_Wrap_Line :: struct {
	start:     int,
	count:     int,
	main_sum:  f32,
	cross_max: f32,
}

/*
Computes the main-axis wrap limit from node config and insets.
*/
layout_wrap_main_limit_from_config :: proc(node: ^Layout_Node, is_horizontal: bool) -> f32 {
	main_len := is_horizontal ? node.config.width : node.config.height
	main_max := is_horizontal ? node.config.max_w : node.config.max_h
	main := length_resolve(main_len, 0)
	if main <= 0 && main_max > 0 do main = main_max

	if main <= 0 do return 0

	inset: f32
	if is_horizontal {
		inset = node.padding.l + node.padding.r + node.border.l + node.border.r
	} else {
		inset = node.padding.t + node.padding.b + node.border.t + node.border.b
	}
	return max(0, main - inset)
}

/*
Returns a child's size along the main axis for wrap layout.
*/
layout_wrap_child_main :: proc(size: Vec2, is_horizontal: bool) -> f32 {
	return is_horizontal ? size.x : size.y
}

/*
Returns a child's size along the cross axis for wrap layout.
*/
layout_wrap_child_cross :: proc(size: Vec2, is_horizontal: bool) -> f32 {
	return is_horizontal ? size.y : size.x
}

/*
Groups children into wrap lines given a main-axis size limit.
*/
layout_wrap_build_lines :: proc(
	sizes: []Vec2,
	is_horizontal: bool,
	gap: f32,
	main_limit: f32,
) -> [dynamic]Layout_Wrap_Line {
	lines: [dynamic]Layout_Wrap_Line
	if len(sizes) == 0 do return lines

	current: Layout_Wrap_Line

	for size, i in sizes {
		main := layout_wrap_child_main(size, is_horizontal)
		cross := layout_wrap_child_cross(size, is_horizontal)

		if current.count > 0 && main_limit > 0 {
			needed := current.main_sum + gap + main
			if needed > main_limit {
				append(&lines, current)
				current = {}
			}
		}

		if current.count == 0 do current.start = i
		if current.count > 0 do current.main_sum += gap
		current.main_sum += main
		current.cross_max = max(current.cross_max, cross)
		current.count += 1
	}

	if current.count > 0 do append(&lines, current)
	return lines
}

/*
Measures a wrap container's natural size from child desired sizes.
*/
layout_wrap_measure :: proc(node: ^Layout_Node, is_horizontal: bool, gap: f32) -> Vec2 {
	sizes: [dynamic]Vec2
	defer delete(sizes)
	resize(&sizes, len(node.child_indices))

	for child_index, i in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		sizes[i] = child.desired
	}

	main_limit := layout_wrap_main_limit_from_config(node, is_horizontal)
	lines := layout_wrap_build_lines(sizes[:], is_horizontal, gap, main_limit)
	defer delete(lines)

	main_natural: f32
	cross_sum: f32
	for line, i in lines {
		main_natural = max(main_natural, line.main_sum)
		cross_sum += line.cross_max
		if i + 1 < len(lines) do cross_sum += gap
	}

	inset_w := node.padding.l + node.padding.r + node.border.l + node.border.r
	inset_h := node.padding.t + node.padding.b + node.border.t + node.border.b

	width := length_resolve(node.config.width, 0)
	height := length_resolve(node.config.height, 0)

	if is_horizontal {
		if width <= 0 do width = (main_limit > 0 ? main_limit : main_natural) + inset_w
		if height <= 0 do height = cross_sum + inset_h
	} else {
		if height <= 0 do height = (main_limit > 0 ? main_limit : main_natural) + inset_h
		if width <= 0 do width = cross_sum + inset_w
	}

	return {
		layout_clamp_axis(width, node.config.min_w, node.config.max_w),
		layout_clamp_axis(height, node.config.min_h, node.config.max_h),
	}
}

/*
Returns the inter-child gap from a resolved widget style.
*/
layout_config_gap :: proc(config: Resolved_Widget_Style) -> f32 {
	return f32(config.gap)
}

/*
Returns the justify alignment from a resolved widget style.
*/
layout_config_justify :: proc(config: Resolved_Widget_Style) -> Justify_Pos {
	return config.justify
}

/*
Merges parent justify with child self-alignment overrides per axis.
*/
layout_merge_justify :: proc(parent, self: Justify_Pos) -> Justify_Pos {
	result := parent
	if _, x_ok := resolve_justify_x(self.x); x_ok do result.x = self.x
	if _, y_ok := resolve_justify_y(self.y); y_ok do result.y = self.y
	return result
}
/*
Clamps a size to optional min and max constraints when they are positive.
*/
layout_clamp_axis :: proc(value, min_v, max_v: f32) -> f32 {
	result := value
	if min_v > 0 do result = max(result, min_v)
	if max_v > 0 do result = min(result, max_v)
	return result
}

/*
Shrinks an outer rect inward by padding to the content box.
*/
layout_content_rect :: proc(outer: Rect, padding: Pd) -> Rect {
	return {
		x = outer.x + padding.l,
		y = outer.y + padding.t,
		w = max(0, outer.w - padding.l - padding.r),
		h = max(0, outer.h - padding.t - padding.b),
	}
}

/*
Shrinks an outer rect inward by border and padding to the inner box.
*/
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

/*
Measures shaped text size for a widget style and optional max width.
*/
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

/*
Measures a leaf node's size from text or explicit dimensions.
*/
layout_measure_leaf :: proc(node: ^Layout_Node) -> Vec2 {
	config := node.config
	size: Vec2

	if len(node.measure.text) > 0 {
		max_w := node.measure.max_w
		if max_w <= 0 && node.config.width.kind == .FIXED do max_w = node.config.width.value
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

/*
Measures a node's desired size from children or leaf content.
*/
layout_measure :: proc(node: ^Layout_Node) -> Vec2 {
	padding := node.padding
	border := node.border
	gap := layout_config_gap(node.config)
	direction := layout_config_direction(node.config)

	if len(node.child_indices) > 0 {
		info := layout_direction_info(direction)

		if info.is_wrap {
			return layout_wrap_measure(node, info.is_horizontal, gap)
		}

		child_sizes: [dynamic]Vec2
		child_nodes: [dynamic]^Layout_Node
		defer delete(child_sizes)
		defer delete(child_nodes)

		for child_index in node.child_indices {
			child := &state.ui.layout.nodes[child_index]
			append(&child_nodes, child)
			append(&child_sizes, child.desired)
		}

		justify := layout_config_justify(node.config)
		layout_apply_content_align_sizes(justify, child_nodes[:], child_sizes[:])

		main_sum: f32
		cross_max: f32
		for child, i in child_nodes {
			child_main := info.is_horizontal ? child.config.width : child.config.height
			if child.config.flex > 0 && !length_is_definite(child_main) do continue

			if info.is_horizontal {
				main_sum += child_sizes[i].x
				cross_max = max(cross_max, child_sizes[i].y)
			} else {
				main_sum += child_sizes[i].y
				cross_max = max(cross_max, child_sizes[i].x)
			}
		}

		if len(node.child_indices) > 1 {
			main_sum += gap * f32(len(node.child_indices) - 1)
		}

		inset_w := padding.l + padding.r + border.l + border.r
		inset_h := padding.t + padding.b + border.t + border.b

		if info.is_horizontal {
			width := length_resolve(node.config.width, 0)
			height := length_resolve(node.config.height, 0)
			if width <= 0 do width = main_sum + inset_w
			if height <= 0 do height = cross_max + inset_h
			return {
				layout_clamp_axis(width, node.config.min_w, node.config.max_w),
				layout_clamp_axis(height, node.config.min_h, node.config.max_h),
			}
		} else {
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

/*
Creates a layout node, links it to the parent, and pushes it on the stack.
*/
layout_push_node :: proc(ui_id: UI_Id, config: Resolved_Widget_Config) -> ^Layout_Node {
	parent_index := -1
	if len(state.ui.layout.node_stack) > 0 {
		parent_index = state.ui.layout.node_stack[len(state.ui.layout.node_stack) - 1]
	}

	padding, _ := resolve_padding_value(config.padding)
	border, _ := resolve_border_value(config.border)

	node := Layout_Node {
		ui_id   = ui_id,
		kind    = config.kind,
		config  = config.style,
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

/*
Attaches text and max-width hints for leaf text measurement.
*/
layout_set_measure_text :: proc(node: ^Layout_Node, text: string, max_w: f32) {
	node.measure.text = text
	node.measure.max_w = max_w
}

/*
Sets an explicit desired size on a layout node.
*/
layout_set_measure_size :: proc(node: ^Layout_Node, size: Vec2) {
	node.desired = size
}

/*
Pops the current node from the stack and stores its measured size.
*/
layout_pop_node :: proc() {
	if len(state.ui.layout.node_stack) == 0 do return

	node_index := state.ui.layout.node_stack[len(state.ui.layout.node_stack) - 1]
	ordered_remove(&state.ui.layout.node_stack, len(state.ui.layout.node_stack) - 1)

	node := &state.ui.layout.nodes[node_index]
	node.desired = layout_measure(node)
}

/*
Resolves final width and height for a node within bounds.
*/
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

/*
Overwrites size axes that have definite length constraints.
*/
layout_apply_definite_size :: proc(node: ^Layout_Node, bounds: Rect, size: ^Vec2) {
	resolved := layout_resolve_node_size(node, bounds)
	if length_is_definite(node.config.width) do size.x = resolved.x
	if length_is_definite(node.config.height) do size.y = resolved.y
}

/*
Computes a child's main-axis size including flex distribution.
*/
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

/*
Returns whether a child participates in main-axis flow layout.
*/
layout_child_in_main_flow :: proc(child: ^Layout_Node, is_horizontal: bool) -> bool {
	self := child.config.self
	if is_horizontal {
		_, ok := resolve_justify_x(self.x)
		return !ok
	}
	_, ok := resolve_justify_y(self.y)
	return !ok
}

/*
Computes a child's cross-axis size including stretch alignment.
*/
layout_child_cross_size :: proc(
	child: ^Layout_Node,
	is_horizontal: bool,
	cross_available: f32,
	justify: Justify_Pos,
) -> f32 {
	cross_len := is_horizontal ? child.config.height : child.config.width
	cross_fixed := length_resolve(cross_len, cross_available)
	if cross_fixed > 0 do return cross_fixed

	self := child.config.self
	cross_stretch := child.config.flex > 0
	if is_horizontal {
		if _, y_ok := resolve_justify_y(self.y); y_ok {
			cross_stretch ||= justify_axis_is_stretch_y(self.y)
		} else {
			cross_stretch ||= justify_axis_is_stretch_y(justify.y)
		}
	} else {
		if _, x_ok := resolve_justify_x(self.x); x_ok {
			cross_stretch ||= justify_axis_is_stretch_x(self.x)
		} else {
			cross_stretch ||= justify_axis_is_stretch_x(justify.x)
		}
	}

	if cross_stretch && cross_available > 0 {
		return cross_available
	}

	return is_horizontal ? child.desired.y : child.desired.x
}

/*
Returns the layout node index for a node pointer in a layout tree.
*/
layout_node_index_in :: proc(layout: ^Layout_State, node: ^Layout_Node) -> int {
	for &n, i in layout.nodes {
		if &n == node do return i
	}
	return -1
}

/*
Returns the layout node index for a node pointer in the current layout tree.
*/
layout_node_index :: proc(node: ^Layout_Node) -> int {
	return layout_node_index_in(&state.ui.layout, node)
}

/*
Walks ancestors to find the nearest TABLE layout node index.
*/
layout_find_table_ancestor_in :: proc(layout: ^Layout_State, node_index: int) -> int {
	parent := node_index
	for parent >= 0 {
		node := &layout.nodes[parent]
		if node.kind == .TABLE do return parent
		parent = node.parent
	}
	return -1
}

/*
Walks ancestors to find the nearest TABLE layout node index.
*/
layout_find_table_ancestor :: proc(node_index: int) -> int {
	return layout_find_table_ancestor_in(&state.ui.layout, node_index)
}

/*
Returns whether a widget kind represents a table data cell.
*/
layout_node_is_table_cell :: proc(kind: Widget_Kind) -> bool {
	return kind == .TABLE_CELL || kind == .TABLE_HEADING
}

/*
Returns whether a justify position uses TABLE_CELL on the x axis.
*/
layout_justify_uses_TABLE_CELL_x :: proc(justify: Justify_Pos) -> bool {
	align, ok := justify_align_from_x(justify.x)
	return ok && align == .TABLE_CELL
}

/*
Returns whether a justify position uses TABLE_CELL on the y axis.
*/
layout_justify_uses_TABLE_CELL_y :: proc(justify: Justify_Pos) -> bool {
	align, ok := justify_align_from_y(justify.y)
	return ok && align == .TABLE_CELL
}

/*
Returns a cell's intrinsic size along one axis for table track sizing.
*/
layout_table_cell_intrinsic_axis :: proc(cell: ^Layout_Node, horizontal: bool) -> f32 {
	if horizontal {
		if length_is_definite(cell.config.width) {
			return length_resolve(cell.config.width, 0)
		}
		return cell.desired.x
	}
	if length_is_definite(cell.config.height) {
		return length_resolve(cell.config.height, 0)
	}
	return cell.desired.y
}

/*
Collects TABLE_ROW node indices under a table in document order.
*/
layout_table_collect_rows_in :: proc(layout: ^Layout_State, table_index: int) -> [dynamic]int {
	rows: [dynamic]int
	stack: [dynamic]int
	defer delete(stack)

	table := &layout.nodes[table_index]
	for i := len(table.child_indices) - 1; i >= 0; i -= 1 {
		append(&stack, table.child_indices[i])
	}

	for len(stack) > 0 {
		idx := stack[len(stack) - 1]
		ordered_remove(&stack, len(stack) - 1)
		node := &layout.nodes[idx]

		if node.kind == .TABLE_ROW {
			append(&rows, idx)
		}

		for i := len(node.child_indices) - 1; i >= 0; i -= 1 {
			append(&stack, node.child_indices[i])
		}
	}

	return rows
}

/*
Finds a row's index inside prepared table track data.
*/
layout_table_row_track_index :: proc(tracks: ^Layout_Table_Tracks, row_index: int) -> (int, bool) {
	for row_node_index, track_i in tracks.rows {
		if row_node_index == row_index do return track_i, true
	}
	return 0, false
}

/*
Computes shared column widths and row heights for a table with TABLE_CELL rows.
*/
layout_table_prepare_in :: proc(layout: ^Layout_State, table_index: int) {
	table := &layout.nodes[table_index]
	if table.kind != .TABLE do return

	rows := layout_table_collect_rows_in(layout, table_index)
	if len(rows) == 0 {
		delete(rows)
		return
	}

	uses_x := false
	uses_y := false
	for row_index in rows {
		row := &layout.nodes[row_index]
		uses_x ||= layout_justify_uses_TABLE_CELL_x(row.config.justify)
		uses_y ||= layout_justify_uses_TABLE_CELL_y(row.config.justify)
	}
	if !uses_x && !uses_y {
		delete(rows)
		return
	}

	col_count := 0
	for row_index in rows {
		row := &layout.nodes[row_index]
		col_count = max(col_count, len(row.child_indices))
	}

	col_widths: [dynamic]f32
	row_heights: [dynamic]f32
	resize(&col_widths, col_count)
	resize(&row_heights, len(rows))

	if uses_x {
		for col in 0 ..< col_count {
			max_w: f32
			for row_index in rows {
				row := &layout.nodes[row_index]
				if col >= len(row.child_indices) do continue
				child := &layout.nodes[row.child_indices[col]]
				if !layout_node_is_table_cell(child.kind) do continue
				max_w = max(max_w, layout_table_cell_intrinsic_axis(child, true))
			}
			col_widths[col] = max_w
		}
	}

	if uses_y {
		for row_node_index, track_i in rows {
			row := &layout.nodes[row_node_index]
			if !layout_justify_uses_TABLE_CELL_y(row.config.justify) do continue

			max_h: f32
			for child_idx in row.child_indices {
				child := &layout.nodes[child_idx]
				if !layout_node_is_table_cell(child.kind) do continue
				max_h = max(max_h, layout_table_cell_intrinsic_axis(child, false))
			}
			row_heights[track_i] = max_h
		}
	}

	if existing, ok := &layout.table_tracks[table_index]; ok {
		delete(existing.rows)
		delete(existing.col_widths)
		delete(existing.row_heights)
	}

	layout.table_tracks[table_index] = Layout_Table_Tracks {
		rows        = rows,
		col_widths  = col_widths,
		row_heights = row_heights,
	}
}

/*
Computes shared column widths and row heights for a table with TABLE_CELL rows.
*/
layout_table_prepare :: proc(table_index: int) {
	layout_table_prepare_in(&state.ui.layout, table_index)
}

/*
Applies prepared table track sizes to a cell when its row uses TABLE_CELL.
*/
layout_table_apply_cell_size :: proc(
	row: ^Layout_Node,
	tracks: ^Layout_Table_Tracks,
	row_track_index: int,
	col_index: int,
	child: ^Layout_Node,
	content: Rect,
) -> Vec2 {
	size := child.desired
	use_x := layout_justify_uses_TABLE_CELL_x(row.config.justify)
	use_y := layout_justify_uses_TABLE_CELL_y(row.config.justify)

	if use_x && col_index < len(tracks.col_widths) && !length_is_definite(child.config.width) {
		size.x = tracks.col_widths[col_index]
	}
	if use_y && !length_is_definite(child.config.height) {
		size.y = tracks.row_heights[row_track_index]
	}

	layout_apply_definite_size(child, content, &size)
	return size
}

/*
Extracts the main-axis justify align from a justify position.
*/
layout_main_justify_align :: proc(
	justify: Justify_Pos,
	is_horizontal: bool,
) -> (
	Justify_Align,
	bool,
) {
	if is_horizontal {
		return justify_align_from_x(justify.x)
	}
	return justify_align_from_y(justify.y)
}

/*
Extracts the cross-axis justify align from a justify position.
*/
layout_cross_justify_align :: proc(
	justify: Justify_Pos,
	is_horizontal: bool,
) -> (
	Justify_Align,
	bool,
) {
	if is_horizontal {
		return justify_align_from_y(justify.y)
	}
	return justify_align_from_x(justify.x)
}

/*
Computes leading inset for space-distribution justify modes.
*/
layout_space_leading :: proc(align: Justify_Align, free: f32, count: int) -> f32 {
	if count <= 0 do return 0

	#partial switch align {
	case .SPACE_BETWEEN:
		return 0
	case .SPACE_AROUND:
		return free / (2 * f32(count))
	case .SPACE_EVENLY:
		return free / f32(count + 1)
	}
	return 0
}

/*
Computes gap between items for space-distribution justify modes.
*/
/*
Returns the target size for a content-align mode from sibling extrema.
*/
layout_content_align_target :: proc(align: Justify_Align, max_v, min_v: f32) -> (f32, bool) {
	#partial switch align {
	case .MAX_CONTENT:
		return max_v, true
	case .MIN_CONTENT:
		return min_v, true
	}
	return 0, false
}

/*
Computes max and min values from a list of sibling axis sizes.
*/
layout_sibling_axis_extrema :: proc(sizes: []f32) -> (max_v, min_v: f32, ok: bool) {
	if len(sizes) == 0 do return 0, 0, false

	max_v = sizes[0]
	min_v = sizes[0]
	for size in sizes[1:] {
		max_v = max(max_v, size)
		min_v = min(min_v, size)
	}
	return max_v, min_v, true
}

/*
Applies a content-align mode to one axis size using sibling extrema.
*/
layout_apply_content_align_axis :: proc(align: Justify_Align, current, max_v, min_v: f32) -> f32 {
	if target, ok := layout_content_align_target(align, max_v, min_v); ok {
		return target
	}
	return current
}

/*
Equalizes one axis of child sizes to sibling max/min when parent justify requests it.

Children with definite width or height keep their provided size but still
participate in sibling extrema.
*/
layout_apply_content_align_sizes_indices :: proc(
	justify: Justify_Pos,
	children: []^Layout_Node,
	child_sizes: []Vec2,
	indices: []int,
) {
	if len(indices) == 0 do return

	if align, ok := justify_align_from_x(justify.x); ok && justify_align_is_content(align) {
		sizes: [dynamic]f32
		defer delete(sizes)
		for idx in indices {
			append(&sizes, child_sizes[idx].x)
		}

		max_v, min_v, extrema_ok := layout_sibling_axis_extrema(sizes[:])
		if extrema_ok {
			for idx in indices {
				child := children[idx]
				if length_is_definite(child.config.width) do continue
				child_sizes[idx].x = layout_apply_content_align_axis(
					align,
					child_sizes[idx].x,
					max_v,
					min_v,
				)
			}
		}
	}

	if align, ok := justify_align_from_y(justify.y); ok && justify_align_is_content(align) {
		sizes: [dynamic]f32
		defer delete(sizes)
		for idx in indices {
			append(&sizes, child_sizes[idx].y)
		}

		max_v, min_v, extrema_ok := layout_sibling_axis_extrema(sizes[:])
		if extrema_ok {
			for idx in indices {
				child := children[idx]
				if length_is_definite(child.config.height) do continue
				child_sizes[idx].y = layout_apply_content_align_axis(
					align,
					child_sizes[idx].y,
					max_v,
					min_v,
				)
			}
		}
	}
}

/*
Equalizes child sizes for all children in a container.
*/
layout_apply_content_align_sizes :: proc(
	justify: Justify_Pos,
	children: []^Layout_Node,
	child_sizes: []Vec2,
) {
	indices: [dynamic]int
	defer delete(indices)
	resize(&indices, len(children))
	for i in 0 ..< len(children) {
		indices[i] = i
	}
	layout_apply_content_align_sizes_indices(justify, children, child_sizes, indices[:])
}

layout_space_between_items :: proc(align: Justify_Align, free: f32, count: int) -> f32 {
	if count <= 1 do return 0

	#partial switch align {
	case .SPACE_BETWEEN:
		return free / f32(count - 1)
	case .SPACE_AROUND:
		return free / f32(count)
	case .SPACE_EVENLY:
		return free / f32(count + 1)
	}
	return 0
}

/*
Computes main-axis positions for space-distribution alignment.
*/
layout_space_positions :: proc(
	align: Justify_Align,
	available: f32,
	sizes: []f32,
	gap: f32,
) -> [dynamic]f32 {
	positions: [dynamic]f32
	count := len(sizes)
	if count == 0 do return positions

	total: f32
	for size in sizes do total += size
	if count > 1 do total += gap * f32(count - 1)

	free := max(0, available - total)
	leading := layout_space_leading(align, free, count)
	between := layout_space_between_items(align, free, count)

	cursor := leading
	for i in 0 ..< count {
		append(&positions, cursor)
		if i + 1 < count {
			cursor += sizes[i] + gap + between
		}
	}

	return positions
}

/*
Positions one child rect and recursively lays out its descendants.
*/
layout_position_child_rect :: proc(
	child: ^Layout_Node,
	content: Rect,
	size: Vec2,
	main_pos: f32,
	cross_pos: f32,
	is_horizontal: bool,
	justify: Justify_Pos,
	in_flow_main: bool,
	in_flow_cross: bool,
) {
	child_justify := layout_merge_justify(justify, child.config.self)
	self := child.config.self
	_, self_x_ok := resolve_justify_x(self.x)
	_, self_y_ok := resolve_justify_y(self.y)

	x, y: f32
	if self_x_ok {
		x = content.x + justify_align_position_offset_x(content.w, size.x, self.x)
	} else if is_horizontal {
		if in_flow_main {
			x = content.x + main_pos
		} else {
			x = content.x + justify_align_position_offset_x(content.w, size.x, child_justify.x)
		}
	} else if in_flow_cross {
		x = content.x + cross_pos
	} else {
		x = content.x + justify_align_position_offset_x(content.w, size.x, child_justify.x)
	}

	if self_y_ok {
		y = content.y + justify_align_position_offset_y(content.h, size.y, self.y)
	} else if is_horizontal {
		if in_flow_cross {
			y = content.y + cross_pos
		} else {
			y = content.y + justify_align_position_offset_y(content.h, size.y, child_justify.y)
		}
	} else if in_flow_main {
		y = content.y + main_pos
	} else {
		y = content.y + justify_align_position_offset_y(content.h, size.y, child_justify.y)
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
		layout_position_children(child, layout_inner_rect(child.rect, child.border, child.padding))
	}
}

/*
Positions children in a wrap flex container.
*/
layout_position_children_wrap :: proc(
	node: ^Layout_Node,
	content: Rect,
	info: Layout_Direction_Info,
) {
	gap := layout_config_gap(node.config)
	justify := layout_config_justify(node.config)
	is_horizontal := info.is_horizontal

	main_available := is_horizontal ? content.w : content.h
	cross_available := is_horizontal ? content.h : content.w
	main_limit := main_available

	child_sizes: [dynamic]Vec2
	defer delete(child_sizes)
	resize(&child_sizes, len(node.child_indices))

	for child_index, i in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		child_justify := layout_merge_justify(justify, child.config.self)
		main := layout_child_main_size(child, is_horizontal, 0, main_available)
		cross := layout_child_cross_size(child, is_horizontal, 0, child_justify)
		child_sizes[i] = is_horizontal ? Vec2{main, cross} : Vec2{cross, main}
		layout_apply_definite_size(child, content, &child_sizes[i])
	}

	lines := layout_wrap_build_lines(child_sizes[:], is_horizontal, gap, main_limit)
	defer delete(lines)

	line_cross_sizes: [dynamic]f32
	defer delete(line_cross_sizes)
	resize(&line_cross_sizes, len(lines))

	for line, line_index in lines {
		line_main_available := main_limit > 0 ? main_limit : line.main_sum

		flex_total: f32
		fixed_total: f32
		for i in 0 ..< line.count {
			child := &state.ui.layout.nodes[node.child_indices[line.start + i]]
			child_main := is_horizontal ? child.config.width : child.config.height
			if child.config.flex > 0 && !length_is_definite(child_main) {
				flex_total += child.config.flex
			} else {
				fixed_total += layout_wrap_child_main(child_sizes[line.start + i], is_horizontal)
			}
		}
		if line.count > 1 do fixed_total += gap * f32(line.count - 1)

		remaining := max(0, line_main_available - fixed_total)
		flex_unit := flex_total > 0 ? remaining / flex_total : 0

		line_cross_natural: f32
		for i in 0 ..< line.count {
			child_index := node.child_indices[line.start + i]
			child := &state.ui.layout.nodes[child_index]
			child_justify := layout_merge_justify(justify, child.config.self)
			main := layout_child_main_size(child, is_horizontal, flex_unit, line_main_available)
			cross := layout_child_cross_size(child, is_horizontal, 0, child_justify)
			size := is_horizontal ? Vec2{main, cross} : Vec2{cross, main}
			layout_apply_definite_size(child, content, &size)
			line_cross_natural = max(
				line_cross_natural,
				layout_wrap_child_cross(size, is_horizontal),
			)
		}

		for i in 0 ..< line.count {
			size_index := line.start + i
			child_index := node.child_indices[size_index]
			child := &state.ui.layout.nodes[child_index]
			child_justify := layout_merge_justify(justify, child.config.self)
			main := layout_child_main_size(child, is_horizontal, flex_unit, line_main_available)
			cross := layout_child_cross_size(
				child,
				is_horizontal,
				line_cross_natural,
				child_justify,
			)
			child_sizes[size_index] = is_horizontal ? Vec2{main, cross} : Vec2{cross, main}
			layout_apply_definite_size(child, content, &child_sizes[size_index])
		}

		line_indices: [dynamic]int
		defer delete(line_indices)
		line_children: [dynamic]^Layout_Node
		defer delete(line_children)
		for i in 0 ..< line.count {
			size_index := line.start + i
			append(&line_indices, size_index)
			append(&line_children, &state.ui.layout.nodes[node.child_indices[size_index]])
		}
		layout_apply_content_align_sizes_indices(
			justify,
			line_children[:],
			child_sizes[:],
			line_indices[:],
		)

		line_cross := line_cross_natural
		for idx in line_indices {
			line_cross = max(line_cross, layout_wrap_child_cross(child_sizes[idx], is_horizontal))
		}
		line_cross_sizes[line_index] = line_cross
	}

	total_cross: f32
	for line_cross, i in line_cross_sizes {
		total_cross += line_cross
		if i + 1 < len(line_cross_sizes) do total_cross += gap
	}

	cross_align, cross_align_ok := layout_cross_justify_align(justify, is_horizontal)
	cross_start: f32
	if cross_align_ok {
		cross_start = justify_align_position_offset(cross_available, total_cross, cross_align)
	}

	main_align, main_align_ok := layout_main_justify_align(justify, is_horizontal)
	main_space := main_align_ok && justify_align_is_space(main_align)

	line_cross_cursor := cross_start
	for line, line_index in lines {
		line_main_available := main_limit > 0 ? main_limit : line.main_sum
		line_cross := line_cross_sizes[line_index]

		in_flow: [dynamic]int
		defer delete(in_flow)
		for i in 0 ..< line.count {
			child := &state.ui.layout.nodes[node.child_indices[line.start + i]]
			if layout_child_in_main_flow(child, is_horizontal) {
				append(&in_flow, line.start + i)
			}
		}

		main_positions: [dynamic]f32
		defer delete(main_positions)
		if main_space && len(in_flow) > 0 {
			main_sizes: [dynamic]f32
			defer delete(main_sizes)
			for idx in in_flow {
				append(&main_sizes, layout_wrap_child_main(child_sizes[idx], is_horizontal))
			}
			main_positions = layout_space_positions(
				main_align,
				line_main_available,
				main_sizes[:],
				gap,
			)
		}

		main_start: f32
		if !main_space {
			total_main: f32
			for idx in in_flow {
				total_main += layout_wrap_child_main(child_sizes[idx], is_horizontal)
			}
			if len(in_flow) > 1 do total_main += gap * f32(len(in_flow) - 1)
			if main_align_ok {
				main_start = justify_align_position_offset(
					line_main_available,
					total_main,
					main_align,
				)
			}
		}

		main_cursor := main_start
		flow_index := 0
		for i in 0 ..< line.count {
			size_index := line.start + i
			child_index := node.child_indices[size_index]
			child := &state.ui.layout.nodes[child_index]
			size := child_sizes[size_index]
			main := layout_wrap_child_main(size, is_horizontal)
			in_flow_child := layout_child_in_main_flow(child, is_horizontal)

			main_pos: f32
			if in_flow_child && main_space {
				main_pos = main_positions[flow_index]
			} else if in_flow_child {
				main_pos = main_cursor
			}
			if info.is_main_reverse && in_flow_child {
				main_pos = layout_mirror_in_available(main_pos, main, line_main_available)
			}

			cross_pos := line_cross_cursor
			if info.is_cross_reverse {
				cross_pos = layout_mirror_in_available(
					line_cross_cursor,
					line_cross,
					cross_available,
				)
			}
			child_justify := layout_merge_justify(justify, child.config.self)
			self := child.config.self
			_, self_x_ok := resolve_justify_x(self.x)
			_, self_y_ok := resolve_justify_y(self.y)
			in_flow_cross := is_horizontal ? !self_y_ok : !self_x_ok

			if is_horizontal {
				if in_flow_cross {
					cross_pos += justify_align_position_offset_y(
						line_cross,
						size.y,
						child_justify.y,
					)
				}
			} else if in_flow_cross {
				cross_pos += justify_align_position_offset_x(line_cross, size.x, child_justify.x)
			}

			layout_position_child_rect(
				child,
				content,
				size,
				main_pos,
				cross_pos,
				is_horizontal,
				justify,
				in_flow_child,
				in_flow_cross,
			)

			if in_flow_child {
				if !main_space {
					main_cursor += main
					if i + 1 < line.count {
						next_child := &state.ui.layout.nodes[node.child_indices[line.start + i + 1]]
						if layout_child_in_main_flow(next_child, is_horizontal) {
							main_cursor += gap
						}
					}
				}
				flow_index += 1
			}
		}

		line_cross_cursor += line_cross
		if line_index + 1 < len(lines) do line_cross_cursor += gap
	}
}

/*
Expands a wrap parent's cross size to fit wrapped children.
*/
layout_wrap_apply_auto_cross_size :: proc(node: ^Layout_Node, is_horizontal: bool) {
	cross_len := is_horizontal ? node.config.height : node.config.width
	if length_is_definite(cross_len) do return

	far_edge := node.rect.y if is_horizontal else node.rect.x
	for child_index in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		if is_horizontal {
			far_edge = max(far_edge, child.rect.y + child.rect.h)
		} else {
			far_edge = max(far_edge, child.rect.x + child.rect.w)
		}
	}

	if is_horizontal {
		inset_b := node.padding.b + node.border.b
		node.rect.h = max(node.rect.h, far_edge - node.rect.y + inset_b)
	} else {
		inset_r := node.padding.r + node.border.r
		node.rect.w = max(node.rect.w, far_edge - node.rect.x + inset_r)
	}
}

/*
Positions children in a non-wrap flex container.
*/
layout_position_children :: proc(node: ^Layout_Node, content: Rect) {
	if len(node.child_indices) == 0 do return

	if node.kind == .TABLE {
		layout_table_prepare(layout_node_index(node))
	}

	direction := layout_config_direction(node.config)
	info := layout_direction_info(direction)
	if info.is_wrap {
		layout_position_children_wrap(node, content, info)
		return
	}

	gap := layout_config_gap(node.config)
	justify := layout_config_justify(node.config)
	is_horizontal := info.is_horizontal

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

	table_index := -1
	row_track_index := -1
	tracks: ^Layout_Table_Tracks = nil
	if node.kind == .TABLE_ROW {
		node_index := layout_node_index(node)
		table_index = layout_find_table_ancestor(node_index)
		if table_index >= 0 {
			if track_data, ok := &state.ui.layout.table_tracks[table_index]; ok {
				tracks = track_data
				row_track_index, _ = layout_table_row_track_index(tracks, node_index)
			}
		}
	}

	for child_index, i in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		if tracks != nil && row_track_index >= 0 && layout_node_is_table_cell(child.kind) {
			child_sizes[i] = layout_table_apply_cell_size(
				node,
				tracks,
				row_track_index,
				i,
				child,
				content,
			)
			continue
		}

		child_justify := layout_merge_justify(justify, child.config.self)
		main := layout_child_main_size(child, is_horizontal, flex_unit, main_available)
		cross := layout_child_cross_size(child, is_horizontal, cross_available, child_justify)
		child_sizes[i] = is_horizontal ? Vec2{main, cross} : Vec2{cross, main}
		layout_apply_definite_size(child, content, &child_sizes[i])
	}

	child_nodes: [dynamic]^Layout_Node
	defer delete(child_nodes)
	resize(&child_nodes, len(node.child_indices))
	for child_index, i in node.child_indices {
		child_nodes[i] = &state.ui.layout.nodes[child_index]
	}
	layout_apply_content_align_sizes(justify, child_nodes[:], child_sizes[:])

	in_flow: [dynamic]int
	defer delete(in_flow)
	for child_index, i in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		if layout_child_in_main_flow(child, is_horizontal) {
			append(&in_flow, i)
		}
	}

	main_align, main_align_ok := layout_main_justify_align(justify, is_horizontal)
	main_space := main_align_ok && justify_align_is_space(main_align)

	cross_align, cross_align_ok := layout_cross_justify_align(justify, is_horizontal)
	cross_space := cross_align_ok && justify_align_is_space(cross_align)

	main_positions: [dynamic]f32
	defer delete(main_positions)
	if main_space && len(in_flow) > 0 {
		main_sizes: [dynamic]f32
		defer delete(main_sizes)
		for idx in in_flow {
			size := child_sizes[idx]
			append(&main_sizes, is_horizontal ? size.x : size.y)
		}
		main_positions = layout_space_positions(main_align, main_available, main_sizes[:], gap)
	}

	cross_positions: [dynamic]f32
	defer delete(cross_positions)
	if cross_space && len(in_flow) > 0 {
		cross_sizes: [dynamic]f32
		defer delete(cross_sizes)
		for idx in in_flow {
			size := child_sizes[idx]
			append(&cross_sizes, is_horizontal ? size.y : size.x)
		}
		cross_positions = layout_space_positions(cross_align, cross_available, cross_sizes[:], 0)
	}

	main_start: f32
	if !main_space {
		total_main: f32
		if len(in_flow) > 0 {
			for idx in in_flow {
				size := child_sizes[idx]
				total_main += is_horizontal ? size.x : size.y
			}
			if len(in_flow) > 1 {
				total_main += gap * f32(len(in_flow) - 1)
			}
		}

		if main_align_ok {
			main_start = justify_align_position_offset(main_available, total_main, main_align)
		}
	}

	main_cursor := main_start
	flow_index := 0
	for child_index, i in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		child_justify := layout_merge_justify(justify, child.config.self)
		size := child_sizes[i]

		main := is_horizontal ? size.x : size.y
		in_flow_child := layout_child_in_main_flow(child, is_horizontal)

		main_pos: f32
		if in_flow_child && main_space {
			main_pos = main_positions[flow_index]
		} else if in_flow_child {
			main_pos = main_cursor
		}
		if info.is_main_reverse && in_flow_child {
			main_pos = layout_mirror_in_available(main_pos, main, main_available)
		}

		x, y: f32
		self := child.config.self
		_, self_x_ok := resolve_justify_x(self.x)
		_, self_y_ok := resolve_justify_y(self.y)

		if self_x_ok {
			x = content.x + justify_align_position_offset_x(content.w, size.x, self.x)
		} else if is_horizontal {
			if in_flow_child {
				x = content.x + main_pos
			} else {
				x = content.x + justify_align_position_offset_x(content.w, size.x, child_justify.x)
			}
		} else if cross_space && in_flow_child {
			x = content.x + cross_positions[flow_index]
		} else {
			x = content.x + justify_align_position_offset_x(content.w, size.x, child_justify.x)
		}

		if self_y_ok {
			y = content.y + justify_align_position_offset_y(content.h, size.y, self.y)
		} else if is_horizontal {
			if cross_space && in_flow_child {
				y = content.y + cross_positions[flow_index]
			} else {
				y = content.y + justify_align_position_offset_y(content.h, size.y, child_justify.y)
			}
		} else if in_flow_child {
			y = content.y + main_pos
		} else {
			y = content.y + justify_align_position_offset_y(content.h, size.y, child_justify.y)
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

		if in_flow_child {
			if !main_space {
				main_cursor += main
				next_in_flow := false
				for j in i + 1 ..< len(node.child_indices) {
					next_child := &state.ui.layout.nodes[node.child_indices[j]]
					if layout_child_in_main_flow(next_child, is_horizontal) {
						next_in_flow = true
						break
					}
				}
				if next_in_flow do main_cursor += gap
			}
			flow_index += 1
		}
	}
}

/*
Assigns a node's rect and recursively positions its children.
*/
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
		if layout_direction_is_wrap(node.config.direction) {
			layout_wrap_apply_auto_cross_size(
				node,
				layout_direction_info(node.config.direction).is_horizontal,
			)
		}
	}
}

/*
Solves layout for a root node within the given bounds.
*/
layout_solve :: proc(root: ^Layout_Node, bounds: Rect) {
	layout_solve_node(root, bounds)
}

/*
Returns layout bounds for screen or artboard draw space.
*/
layout_space_bounds :: proc(space: Draw_Space) -> Rect {
	logical_w := f32(state.dpi.logical_w)
	logical_h := f32(state.dpi.logical_h)

	if space == .ARTBOARD {
		zoom := view_effective_zoom()
		if zoom <= 0 do zoom = 1
		return {0, 0, logical_w / zoom, logical_h / zoom}
	}

	return {0, 0, logical_w, logical_h}
}

/*
Pushes layout bounds and records the node index for a new space.
*/
layout_begin_space :: proc(space: Draw_Space) {
	append(&state.ui.layout.bounds_stack, layout_space_bounds(space))
	append(&state.ui.layout.space_markers, len(state.ui.layout.nodes))
}

/*
Solves all root nodes created since the matching layout_begin_space.
*/
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
