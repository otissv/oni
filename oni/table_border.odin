package oni

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

table_border_side_width :: proc(border: Bd, side: u8) -> f32 {
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
	border: Bd
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
	candidates: ^[dynamic]Table_Border_Side,
) {
	table_index, group_index, row_index := table_layout_cell_ancestors(layout, cell_index)

	table_layout_append_side_candidates(
		layout,
		cell_index,
		side,
		.CELL,
		cell_index,
		candidates,
	)
	table_layout_append_side_candidates(layout, row_index, side, .ROW, row_index, candidates)
	table_layout_append_side_candidates(
		layout,
		group_index,
		side,
		.ROW_GROUP,
		group_index,
		candidates,
	)
	table_layout_append_side_candidates(layout, table_index, side, .TABLE, table_index, candidates)

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
	if tracks.border_collapse != .COLLAPSE do return {}

	pos, pos_ok := tracks.cell_positions[node_index]
	if !pos_ok do return {}

	candidates: [dynamic]Table_Border_Side
	defer delete(candidates)

	result: Layout_Collapsed_Borders
	result.active = true

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
		&candidates,
	)
	result.borders.l = table_border_pick_winner(candidates[:])
	result.strips[2] = table_border_strip_rect(cell.rect, 'l', result.borders.l.width)

	if pos.row + 1 == len(tracks.rows) {
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
			&candidates,
		)
		result.borders.b = table_border_pick_winner(candidates[:])
		result.strips[1] = table_border_strip_rect(cell.rect, 'b', result.borders.b.width)
	}

	col_count := 0
	if len(tracks.rows) > 0 {
		row_index := tracks.rows[pos.row]
		row := &layout.nodes[row_index]
		for child_index in row.child_indices {
			child := &layout.nodes[child_index]
			if layout_node_is_table_cell(child.kind) do col_count += 1
		}
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
			&candidates,
		)
		result.borders.r = table_border_pick_winner(candidates[:])
		result.strips[3] = table_border_strip_rect(cell.rect, 'r', result.borders.r.width)
	}

	return result
}

table_layout_border_collapse_for :: proc(layout_id: UI_Id) -> Border_Collapse {
	if mode, ok := state.ui.layout.table_border_collapse[layout_id]; ok {
		return mode
	}
	return .SEPERATE
}

table_layout_border_collapse_for_widget :: proc(
	layout_id: UI_Id,
	kind: Widget_Kind,
) -> Border_Collapse {
	if kind == .TABLE_CAPTION do return .SEPERATE

	node_index, ok := state.ui.layout.id_to_node[layout_id]
	if !ok do return .SEPERATE

	table_index := layout_find_table_ancestor_in(&state.ui.layout, node_index)
	if table_index < 0 do return .SEPERATE

	table := &state.ui.layout.nodes[table_index]
	return table_layout_border_collapse_for(table.ui_id)
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
	return to_rgba(node.config.border_color, state_ptr, event)
}

table_draw_border_strip :: proc(strip: Rect, color: RGBA) {
	if strip.w <= 0 || strip.h <= 0 || color.a <= 0 do return
	draw_rect(strip, color)
}

table_draw_collapsed_cell :: proc(
	rect: Rect,
	background: RGBA,
	collapsed: Layout_Collapsed_Borders,
	state_ptr: ^$S,
	event: Widget_Event(S),
) {
	if !collapsed.active do return

	if background.a > 0 {
		draw_rect(rect, background)
	}

	sides := [4]Table_Border_Side {
		collapsed.borders.t,
		collapsed.borders.b,
		collapsed.borders.l,
		collapsed.borders.r,
	}
	for side, i in sides {
		color, color_ok := table_collapsed_border_color(side, state_ptr, event)
		if !color_ok do continue
		table_draw_border_strip(collapsed.strips[i], color)
	}
}
