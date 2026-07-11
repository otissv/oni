package oni

table_gaps_are_collapsed :: proc(gap_x, gap_y: u16) -> bool {
	return gap_x == 0 && gap_y == 0
}

table_border_source_rank :: proc(source: Table_Border_Source) -> int {
	switch source {
	case .TABLE:
		return 0
	case .ROW_GROUP:
		return 1
	case .ROW:
		return 2
	case .CELL:
		return 3
	}
	return 0
}

table_border_compare :: proc(a, b: Table_Border_Side) -> int {
	if a.width != b.width {
		if a.width > b.width do return 1
		return -1
	}

	rank_a := table_border_source_rank(a.source)
	rank_b := table_border_source_rank(b.source)
	if rank_a != rank_b {
		if rank_a > rank_b do return 1
		return -1
	}

	if a.order != b.order {
		if a.order > b.order do return 1
		return -1
	}

	return 0
}

table_border_pick_winner :: proc(candidates: []Table_Border_Side) -> Table_Border_Side {
	if len(candidates) == 0 do return {}
	winner := candidates[0]
	for candidate in candidates[1:] {
		if table_border_compare(candidate, winner) > 0 {
			winner = candidate
		}
	}
	return winner
}

table_border_side_width :: proc(border: Bd_px, side: u8) -> f32 {
	switch side {
	case 't':
		return border.t
	case 'b':
		return border.b
	case 'l':
		return border.l
	case 'r':
		return border.r
	}
	return 0
}

table_border_side_from_node :: proc(
	node: ^Layout_Node,
	side: u8,
	source: Table_Border_Source,
	order: int,
	color: RGBA,
) -> Table_Border_Side {
	border: Bd_px
	if resolved, ok := resolve_border_value(node.config.border); ok {
		border = resolved
	}
	width := table_border_side_width(border, side)
	if width <= 0 do return {}
	return Table_Border_Side{width = width, color = color, source = source, order = order}
}

table_layout_cell_ancestors :: proc(
	layout: ^Layout_State,
	cell_index: int,
) -> (
	table_index: int,
	group_index: int,
	row_index: int,
) {
	table_index = -1
	group_index = -1
	row_index = -1

	parent := layout.nodes[cell_index].parent
	for parent >= 0 {
		node := &layout.nodes[parent]
		#partial switch node.kind {
		case .TABLE_ROW:
			row_index = parent
		case .TABLE_HEAD, .TABLE_BODY, .TABLE_FOOT:
			group_index = parent
		case .TABLE:
			table_index = parent
			return
		}
		parent = node.parent
	}

	return
}

table_layout_append_side_candidates :: proc(
	layout: ^Layout_State,
	node_index: int,
	side: u8,
	source: Table_Border_Source,
	order: int,
	candidates: ^[dynamic]Table_Border_Side,
) {
	if node_index < 0 do return
	node := &layout.nodes[node_index]
	segment := table_border_side_from_node(node, side, source, order, {})
	if segment.width > 0 do append(candidates, segment)
}

table_layout_collect_edge_candidates :: proc(
	layout: ^Layout_State,
	cell_index: int,
	side: u8,
	neighbor_index: int,
	neighbor_side: u8,
	pos: Table_Grid_Pos,
	col_count: int,
	candidates: ^[dynamic]Table_Border_Side,
) {
	table_index, group_index, row_index := table_layout_cell_ancestors(layout, cell_index)
	_ = pos
	_ = col_count

	table_layout_append_side_candidates(
		layout,
		cell_index,
		side,
		.CELL,
		cell_index,
		candidates,
	)
	// Row and row-group borders compete on every cell edge they touch, so an
	// inherited row/group border still forms internal column/row grid lines.
	table_layout_append_side_candidates(layout, row_index, side, .ROW, row_index, candidates)
	table_layout_append_side_candidates(
		layout,
		group_index,
		side,
		.ROW_GROUP,
		group_index,
		candidates,
	)

	// Table borders only compete on the outer perimeter (no adjacent cell).
	if neighbor_index < 0 {
		table_layout_append_side_candidates(
			layout,
			table_index,
			side,
			.TABLE,
			table_index,
			candidates,
		)
	}

	if neighbor_index >= 0 {
		table_layout_append_side_candidates(
			layout,
			neighbor_index,
			neighbor_side,
			.CELL,
			neighbor_index,
			candidates,
		)
	}
}

table_border_strip_rect :: proc(rect: Rect, side: u8, width: f32) -> Rect {
	if width <= 0 do return {}
	switch side {
	case 't':
		return {rect.x, rect.y, rect.w, width}
	case 'b':
		return {rect.x, rect.y + rect.h - width, rect.w, width}
	case 'l':
		return {rect.x, rect.y, width, rect.h}
	case 'r':
		return {rect.x + rect.w - width, rect.y, width, rect.h}
	}
	return {}
}

table_layout_resolve_collapsed_borders :: proc(
	layout: ^Layout_State,
	tracks: ^Layout_Table_Tracks,
	node_index: int,
) -> Layout_Collapsed_Borders {
	cell := &layout.nodes[node_index]
	if !layout_node_is_table_cell(cell.kind) do return {}
	if !tracks.collapsed do return {}

	pos, pos_ok := tracks.cell_positions[node_index]
	if !pos_ok do return {}

	candidates: [dynamic]Table_Border_Side
	defer delete(candidates)

	result: Layout_Collapsed_Borders
	result.active = true

	col_count := 0
	if len(tracks.rows) > 0 {
		row_index := tracks.rows[pos.row]
		row := &layout.nodes[row_index]
		for child_index in row.child_indices {
			child := &layout.nodes[child_index]
			if layout_node_is_table_cell(child.kind) do col_count += 1
		}
	}
	row_count := len(tracks.rows)

	neighbor_index, neighbor_side := table_layout_find_cell_neighbor(
		layout,
		tracks,
		node_index,
		pos,
		't',
	)
	clear(&candidates)
	table_layout_collect_edge_candidates(
		layout,
		node_index,
		't',
		neighbor_index,
		neighbor_side,
		pos,
		col_count,
		&candidates,
	)
	result.borders.t = table_border_pick_winner(candidates[:])
	result.strips[0] = table_border_strip_rect(cell.rect, 't', result.borders.t.width)

	neighbor_index, neighbor_side = table_layout_find_cell_neighbor(
		layout,
		tracks,
		node_index,
		pos,
		'l',
	)
	clear(&candidates)
	table_layout_collect_edge_candidates(
		layout,
		node_index,
		'l',
		neighbor_index,
		neighbor_side,
		pos,
		col_count,
		&candidates,
	)
	result.borders.l = table_border_pick_winner(candidates[:])
	result.strips[2] = table_border_strip_rect(cell.rect, 'l', result.borders.l.width)

	if pos.row + 1 == row_count {
		neighbor_index, neighbor_side = table_layout_find_cell_neighbor(
			layout,
			tracks,
			node_index,
			pos,
			'b',
		)
		clear(&candidates)
		table_layout_collect_edge_candidates(
			layout,
			node_index,
			'b',
			neighbor_index,
			neighbor_side,
			pos,
			col_count,
			&candidates,
		)
		result.borders.b = table_border_pick_winner(candidates[:])
		result.strips[1] = table_border_strip_rect(cell.rect, 'b', result.borders.b.width)
	}

	if pos.col + 1 == col_count {
		neighbor_index, neighbor_side = table_layout_find_cell_neighbor(
			layout,
			tracks,
			node_index,
			pos,
			'r',
		)
		clear(&candidates)
		table_layout_collect_edge_candidates(
			layout,
			node_index,
			'r',
			neighbor_index,
			neighbor_side,
			pos,
			col_count,
			&candidates,
		)
		result.borders.r = table_border_pick_winner(candidates[:])
		result.strips[3] = table_border_strip_rect(cell.rect, 'r', result.borders.r.width)
	}

	return result
}

table_layout_borders_collapsed_for_widget :: proc(
	layout_id: UI_Id,
	kind: Widget_Kind,
) -> bool {
	if kind == .TABLE_CAPTION do return false

	node_index, ok := state.ui.layout.id_to_node[layout_id]
	if !ok do return false

	table_index := layout_find_table_ancestor_in(&state.ui.layout, node_index)
	if table_index < 0 do return false

	table := &state.ui.layout.nodes[table_index]
	return table_gaps_are_collapsed(table.config.gap_x, table.config.gap_y)
}

table_layout_find_cell_neighbor :: proc(
	layout: ^Layout_State,
	tracks: ^Layout_Table_Tracks,
	cell_index: int,
	pos: Table_Grid_Pos,
	side: u8,
) -> (
	neighbor_index: int,
	neighbor_side: u8,
) {
	neighbor_index = -1

	switch side {
	case 't':
		if pos.row <= 0 do return
		neighbor_side = 'b'
		row_index := tracks.rows[pos.row - 1]
		row := &layout.nodes[row_index]
		for child_index in row.child_indices {
			child := &layout.nodes[child_index]
			if !layout_node_is_table_cell(child.kind) do continue
			if child_pos, ok := tracks.cell_positions[child_index];
			   ok && child_pos.col == pos.col {
				neighbor_index = child_index
				return
			}
		}
	case 'b':
		if pos.row + 1 >= len(tracks.rows) do return
		neighbor_side = 't'
		row_index := tracks.rows[pos.row + 1]
		row := &layout.nodes[row_index]
		for child_index in row.child_indices {
			child := &layout.nodes[child_index]
			if !layout_node_is_table_cell(child.kind) do continue
			if child_pos, ok := tracks.cell_positions[child_index];
			   ok && child_pos.col == pos.col {
				neighbor_index = child_index
				return
			}
		}
	case 'l':
		if pos.col <= 0 do return
		neighbor_side = 'r'
		row_index := tracks.rows[pos.row]
		row := &layout.nodes[row_index]
		col := 0
		for child_index in row.child_indices {
			child := &layout.nodes[child_index]
			if !layout_node_is_table_cell(child.kind) do continue
			if col == pos.col - 1 {
				neighbor_index = child_index
				return
			}
			col += 1
		}
	case 'r':
		neighbor_side = 'l'
		row_index := tracks.rows[pos.row]
		row := &layout.nodes[row_index]
		col := 0
		for child_index in row.child_indices {
			child := &layout.nodes[child_index]
			if !layout_node_is_table_cell(child.kind) do continue
			if col == pos.col + 1 {
				neighbor_index = child_index
				return
			}
			col += 1
		}
	}

	return
}

table_collapsed_border_color :: proc(
	segment: Table_Border_Side,
	state_ptr: ^$S,
	event: Widget_Event(S),
) -> (
	RGBA,
	bool,
) {
	if segment.width <= 0 do return {}, false
	if segment.order < 0 || segment.order >= len(state.ui.layout.nodes) do return {}, false
	node := &state.ui.layout.nodes[segment.order]
	if color, ok := to_rgba(node.config.border_color, state_ptr, event); ok && color.a > 0 {
		return color, true
	}
	// Keep grid lines visible when the winning node has no usable border_color.
	return css_color_to_rgba(.BLACK), true
}

table_draw_border_strip :: proc(strip: Rect, color: RGBA) {
	if strip.w <= 0 || strip.h <= 0 || color.a <= 0 do return
	draw_rect(strip, color)
}

TABLE_CORNER_EPS :: f32(0.51)

table_f32_max :: proc(a, b: f32) -> f32 {
	return a > b ? a : b
}

table_corners_touch :: proc(ax, ay, bx, by: f32) -> bool {
	dx := ax - bx
	if dx < 0 do dx = -dx
	dy := ay - by
	if dy < 0 do dy = -dy
	return dx <= TABLE_CORNER_EPS && dy <= TABLE_CORNER_EPS
}

table_merge_radius_corners :: proc(a, b: Radius_px) -> Radius_px {
	return {
		tl = table_f32_max(a.tl, b.tl),
		tr = table_f32_max(a.tr, b.tr),
		bl = table_f32_max(a.bl, b.bl),
		br = table_f32_max(a.br, b.br),
	}
}

/*
Returns table outer-corner radii for a descendant whose rect shares those corners.

Matches CSS padding-edge radii: outer radius minus border/padding inset. Used so
opaque cell/row fills do not square off a rounded table.
*/
table_descendant_outer_radius :: proc(layout_id: UI_Id, child_rect: Rect) -> Radius_px {
	node_index, ok := state.ui.layout.id_to_node[layout_id]
	if !ok do return {}

	table_index := layout_find_table_ancestor_in(&state.ui.layout, node_index)
	if table_index < 0 || table_index == node_index do return {}

	table := &state.ui.layout.nodes[table_index]
	outer, outer_ok := resolve_radius_value(table.config.radius)
	if !outer_ok do return {}
	if outer.tl <= 0 && outer.tr <= 0 && outer.bl <= 0 && outer.br <= 0 do return {}

	content := layout_inner_rect(table.rect, table.border, table.padding)
	inset_t := table.border.t + table.padding.t
	inset_b := table.border.b + table.padding.b
	inset_l := table.border.l + table.padding.l
	inset_r := table.border.r + table.padding.r

	inner := Radius_px {
		tl = table_f32_max(0, outer.tl - table_f32_max(inset_t, inset_l)),
		tr = table_f32_max(0, outer.tr - table_f32_max(inset_t, inset_r)),
		bl = table_f32_max(0, outer.bl - table_f32_max(inset_b, inset_l)),
		br = table_f32_max(0, outer.br - table_f32_max(inset_b, inset_r)),
	}

	result: Radius_px
	if table_corners_touch(child_rect.x, child_rect.y, content.x, content.y) {
		result.tl = inner.tl
	}
	if table_corners_touch(
		child_rect.x + child_rect.w,
		child_rect.y,
		content.x + content.w,
		content.y,
	) {
		result.tr = inner.tr
	}
	if table_corners_touch(
		child_rect.x,
		child_rect.y + child_rect.h,
		content.x,
		content.y + content.h,
	) {
		result.bl = inner.bl
	}
	if table_corners_touch(
		child_rect.x + child_rect.w,
		child_rect.y + child_rect.h,
		content.x + content.w,
		content.y + content.h,
	) {
		result.br = inner.br
	}
	return result
}

table_side_is_straight :: proc(radius: Radius_px, side: u8) -> bool {
	switch side {
	case 't':
		return radius.tl <= 0 && radius.tr <= 0
	case 'b':
		return radius.bl <= 0 && radius.br <= 0
	case 'l':
		return radius.tl <= 0 && radius.bl <= 0
	case 'r':
		return radius.tr <= 0 && radius.br <= 0
	}
	return true
}

table_draw_collapsed_cell :: proc(
	rect: Rect,
	background: RGBA,
	collapsed: Layout_Collapsed_Borders,
	radius: Radius_px,
	state_ptr: ^$S,
	event: Widget_Event(S),
) {
	if !collapsed.active do return

	sides := [4]Table_Border_Side {
		collapsed.borders.t,
		collapsed.borders.b,
		collapsed.borders.l,
		collapsed.borders.r,
	}
	side_chars := [4]u8{'t', 'b', 'l', 'r'}

	has_radius := radius.tl > 0 || radius.tr > 0 || radius.bl > 0 || radius.br > 0
	if has_radius {
		// Rounded outer corners need the rounded-rect border path.
		border := Bd_px {
			t = collapsed.borders.t.width,
			b = collapsed.borders.b.width,
			l = collapsed.borders.l.width,
			r = collapsed.borders.r.width,
		}
		border_color: RGBA
		for side in sides {
			if color, color_ok := table_collapsed_border_color(side, state_ptr, event); color_ok {
				border_color = color
				break
			}
		}
		draw_rect(rect, background, radius, border, border_color)

		// Straight internal edges (e.g. vertical line between headings) are also
		// painted as strips so they stay visible when only an outer corner is rounded.
		for side, i in sides {
			if !table_side_is_straight(radius, side_chars[i]) do continue
			color, color_ok := table_collapsed_border_color(side, state_ptr, event)
			if !color_ok do continue
			strip := collapsed.strips[i]
			if strip.w <= 0 || strip.h <= 0 {
				strip = table_border_strip_rect(rect, side_chars[i], side.width)
			}
			table_draw_border_strip(strip, color)
		}
		return
	}

	if background.a > 0 {
		draw_rect(rect, background)
	}

	for side, i in sides {
		color, color_ok := table_collapsed_border_color(side, state_ptr, event)
		if !color_ok do continue
		table_draw_border_strip(collapsed.strips[i], color)
	}
}
