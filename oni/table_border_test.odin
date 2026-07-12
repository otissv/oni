package oni

import "core:testing"

@(test)
table_gaps_collapsed_only_when_both_zero :: proc(t: ^testing.T) {
	testing.expect(t, table_gaps_are_collapsed(0, 0))
	testing.expect(t, !table_gaps_are_collapsed(1, 0))
	testing.expect(t, !table_gaps_are_collapsed(0, 1))
	testing.expect(t, !table_gaps_are_collapsed(2, 3))
}

@(test)
table_border_source_rank_ordering :: proc(t: ^testing.T) {
	testing.expect_value(t, table_border_source_rank(.TABLE), 0)
	testing.expect_value(t, table_border_source_rank(.ROW_GROUP), 1)
	testing.expect_value(t, table_border_source_rank(.ROW), 2)
	testing.expect_value(t, table_border_source_rank(.CELL), 3)
	testing.expect(t, table_border_source_rank(.CELL) > table_border_source_rank(.ROW))
	testing.expect(t, table_border_source_rank(.ROW) > table_border_source_rank(.ROW_GROUP))
}

@(test)
table_border_compare_width_source_and_order :: proc(t: ^testing.T) {
	thick := Table_Border_Side{width = 3, source = .TABLE, order = 0}
	thin := Table_Border_Side{width = 1, source = .CELL, order = 9}
	testing.expect(t, table_border_compare(thick, thin) > 0)
	testing.expect(t, table_border_compare(thin, thick) < 0)

	cell := Table_Border_Side{width = 1, source = .CELL, order = 0}
	row := Table_Border_Side{width = 1, source = .ROW, order = 1}
	testing.expect(t, table_border_compare(cell, row) > 0)

	early := Table_Border_Side{width = 1, source = .CELL, order = 1}
	late := Table_Border_Side{width = 1, source = .CELL, order = 5}
	testing.expect(t, table_border_compare(late, early) > 0)
	testing.expect_value(t, table_border_compare(early, early), 0)
}

@(test)
table_border_pick_winner_handles_empty_and_ties :: proc(t: ^testing.T) {
	empty := table_border_pick_winner({})
	expect_close(t, empty.width, 0)

	only := []Table_Border_Side{{width = 2, source = .ROW, order = 1}}
	got := table_border_pick_winner(only)
	expect_close(t, got.width, 2)

	candidates := []Table_Border_Side {
		{width = 1, source = .TABLE, order = 0},
		{width = 1, source = .CELL, order = 2},
		{width = 2, source = .ROW, order = 1},
	}
	winner := table_border_pick_winner(candidates)
	expect_close(t, winner.width, 2)
	testing.expect(t, winner.source == .ROW)
}

@(test)
table_border_side_width_and_from_node :: proc(t: ^testing.T) {
	border := Bd_px{t = 1, b = 2, l = 3, r = 4}
	expect_close(t, table_border_side_width(border, 't'), 1)
	expect_close(t, table_border_side_width(border, 'b'), 2)
	expect_close(t, table_border_side_width(border, 'l'), 3)
	expect_close(t, table_border_side_width(border, 'r'), 4)
	expect_close(t, table_border_side_width(border, 'x'), 0)

	node := Layout_Node {
		config = {border = Bd{t = 5, b = 0, l = 0, r = 0}},
	}
	side := table_border_side_from_node(&node, 't', .CELL, 7, {1, 0, 0, 1})
	expect_close(t, side.width, 5)
	testing.expect(t, side.source == .CELL)
	testing.expect_value(t, side.order, 7)

	zero := table_border_side_from_node(&node, 'l', .CELL, 0, {})
	expect_close(t, zero.width, 0)
}

@(test)
table_border_strip_rect_zero_and_invalid :: proc(t: ^testing.T) {
	rect := Rect{5, 10, 40, 20}
	empty := table_border_strip_rect(rect, 't', 0)
	expect_rect(t, empty, {})

	invalid := table_border_strip_rect(rect, 'z', 3)
	expect_rect(t, invalid, {})

	top := table_border_strip_rect(rect, 't', 2)
	expect_rect(t, top, {5, 10, 40, 2})
	bottom := table_border_strip_rect(rect, 'b', 3)
	expect_rect(t, bottom, {5, 27, 40, 3})
	left := table_border_strip_rect(rect, 'l', 1)
	expect_rect(t, left, {5, 10, 1, 20})
	right := table_border_strip_rect(rect, 'r', 4)
	expect_rect(t, right, {41, 10, 4, 20})
}

@(test)
table_layout_cell_ancestors_walks_hierarchy :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	table := layout_test_append_node(&layout, -1, .TABLE)
	head := layout_test_append_node(&layout, table, .TABLE_HEAD)
	row := layout_test_append_node(&layout, head, .TABLE_ROW)
	cell := layout_test_append_node(&layout, row, .TABLE_CELL)

	ti, gi, ri := table_layout_cell_ancestors(&layout, cell)
	testing.expect_value(t, ti, table)
	testing.expect_value(t, gi, head)
	testing.expect_value(t, ri, row)

	// Body/foot groups also count.
	body := layout_test_append_node(&layout, table, .TABLE_BODY)
	brow := layout_test_append_node(&layout, body, .TABLE_ROW)
	bcell := layout_test_append_node(&layout, brow, .TABLE_CELL)
	ti, gi, ri = table_layout_cell_ancestors(&layout, bcell)
	testing.expect_value(t, ti, table)
	testing.expect_value(t, gi, body)
	testing.expect_value(t, ri, brow)
}

@(test)
table_layout_find_cell_neighbor_all_sides :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	border := Border(Bd{t = 1, b = 1, l = 1, r = 1})
	table := layout_test_append_node(&layout, -1, .TABLE, {}, {}, {gap_x = 0, gap_y = 0, border = border})
	body := layout_test_append_node(&layout, table, .TABLE_BODY, {}, {}, {border = border})
	row0 := layout_test_append_node(&layout, body, .TABLE_ROW, {x = .TABLE_CELL, y = .TABLE_CELL}, {}, {border = border})
	row1 := layout_test_append_node(&layout, body, .TABLE_ROW, {x = .TABLE_CELL, y = .TABLE_CELL}, {}, {border = border})
	c00 := layout_test_append_node(&layout, row0, .TABLE_CELL, {}, {40, 20}, {border = border})
	c01 := layout_test_append_node(&layout, row0, .TABLE_CELL, {}, {40, 20}, {border = border})
	c10 := layout_test_append_node(&layout, row1, .TABLE_CELL, {}, {40, 20}, {border = border})
	c11 := layout_test_append_node(&layout, row1, .TABLE_CELL, {}, {40, 20}, {border = border})

	layout.nodes[c00].rect = {0, 0, 40, 20}
	layout.nodes[c01].rect = {40, 0, 40, 20}
	layout.nodes[c10].rect = {0, 20, 40, 20}
	layout.nodes[c11].rect = {40, 20, 40, 20}

	layout_table_prepare_in(&layout, table)
	layout_table_finalize_in(&layout, table)
	tracks := &layout.table_tracks[table]

	pos00 := tracks.cell_positions[c00]
	n, side := table_layout_find_cell_neighbor(&layout, tracks, c00, pos00, 'r')
	testing.expect_value(t, n, c01)
	testing.expect_value(t, side, u8('l'))

	n, side = table_layout_find_cell_neighbor(&layout, tracks, c00, pos00, 'b')
	testing.expect_value(t, n, c10)
	testing.expect_value(t, side, u8('t'))

	n, side = table_layout_find_cell_neighbor(&layout, tracks, c00, pos00, 't')
	testing.expect_value(t, n, -1)

	n, side = table_layout_find_cell_neighbor(&layout, tracks, c00, pos00, 'l')
	testing.expect_value(t, n, -1)

	pos11 := tracks.cell_positions[c11]
	n, side = table_layout_find_cell_neighbor(&layout, tracks, c11, pos11, 'l')
	testing.expect_value(t, n, c10)
	testing.expect_value(t, side, u8('r'))

	n, side = table_layout_find_cell_neighbor(&layout, tracks, c11, pos11, 't')
	testing.expect_value(t, n, c01)
	testing.expect_value(t, side, u8('b'))
}

@(test)
table_layout_resolve_collapsed_borders_outer_and_internal :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	border := Border(Bd{t = 2, b = 2, l = 2, r = 2})
	table := layout_test_append_node(
		&layout,
		-1,
		.TABLE,
		{},
		{},
		{gap_x = 0, gap_y = 0, border = border},
	)
	body := layout_test_append_node(&layout, table, .TABLE_BODY, {}, {}, {border = border})
	row0 := layout_test_append_node(
		&layout,
		body,
		.TABLE_ROW,
		{x = .TABLE_CELL, y = .TABLE_CELL},
		{},
		{border = border},
	)
	row1 := layout_test_append_node(
		&layout,
		body,
		.TABLE_ROW,
		{x = .TABLE_CELL, y = .TABLE_CELL},
		{},
		{border = border},
	)
	c00 := layout_test_append_node(&layout, row0, .TABLE_CELL, {}, {50, 25}, {border = border})
	c01 := layout_test_append_node(&layout, row0, .TABLE_CELL, {}, {50, 25}, {border = border})
	c10 := layout_test_append_node(&layout, row1, .TABLE_CELL, {}, {50, 25}, {border = border})
	c11 := layout_test_append_node(&layout, row1, .TABLE_CELL, {}, {50, 25}, {border = border})

	layout.nodes[c00].rect = {0, 0, 50, 25}
	layout.nodes[c01].rect = {50, 0, 50, 25}
	layout.nodes[c10].rect = {0, 25, 50, 25}
	layout.nodes[c11].rect = {50, 25, 50, 25}

	layout_table_prepare_in(&layout, table)
	layout_table_finalize_in(&layout, table)
	tracks := &layout.table_tracks[table]

	top_left := table_layout_resolve_collapsed_borders(&layout, tracks, c00)
	testing.expect(t, top_left.active)
	expect_close(t, top_left.borders.t.width, 2)
	expect_close(t, top_left.borders.l.width, 2)
	// Internal edges: bottom/right owned by trailing cells only.
	expect_close(t, top_left.borders.b.width, 0)
	expect_close(t, top_left.borders.r.width, 0)

	bottom_right := table_layout_resolve_collapsed_borders(&layout, tracks, c11)
	testing.expect(t, bottom_right.active)
	expect_close(t, bottom_right.borders.b.width, 2)
	expect_close(t, bottom_right.borders.r.width, 2)
	expect_close(t, bottom_right.borders.t.width, 2)
	expect_close(t, bottom_right.borders.l.width, 2)

	non_cell := table_layout_resolve_collapsed_borders(&layout, tracks, table)
	testing.expect(t, !non_cell.active)
}

@(test)
table_borders_collapsed_for_widget_respects_gaps_and_caption :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			_ = layout_test_begin()
			defer layout_test_end(&state.ui.layout)

			table := layout_test_append_node(
				&state.ui.layout,
				-1,
				.TABLE,
				{},
				{},
				{gap_x = 0, gap_y = 0},
			)
			head := layout_test_append_node(&state.ui.layout, table, .TABLE_HEAD)
			row := layout_test_append_node(&state.ui.layout, head, .TABLE_ROW)
			cell := layout_test_append_node(&state.ui.layout, row, .TABLE_CELL)
			caption := layout_test_append_node(&state.ui.layout, table, .TABLE_CAPTION)

			state.ui.layout.nodes[table].ui_id = UI_Id(1)
			state.ui.layout.nodes[cell].ui_id = UI_Id(2)
			state.ui.layout.nodes[caption].ui_id = UI_Id(3)
			state.ui.layout.id_to_node[UI_Id(2)] = cell
			state.ui.layout.id_to_node[UI_Id(3)] = caption

			testing.expect(t, table_layout_borders_collapsed_for_widget(UI_Id(2), .TABLE_CELL))
			testing.expect(t, !table_layout_borders_collapsed_for_widget(UI_Id(3), .TABLE_CAPTION))
			testing.expect(t, !table_layout_borders_collapsed_for_widget(UI_Id(99), .TABLE_CELL))

			state.ui.layout.nodes[table].config.gap_x = 4
			testing.expect(t, !table_layout_borders_collapsed_for_widget(UI_Id(2), .TABLE_CELL))
		},
	)
}

@(test)
table_corner_helpers_and_merge_radius :: proc(t: ^testing.T) {
	expect_close(t, table_f32_max(3, 5), 5)
	expect_close(t, table_f32_max(8, 2), 8)

	testing.expect(t, table_corners_touch(0, 0, 0.4, 0.4))
	testing.expect(t, !table_corners_touch(0, 0, 2, 2))

	merged := table_merge_radius_corners({1, 2, 3, 4}, {4, 1, 5, 0})
	expect_radius(t, merged, {4, 2, 5, 4})

	radius := Radius_px{tl = 4, tr = 0, bl = 0, br = 2}
	testing.expect(t, !table_side_is_straight(radius, 't'))
	testing.expect(t, table_side_is_straight(radius, 'l') == false)
	testing.expect(t, table_side_is_straight(radius, 'b') == false)
	testing.expect(t, table_side_is_straight({0, 0, 0, 0}, 't'))
	testing.expect(t, table_side_is_straight(radius, 'x'))
}

@(test)
table_collect_edge_candidates_includes_hierarchy :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	table_border := Border(Bd{t = 4, b = 4, l = 4, r = 4})
	row_border := Border(Bd{t = 1, b = 1, l = 1, r = 1})
	cell_border := Border(Bd{t = 2, b = 2, l = 2, r = 2})

	table := layout_test_append_node(
		&layout,
		-1,
		.TABLE,
		{},
		{},
		{gap_x = 0, gap_y = 0, border = table_border},
	)
	body := layout_test_append_node(&layout, table, .TABLE_BODY, {}, {}, {border = row_border})
	row := layout_test_append_node(
		&layout,
		body,
		.TABLE_ROW,
		{x = .TABLE_CELL, y = .TABLE_CELL},
		{},
		{border = row_border},
	)
	cell := layout_test_append_node(&layout, row, .TABLE_CELL, {}, {40, 20}, {border = cell_border})
	layout.nodes[cell].rect = {0, 0, 40, 20}

	candidates: [dynamic]Table_Border_Side
	defer delete(candidates)
	table_layout_collect_edge_candidates(
		&layout,
		cell,
		't',
		-1,
		0,
		{},
		1,
		&candidates,
	)
	testing.expect(t, len(candidates) >= 3)

	winner := table_border_pick_winner(candidates[:])
	expect_close(t, winner.width, 4)
	testing.expect(t, winner.source == .TABLE)
}

@(test)
table_collapsed_border_color_fallback :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			_ = layout_test_begin()
			defer layout_test_end(&state.ui.layout)

			node := layout_test_append_node(
				&state.ui.layout,
				-1,
				.TABLE_CELL,
				{},
				{},
				{border_color = RGBA{0, 0, 1, 1}},
			)
			frame, event := ui_test_frame_event()

			color, ok := table_collapsed_border_color(
				{width = 1, order = node, source = .CELL},
				&frame,
				event,
			)
			testing.expect(t, ok)
			testing.expect_value(t, color.b, u8(1))

			_, bad := table_collapsed_border_color({width = 0, order = node}, &frame, event)
			testing.expect(t, !bad)

			_, invalid := table_collapsed_border_color({width = 1, order = -1}, &frame, event)
			testing.expect(t, !invalid)

			plain := layout_test_append_node(&state.ui.layout, -1, .TABLE_CELL)
			fallback, fok := table_collapsed_border_color(
				{width = 1, order = plain, source = .CELL},
				&frame,
				event,
			)
			testing.expect(t, fok)
			testing.expect_value(t, fallback.a, u8(255))
		},
	)
}

@(test)
table_descendant_outer_radius_all_corners_and_non_table :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			_ = layout_test_begin()
			defer layout_test_end(&state.ui.layout)

			table := layout_test_append_node(&state.ui.layout, -1, .TABLE)
			head := layout_test_append_node(&state.ui.layout, table, .TABLE_HEAD)
			row := layout_test_append_node(&state.ui.layout, head, .TABLE_ROW)
			tl := layout_test_append_node(&state.ui.layout, row, .TABLE_CELL)
			br := layout_test_append_node(&state.ui.layout, row, .TABLE_CELL)

			state.ui.layout.nodes[table].rect = {0, 0, 100, 80}
			state.ui.layout.nodes[table].border = {2, 2, 2, 2}
			state.ui.layout.nodes[table].padding = {1, 1, 1, 1}
			state.ui.layout.nodes[table].config.radius = f32(12)
			state.ui.layout.nodes[table].ui_id = UI_Id(1)

			// Content origin after border+padding = (3,3); size 100-6 x 80-6
			state.ui.layout.nodes[tl].rect = {3, 3, 40, 20}
			state.ui.layout.nodes[tl].ui_id = UI_Id(2)
			state.ui.layout.id_to_node[UI_Id(2)] = tl

			state.ui.layout.nodes[br].rect = {57, 57, 40, 20}
			state.ui.layout.nodes[br].ui_id = UI_Id(3)
			state.ui.layout.id_to_node[UI_Id(3)] = br

			got_tl := table_descendant_outer_radius(UI_Id(2), state.ui.layout.nodes[tl].rect)
			expect_close(t, got_tl.tl, 9) // 12 - max(3,3)
			expect_close(t, got_tl.tr, 0)

			got_br := table_descendant_outer_radius(UI_Id(3), state.ui.layout.nodes[br].rect)
			expect_close(t, got_br.br, 9)
			expect_close(t, got_br.tl, 0)

			testing.expect(t, table_descendant_outer_radius(UI_Id(99), {}) == Radius_px{})
			testing.expect(
				t,
				table_descendant_outer_radius(UI_Id(1), state.ui.layout.nodes[table].rect) ==
				Radius_px{},
			)
		},
	)
}



@(private)
table_border_test_style :: proc(border_w: f32 = 0, gap_x: u16 = 0, gap_y: u16 = 0) -> Resolved_Widget_Style {
	cfg: Resolved_Widget_Style
	cfg.gap_x = gap_x
	cfg.gap_y = gap_y
	if border_w > 0 {
		cfg.border = Border(border_w)
	}
	return cfg
}

@(private)
table_border_test_sides :: proc(t, b, l, r: f32) -> Resolved_Widget_Style {
	cfg: Resolved_Widget_Style
	sides := Bd {
		t = t,
		b = b,
		l = l,
		r = r,
	}
	cfg.border = Border(sides)
	return cfg
}

@(test)
table_layout_append_side_candidates_skips_invalid_and_zero :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	node := layout_test_append_node(
		&layout,
		-1,
		.TABLE_CELL,
		{},
		{},
		table_border_test_sides(3, 0, 0, 0),
	)

	candidates: [dynamic]Table_Border_Side
	defer delete(candidates)

	table_layout_append_side_candidates(&layout, -1, 't', .CELL, 0, &candidates)
	testing.expect_value(t, len(candidates), 0)

	table_layout_append_side_candidates(&layout, node, 'b', .CELL, node, &candidates)
	testing.expect_value(t, len(candidates), 0)

	table_layout_append_side_candidates(&layout, node, 't', .CELL, node, &candidates)
	testing.expect_value(t, len(candidates), 1)
	expect_close(t, candidates[0].width, 3)
	testing.expect(t, candidates[0].source == .CELL)
	testing.expect_value(t, candidates[0].order, node)
}

@(test)
table_collect_edge_candidates_internal_excludes_table_includes_neighbor :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	table := layout_test_append_node(
		&layout,
		-1,
		.TABLE,
		{},
		{},
		table_border_test_style(8),
	)
	body := layout_test_append_node(&layout, table, .TABLE_BODY)
	row := layout_test_append_node(
		&layout,
		body,
		.TABLE_ROW,
		{x = .TABLE_CELL, y = .TABLE_CELL},
	)
	left := layout_test_append_node(
		&layout,
		row,
		.TABLE_CELL,
		{},
		{40, 20},
		table_border_test_style(1),
	)
	right := layout_test_append_node(
		&layout,
		row,
		.TABLE_CELL,
		{},
		{40, 20},
		table_border_test_style(3),
	)

	candidates: [dynamic]Table_Border_Side
	defer delete(candidates)
	table_layout_collect_edge_candidates(
		&layout,
		left,
		'r',
		right,
		'l',
		{row = 0, col = 0},
		2,
		&candidates,
	)

	has_table := false
	has_neighbor := false
	for c in candidates {
		if c.source == .TABLE do has_table = true
		if c.source == .CELL && c.order == right do has_neighbor = true
	}
	testing.expect(t, !has_table)
	testing.expect(t, has_neighbor)

	winner := table_border_pick_winner(candidates[:])
	expect_close(t, winner.width, 3)
	testing.expect(t, winner.source == .CELL)
	testing.expect_value(t, winner.order, right)
}

@(test)
table_border_compare_full_source_ladder_and_pick_tie :: proc(t: ^testing.T) {
	equal_w: f32 = 2
	table := Table_Border_Side{width = equal_w, source = .TABLE, order = 9}
	group := Table_Border_Side{width = equal_w, source = .ROW_GROUP, order = 8}
	row := Table_Border_Side{width = equal_w, source = .ROW, order = 7}
	cell := Table_Border_Side{width = equal_w, source = .CELL, order = 6}

	testing.expect(t, table_border_compare(group, table) > 0)
	testing.expect(t, table_border_compare(row, group) > 0)
	testing.expect(t, table_border_compare(cell, row) > 0)

	tied_a := Table_Border_Side{width = 1, source = .CELL, order = 4, color = {1, 0, 0, 1}}
	tied_b := Table_Border_Side{width = 1, source = .CELL, order = 4, color = {0, 1, 0, 1}}
	testing.expect_value(t, table_border_compare(tied_a, tied_b), 0)

	// Exact ties keep the first candidate (compare never returns > 0).
	winner := table_border_pick_winner({tied_a, tied_b})
	testing.expect_value(t, winner.color.r, u8(1))
	testing.expect_value(t, winner.color.g, u8(0))
}

@(test)
table_layout_cell_ancestors_foot_and_orphan :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	table := layout_test_append_node(&layout, -1, .TABLE)
	foot := layout_test_append_node(&layout, table, .TABLE_FOOT)
	row := layout_test_append_node(&layout, foot, .TABLE_ROW)
	cell := layout_test_append_node(&layout, row, .TABLE_CELL)

	ti, gi, ri := table_layout_cell_ancestors(&layout, cell)
	testing.expect_value(t, ti, table)
	testing.expect_value(t, gi, foot)
	testing.expect_value(t, ri, row)

	orphan := layout_test_append_node(&layout, -1, .TABLE_CELL)
	ti, gi, ri = table_layout_cell_ancestors(&layout, orphan)
	testing.expect_value(t, ti, -1)
	testing.expect_value(t, gi, -1)
	testing.expect_value(t, ri, -1)

	// Row directly under table (no row-group).
	bare_row := layout_test_append_node(&layout, table, .TABLE_ROW)
	bare_cell := layout_test_append_node(&layout, bare_row, .TABLE_CELL)
	ti, gi, ri = table_layout_cell_ancestors(&layout, bare_cell)
	testing.expect_value(t, ti, table)
	testing.expect_value(t, gi, -1)
	testing.expect_value(t, ri, bare_row)
}

@(test)
table_layout_find_cell_neighbor_skips_non_cells_and_grid_edges :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	table := layout_test_append_node(&layout, -1, .TABLE, {}, {}, table_border_test_style(1))
	body := layout_test_append_node(&layout, table, .TABLE_BODY)
	row0 := layout_test_append_node(
		&layout,
		body,
		.TABLE_ROW,
		{x = .TABLE_CELL, y = .TABLE_CELL},
	)
	row1 := layout_test_append_node(
		&layout,
		body,
		.TABLE_ROW,
		{x = .TABLE_CELL, y = .TABLE_CELL},
	)

	// Non-cell sibling should be ignored when walking columns.
	_ = layout_test_append_node(&layout, row0, .TEXT)
	c00 := layout_test_append_node(
		&layout,
		row0,
		.TABLE_CELL,
		{},
		{40, 20},
		table_border_test_style(1),
	)
	c01 := layout_test_append_node(
		&layout,
		row0,
		.TABLE_CELL,
		{},
		{40, 20},
		table_border_test_style(1),
	)
	c10 := layout_test_append_node(
		&layout,
		row1,
		.TABLE_CELL,
		{},
		{40, 20},
		table_border_test_style(1),
	)
	c11 := layout_test_append_node(
		&layout,
		row1,
		.TABLE_CELL,
		{},
		{40, 20},
		table_border_test_style(1),
	)

	layout.nodes[c00].rect = {0, 0, 40, 20}
	layout.nodes[c01].rect = {40, 0, 40, 20}
	layout.nodes[c10].rect = {0, 20, 40, 20}
	layout.nodes[c11].rect = {40, 20, 40, 20}

	layout_table_prepare_in(&layout, table)
	layout_table_finalize_in(&layout, table)
	tracks := &layout.table_tracks[table]

	pos00 := tracks.cell_positions[c00]
	n, side := table_layout_find_cell_neighbor(&layout, tracks, c00, pos00, 'r')
	testing.expect_value(t, n, c01)
	testing.expect_value(t, side, u8('l'))

	pos01 := tracks.cell_positions[c01]
	n, side = table_layout_find_cell_neighbor(&layout, tracks, c01, pos01, 'r')
	testing.expect_value(t, n, -1)

	pos10 := tracks.cell_positions[c10]
	n, side = table_layout_find_cell_neighbor(&layout, tracks, c10, pos10, 'b')
	testing.expect_value(t, n, -1)

	n, side = table_layout_find_cell_neighbor(&layout, tracks, c10, pos10, 't')
	testing.expect_value(t, n, c00)
	testing.expect_value(t, side, u8('b'))
}

@(test)
table_layout_resolve_collapsed_borders_inactive_and_strips :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	style := table_border_test_style(2)
	table := layout_test_append_node(&layout, -1, .TABLE, {}, {}, style)
	body := layout_test_append_node(&layout, table, .TABLE_BODY, {}, {}, style)
	row := layout_test_append_node(
		&layout,
		body,
		.TABLE_ROW,
		{x = .TABLE_CELL, y = .TABLE_CELL},
		{},
		style,
	)
	cell := layout_test_append_node(&layout, row, .TABLE_CELL, {}, {60, 30}, style)
	layout.nodes[cell].rect = {10, 20, 60, 30}

	layout_table_prepare_in(&layout, table)
	layout_table_finalize_in(&layout, table)
	tracks := &layout.table_tracks[table]
	testing.expect(t, tracks.collapsed)

	resolved := table_layout_resolve_collapsed_borders(&layout, tracks, cell)
	testing.expect(t, resolved.active)
	expect_close(t, resolved.borders.t.width, 2)
	expect_close(t, resolved.borders.l.width, 2)
	expect_close(t, resolved.borders.b.width, 2)
	expect_close(t, resolved.borders.r.width, 2)
	expect_rect(t, resolved.strips[0], {10, 20, 60, 2})
	expect_rect(t, resolved.strips[1], {10, 48, 60, 2})
	expect_rect(t, resolved.strips[2], {10, 20, 2, 30})
	expect_rect(t, resolved.strips[3], {68, 20, 2, 30})

	tracks.collapsed = false
	inactive := table_layout_resolve_collapsed_borders(&layout, tracks, cell)
	testing.expect(t, !inactive.active)

	tracks.collapsed = true
	delete_key(&tracks.cell_positions, cell)
	missing := table_layout_resolve_collapsed_borders(&layout, tracks, cell)
	testing.expect(t, !missing.active)
}

@(test)
table_layout_resolve_collapsed_borders_prefers_thicker_cell_on_outer :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	table := layout_test_append_node(&layout, -1, .TABLE, {}, {}, table_border_test_style(1))
	body := layout_test_append_node(&layout, table, .TABLE_BODY)
	row := layout_test_append_node(&layout, body, .TABLE_ROW, {x = .TABLE_CELL, y = .TABLE_CELL})
	cell := layout_test_append_node(
		&layout,
		row,
		.TABLE_CELL,
		{},
		{50, 25},
		table_border_test_style(4),
	)
	layout.nodes[cell].rect = {0, 0, 50, 25}

	layout_table_prepare_in(&layout, table)
	layout_table_finalize_in(&layout, table)
	tracks := &layout.table_tracks[table]

	resolved := table_layout_resolve_collapsed_borders(&layout, tracks, cell)
	testing.expect(t, resolved.active)
	expect_close(t, resolved.borders.t.width, 4)
	testing.expect(t, resolved.borders.t.source == .CELL)
	expect_close(t, resolved.borders.l.width, 4)
	testing.expect(t, resolved.borders.l.source == .CELL)
}

@(test)
table_layout_resolve_collapsed_borders_equal_width_prefers_cell_source :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	style := table_border_test_style(2)
	table := layout_test_append_node(&layout, -1, .TABLE, {}, {}, style)
	body := layout_test_append_node(&layout, table, .TABLE_BODY, {}, {}, style)
	row := layout_test_append_node(
		&layout,
		body,
		.TABLE_ROW,
		{x = .TABLE_CELL, y = .TABLE_CELL},
		{},
		style,
	)
	cell := layout_test_append_node(&layout, row, .TABLE_CELL, {}, {40, 20}, style)
	layout.nodes[cell].rect = {0, 0, 40, 20}

	layout_table_prepare_in(&layout, table)
	layout_table_finalize_in(&layout, table)
	tracks := &layout.table_tracks[table]

	resolved := table_layout_resolve_collapsed_borders(&layout, tracks, cell)
	testing.expect(t, resolved.active)
	testing.expect(t, resolved.borders.t.source == .CELL)
	testing.expect(t, resolved.borders.l.source == .CELL)
	testing.expect_value(t, resolved.borders.t.order, cell)
}

@(test)
table_side_is_straight_all_sides_and_corners_eps :: proc(t: ^testing.T) {
	radius := Radius_px{tl = 2, tr = 3, bl = 4, br = 5}
	testing.expect(t, !table_side_is_straight(radius, 't'))
	testing.expect(t, !table_side_is_straight(radius, 'b'))
	testing.expect(t, !table_side_is_straight(radius, 'l'))
	testing.expect(t, !table_side_is_straight(radius, 'r'))

	only_tr := Radius_px{tr = 1}
	testing.expect(t, !table_side_is_straight(only_tr, 't'))
	testing.expect(t, !table_side_is_straight(only_tr, 'r'))
	testing.expect(t, table_side_is_straight(only_tr, 'b'))
	testing.expect(t, table_side_is_straight(only_tr, 'l'))

	eps := TABLE_CORNER_EPS
	testing.expect(t, table_corners_touch(0, 0, eps, eps))
	testing.expect(t, !table_corners_touch(0, 0, eps + 0.01, 0))
	testing.expect(t, table_corners_touch(10, 10, 10 - 0.5, 10 + 0.5))
	testing.expect(t, !table_corners_touch(10, 10, 10 - (eps + 0.1), 10))
}

@(test)
table_descendant_outer_radius_tr_bl_zero_and_asymmetric :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			_ = layout_test_begin()
			defer layout_test_end(&state.ui.layout)

			table := layout_test_append_node(&state.ui.layout, -1, .TABLE)
			body := layout_test_append_node(&state.ui.layout, table, .TABLE_BODY)
			row := layout_test_append_node(&state.ui.layout, body, .TABLE_ROW)
			tr := layout_test_append_node(&state.ui.layout, row, .TABLE_CELL)
			bl := layout_test_append_node(&state.ui.layout, row, .TABLE_CELL)
			mid := layout_test_append_node(&state.ui.layout, row, .TABLE_CELL)

			state.ui.layout.nodes[table].rect = {0, 0, 100, 80}
			state.ui.layout.nodes[table].border = {1, 5, 2, 4}
			state.ui.layout.nodes[table].padding = {3, 1, 1, 2}
			corners := Radius_corners {
				tl = f32(20),
				tr = f32(18),
				bl = f32(16),
				br = f32(14),
			}
			state.ui.layout.nodes[table].config.radius = corners
			state.ui.layout.nodes[table].ui_id = UI_Id(10)

			// Content: x=3, y=4, w=91, h=70  (insets t=4,b=6,l=3,r=6)
			state.ui.layout.nodes[tr].rect = {54, 4, 40, 20}
			state.ui.layout.nodes[tr].ui_id = UI_Id(11)
			state.ui.layout.id_to_node[UI_Id(11)] = tr

			state.ui.layout.nodes[bl].rect = {3, 54, 40, 20}
			state.ui.layout.nodes[bl].ui_id = UI_Id(12)
			state.ui.layout.id_to_node[UI_Id(12)] = bl

			state.ui.layout.nodes[mid].rect = {30, 30, 20, 20}
			state.ui.layout.nodes[mid].ui_id = UI_Id(13)
			state.ui.layout.id_to_node[UI_Id(13)] = mid

			got_tr := table_descendant_outer_radius(UI_Id(11), state.ui.layout.nodes[tr].rect)
			expect_close(t, got_tr.tr, 12) // 18 - max(4, 6)
			expect_close(t, got_tr.tl, 0)

			got_bl := table_descendant_outer_radius(UI_Id(12), state.ui.layout.nodes[bl].rect)
			expect_close(t, got_bl.bl, 10) // 16 - max(6, 3)
			expect_close(t, got_bl.br, 0)

			got_mid := table_descendant_outer_radius(UI_Id(13), state.ui.layout.nodes[mid].rect)
			expect_radius(t, got_mid, {})

			state.ui.layout.nodes[table].config.radius = f32(0)
			got_zero := table_descendant_outer_radius(UI_Id(11), state.ui.layout.nodes[tr].rect)
			expect_radius(t, got_zero, {})
		},
	)
}

@(test)
table_collapsed_border_color_transparent_and_oob_order :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			_ = layout_test_begin()
			defer layout_test_end(&state.ui.layout)

			cfg: Resolved_Widget_Style
			cfg.border_color = RGBA{10, 20, 30, 0}
			node := layout_test_append_node(&state.ui.layout, -1, .TABLE_CELL, {}, {}, cfg)
			frame, event := ui_test_frame_event()

			fallback, ok := table_collapsed_border_color(
				{width = 2, order = node, source = .CELL},
				&frame,
				event,
			)
			testing.expect(t, ok)
			black := css_color_to_rgba(.BLACK)
			testing.expect_value(t, fallback.r, black.r)
			testing.expect_value(t, fallback.g, black.g)
			testing.expect_value(t, fallback.b, black.b)
			testing.expect_value(t, fallback.a, black.a)

			_, oob := table_collapsed_border_color(
				{width = 1, order = len(state.ui.layout.nodes) + 5},
				&frame,
				event,
			)
			testing.expect(t, !oob)
		},
	)
}

@(test)
table_draw_border_strip_and_collapsed_cell_paths :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			_ = layout_test_begin()
			defer layout_test_end(&state.ui.layout)

			cfg: Resolved_Widget_Style
			cfg.border_color = RGBA{0, 0, 0, 255}
			node := layout_test_append_node(&state.ui.layout, -1, .TABLE_CELL, {}, {}, cfg)
			frame, event := ui_test_frame_event()

			before := len(state.gpu_state.batch.vertices)
			table_draw_border_strip({}, {0, 0, 0, 255})
			table_draw_border_strip({0, 0, 10, 2}, {0, 0, 0, 0})
			testing.expect_value(t, len(state.gpu_state.batch.vertices), before)

			table_draw_border_strip({0, 0, 10, 2}, {0, 0, 0, 255})
			testing.expect(t, len(state.gpu_state.batch.vertices) > before)

			inactive := Layout_Collapsed_Borders{}
			before_inactive := len(state.gpu_state.batch.vertices)
			table_draw_collapsed_cell({0, 0, 40, 20}, {255, 0, 0, 255}, inactive, {}, &frame, event)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), before_inactive)

			side := Table_Border_Side{width = 2, source = .CELL, order = node}
			collapsed := Layout_Collapsed_Borders {
				active  = true,
				borders = {t = side, b = side, l = side, r = side},
				strips  = {{0, 0, 40, 2}, {0, 18, 40, 2}, {0, 0, 2, 20}, {38, 0, 2, 20}},
			}
			before_draw := len(state.gpu_state.batch.vertices)
			table_draw_collapsed_cell(
				{0, 0, 40, 20},
				{255, 0, 0, 128},
				collapsed,
				{},
				&frame,
				event,
			)
			testing.expect(t, len(state.gpu_state.batch.vertices) > before_draw)

			// Rounded path: fill+border quad plus straight-side strips.
			before_round := len(state.gpu_state.batch.vertices)
			table_draw_collapsed_cell(
				{0, 0, 40, 20},
				{0, 255, 0, 255},
				collapsed,
				{tl = 4, tr = 0, bl = 0, br = 0},
				&frame,
				event,
			)
			testing.expect(t, len(state.gpu_state.batch.vertices) > before_round)
		},
	)
}

@(test)
table_borders_collapsed_for_widget_gap_y_and_non_table :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			_ = layout_test_begin()
			defer layout_test_end(&state.ui.layout)

			plain := layout_test_append_node(&state.ui.layout, -1, .RECT)
			state.ui.layout.nodes[plain].ui_id = UI_Id(1)
			state.ui.layout.id_to_node[UI_Id(1)] = plain
			testing.expect(t, !table_layout_borders_collapsed_for_widget(UI_Id(1), .RECT))

			table := layout_test_append_node(
				&state.ui.layout,
				-1,
				.TABLE,
				{},
				{},
				table_border_test_style(0),
			)
			row := layout_test_append_node(&state.ui.layout, table, .TABLE_ROW)
			cell := layout_test_append_node(&state.ui.layout, row, .TABLE_CELL)
			state.ui.layout.nodes[cell].ui_id = UI_Id(2)
			state.ui.layout.id_to_node[UI_Id(2)] = cell
			testing.expect(t, table_layout_borders_collapsed_for_widget(UI_Id(2), .TABLE_CELL))

			state.ui.layout.nodes[table].config.gap_y = 2
			testing.expect(t, !table_layout_borders_collapsed_for_widget(UI_Id(2), .TABLE_CELL))
		},
	)
}

@(test)
table_border_side_from_node_preserves_color_and_unset_border :: proc(t: ^testing.T) {
	node := Layout_Node {
		config = table_border_test_sides(0, 0, 7, 0),
	}
	colored := table_border_side_from_node(&node, 'l', .ROW, 3, {9, 8, 7, 6})
	expect_close(t, colored.width, 7)
	testing.expect_value(t, colored.color.r, u8(9))
	testing.expect(t, colored.source == .ROW)
	testing.expect_value(t, colored.order, 3)

	unset := table_border_side_from_node(&Layout_Node{}, 't', .TABLE, 0, {1, 1, 1, 1})
	expect_close(t, unset.width, 0)
}

