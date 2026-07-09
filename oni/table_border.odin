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

table_layout_node_border_color :: proc(
	node: ^Layout_Node,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	RGBA,
	bool,
) {
	return to_rgba(node.config.border_color, state, event)
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
	state_ptr: ^$S,
	event: Widget_Event(S),
	candidates: ^[dynamic]Table_Border_Side,
) {
	if node_index < 0 do return
	node := &layout.nodes[node_index]
	color, color_ok := table_layout_node_border_color(node, state_ptr, event)
	if !color_ok do return
	segment := table_border_side_from_node(node, side, source, order, color)
	if segment.width > 0 do append(candidates, segment)
}

table_layout_collect_edge_candidates :: proc(
	layout: ^Layout_State,
	cell_index: int,
	side: u8,
	neighbor_index: int,
	neighbor_side: u8,
	state_ptr: ^$S,
	event: Widget_Event(S),
	candidates: ^[dynamic]Table_Border_Side,
) {
	table_index, group_index, row_index := table_layout_cell_ancestors(layout, cell_index)

	table_layout_append_side_candidates(
		layout,
		cell_index,
		side,
		.CELL,
		cell_index,
		state_ptr,
		event,
		candidates,
	)
	table_layout_append_side_candidates(
		layout,
		row_index,
		side,
		.ROW,
		row_index,
		state_ptr,
		event,
		candidates,
	)
	table_layout_append_side_candidates(
		layout,
		group_index,
		side,
		.ROW_GROUP,
		group_index,
		state_ptr,
		event,
		candidates,
	)
	table_layout_append_side_candidates(
		layout,
		table_index,
		side,
		.TABLE,
		table_index,
		state_ptr,
		event,
		candidates,
	)

	if neighbor_index >= 0 {
		table_layout_append_side_candidates(
			layout,
			neighbor_index,
			neighbor_side,
			.CELL,
			neighbor_index,
			state_ptr,
			event,
			candidates,
		)
	}
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

table_resolve_collapsed_borders :: proc(
	layout_id: UI_Id,
	state_ptr: ^$S,
	event: Widget_Event(S),
) -> (
	borders: Table_Cell_Borders,
	ok: bool,
) {
	node_index, found := state.ui.layout.id_to_node[layout_id]
	if !found do return

	cell := &state.ui.layout.nodes[node_index]
	if !layout_node_is_table_cell(cell.kind) do return

	table_index := layout_find_table_ancestor_in(&state.ui.layout, node_index)
	if table_index < 0 do return

	tracks, tracks_ok := state.ui.layout.table_tracks[table_index]
	if !tracks_ok || tracks.border_collapse != .COLLAPSE do return

	pos, pos_ok := tracks.cell_positions[node_index]
	if !pos_ok do return

	candidates: [dynamic]Table_Border_Side
	defer delete(candidates)

	neighbor_index, neighbor_side := table_layout_find_cell_neighbor(
		&state.ui.layout,
		&tracks,
		node_index,
		pos,
		't',
	)
	clear(&candidates)
	table_layout_collect_edge_candidates(
		&state.ui.layout,
		node_index,
		't',
		neighbor_index,
		neighbor_side,
		state_ptr,
		event,
		&candidates,
	)
	borders.t = table_border_pick_winner(candidates[:])

	neighbor_index, neighbor_side = table_layout_find_cell_neighbor(
		&state.ui.layout,
		&tracks,
		node_index,
		pos,
		'l',
	)
	clear(&candidates)
	table_layout_collect_edge_candidates(
		&state.ui.layout,
		node_index,
		'l',
		neighbor_index,
		neighbor_side,
		state_ptr,
		event,
		&candidates,
	)
	borders.l = table_border_pick_winner(candidates[:])

	if pos.row + 1 == len(tracks.rows) {
		neighbor_index, neighbor_side = table_layout_find_cell_neighbor(
			&state.ui.layout,
			&tracks,
			node_index,
			pos,
			'b',
		)
		clear(&candidates)
		table_layout_collect_edge_candidates(
			&state.ui.layout,
			node_index,
			'b',
			neighbor_index,
			neighbor_side,
			state_ptr,
			event,
			&candidates,
		)
		borders.b = table_border_pick_winner(candidates[:])
	}

	col_count := 0
	if len(tracks.rows) > 0 {
		row_index := tracks.rows[pos.row]
		row := &state.ui.layout.nodes[row_index]
		for child_index in row.child_indices {
			child := &state.ui.layout.nodes[child_index]
			if layout_node_is_table_cell(child.kind) do col_count += 1
		}
	}

	if pos.col + 1 == col_count {
		neighbor_index, neighbor_side = table_layout_find_cell_neighbor(
			&state.ui.layout,
			&tracks,
			node_index,
			pos,
			'r',
		)
		clear(&candidates)
		table_layout_collect_edge_candidates(
			&state.ui.layout,
			node_index,
			'r',
			neighbor_index,
			neighbor_side,
			state_ptr,
			event,
			&candidates,
		)
		borders.r = table_border_pick_winner(candidates[:])
	}

	return borders, true
}

table_draw_border_side :: proc(rect: Rect, side: u8, segment: Table_Border_Side) {
	if segment.width <= 0 || segment.color.a <= 0 do return

	r: Rect
	switch side {
	case 't':
		r = {rect.x, rect.y, rect.w, segment.width}
	case 'b':
		r = {rect.x, rect.y + rect.h - segment.width, rect.w, segment.width}
	case 'l':
		r = {rect.x, rect.y, segment.width, rect.h}
	case 'r':
		r = {rect.x + rect.w - segment.width, rect.y, segment.width, rect.h}
	case:
		return
	}

	draw_rect(r, segment.color)
}

table_draw_collapsed_cell :: proc(rect: Rect, background: RGBA, borders: Table_Cell_Borders) {
	if background.a > 0 {
		draw_rect(rect, background)
	}

	table_draw_border_side(rect, 't', borders.t)
	table_draw_border_side(rect, 'l', borders.l)
	table_draw_border_side(rect, 'b', borders.b)
	table_draw_border_side(rect, 'r', borders.r)
}
