package oni

import "core:sync"
import "core:testing"


expect_close :: proc(t: ^testing.T, got, want: f32, loc := #caller_location) {
	testing.expectf(t, abs(got - want) < 1e-4, "got=%v want=%v", got, want, loc = loc)
}

@(private)
expect_rect :: proc(t: ^testing.T, got, want: Rect, loc := #caller_location) {
	expect_close(t, got.x, want.x, loc = loc)
	expect_close(t, got.y, want.y, loc = loc)
	expect_close(t, got.w, want.w, loc = loc)
	expect_close(t, got.h, want.h, loc = loc)
}

@(private)
expect_rect_inside :: proc(t: ^testing.T, outer, inner: Rect, loc := #caller_location) {
	testing.expectf(
		t,
		inner.x >= outer.x - 1e-4,
		"inner.x=%v outside outer.x=%v",
		inner.x,
		outer.x,
		loc = loc,
	)
	testing.expectf(
		t,
		inner.y >= outer.y - 1e-4,
		"inner.y=%v outside outer.y=%v",
		inner.y,
		outer.y,
		loc = loc,
	)
	testing.expectf(
		t,
		inner.x + inner.w <= outer.x + outer.w + 1e-4,
		"inner right=%v outside outer right=%v",
		inner.x + inner.w,
		outer.x + outer.w,
		loc = loc,
	)
	testing.expectf(
		t,
		inner.y + inner.h <= outer.y + outer.h + 1e-4,
		"inner bottom=%v outside outer bottom=%v",
		inner.y + inner.h,
		outer.y + outer.h,
		loc = loc,
	)
}

@(private)
layout_len_fixed :: proc(v: f32) -> Length {
	return {kind = .FIXED, value = v}
}

@(private)
layout_len_percent :: proc(v: f32) -> Length {
	return {kind = .PERCENT, value = v}
}

@(private)
test_global_state_guard: sync.Mutex

@(private)
with_test_global_state :: proc(
	test_state: ^State,
	body: proc(test_state: ^State, t: ^testing.T),
	t: ^testing.T,
) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	saved_state := state
	saved_theme := theme
	defer {
		state = saved_state
		theme = saved_theme
	}

	state = test_state
	theme = nil
	body(test_state, t)
}

@(private)
with_layout_solve :: proc(t: ^testing.T, body: proc(layout: ^Layout_State, t: ^testing.T)) {
	test_state: State

	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	saved_state := state
	saved_theme := theme
	defer {
		state = saved_state
		theme = saved_theme
	}

	state = &test_state
	theme = nil
	test_state.ui.layout = layout_test_begin()
	defer layout_test_end(&test_state.ui.layout)
	body(&test_state.ui.layout, t)
}

@(private)
layout_test_begin :: proc() -> Layout_State {
	return Layout_State {
		table_tracks = make(map[int]Layout_Table_Tracks),
		id_to_node = make(map[UI_Id]int),
	}
}

@(private)
layout_test_append_node :: proc(
	layout: ^Layout_State,
	parent: int,
	kind: Widget_Kind,
	justify: Justify_Pos = {},
	desired: Vec2 = {},
	config: Resolved_Widget_Style = {},
) -> int {
	node_config := config
	node_config.justify = justify

	padding, _ := resolve_padding_value(node_config.padding)
	border, _ := resolve_border_value(node_config.border)

	append(
		&layout.nodes,
		Layout_Node {
			kind = kind,
			config = node_config,
			desired = desired,
			padding = padding,
			border = border,
			parent = parent,
		},
	)
	node_index := len(layout.nodes) - 1
	if parent >= 0 {
		append(&layout.nodes[parent].child_indices, node_index)
	}
	return node_index
}

@(private)
layout_test_set_insets :: proc(
	layout: ^Layout_State,
	index: int,
	padding: Pd_px = {},
	border: Bd_px = {},
) {
	layout.nodes[index].padding = padding
	layout.nodes[index].border = border
}

@(private)
layout_test_end :: proc(layout: ^Layout_State) {
	for _, tracks in layout.table_tracks {
		delete(tracks.rows)
		delete(tracks.col_widths)
		delete(tracks.row_heights)
		delete(tracks.cell_positions)
	}
	delete(layout.table_tracks)
	layout.table_tracks = nil

	layout_release_node_children(layout)
	delete(layout.nodes)
	layout.nodes = nil

	delete(layout.node_stack)
	layout.node_stack = nil
	delete(layout.bounds_stack)
	layout.bounds_stack = nil
	delete(layout.space_markers)
	layout.space_markers = nil
	delete(layout.id_to_node)
	layout.id_to_node = nil
}

@(test)
layout_justify_table_cell_detects_explicit_axes :: proc(t: ^testing.T) {
	testing.expect(t, layout_justify_uses_TABLE_CELL_x(Justify_Pos{x = .TABLE_CELL}))
	testing.expect(t, !layout_justify_uses_TABLE_CELL_x(Justify_Pos{y = .TABLE_CELL}))
	testing.expect(t, layout_justify_uses_TABLE_CELL_y(Justify_Pos{y = .TABLE_CELL}))
	testing.expect(t, !layout_justify_uses_TABLE_CELL_y(Justify_Pos{x = .TABLE_CELL}))
}

@(test)
layout_table_cell_does_not_use_sibling_content_align :: proc(t: ^testing.T) {
	_, ok := layout_content_align_target(.TABLE_CELL, 120, 30)
	testing.expect(t, !ok)
	testing.expect(t, !justify_align_is_content(.TABLE_CELL))
}

@(test)
layout_table_collect_rows_preserves_table_order :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	table := layout_test_append_node(&layout, -1, .TABLE)
	head := layout_test_append_node(&layout, table, .TABLE_HEAD)
	body := layout_test_append_node(&layout, table, .TABLE_BODY)
	head_row := layout_test_append_node(&layout, head, .TABLE_ROW)
	body_row := layout_test_append_node(&layout, body, .TABLE_ROW)

	rows := layout_table_collect_rows_in(&layout, table)
	defer delete(rows)

	testing.expect_value(t, len(rows), 2)
	testing.expect_value(t, rows[0], head_row)
	testing.expect_value(t, rows[1], body_row)
}

@(test)
layout_table_cell_alignment_sets_shared_column_widths_across_rows :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	table := layout_test_append_node(&layout, -1, .TABLE)
	body := layout_test_append_node(&layout, table, .TABLE_BODY)
	row1 := layout_test_append_node(&layout, body, .TABLE_ROW, {x = .TABLE_CELL, y = .TABLE_CELL})
	row2 := layout_test_append_node(&layout, body, .TABLE_ROW, {x = .TABLE_CELL, y = .TABLE_CELL})
	cell11 := layout_test_append_node(&layout, row1, .TABLE_CELL, {}, {80, 20})
	cell12 := layout_test_append_node(&layout, row1, .TABLE_CELL, {}, {120, 20})
	cell21 := layout_test_append_node(&layout, row2, .TABLE_CELL, {}, {60, 30})
	cell22 := layout_test_append_node(&layout, row2, .TABLE_CELL, {}, {90, 40})

	layout_table_prepare_in(&layout, table)

	tracks, ok := layout.table_tracks[table]
	testing.expect(t, ok)
	expect_close(t, tracks.col_widths[0], 80)
	expect_close(t, tracks.col_widths[1], 120)
	expect_close(t, tracks.row_heights[0], 20)
	expect_close(t, tracks.row_heights[1], 40)

	row2_track, row2_ok := layout_table_row_track_index(&tracks, row2)
	testing.expect(t, row2_ok)
	testing.expect_value(t, row2_track, 1)

	size11 := layout_table_apply_cell_size(
		&layout.nodes[row1],
		&tracks,
		0,
		0,
		&layout.nodes[cell11],
		{},
	)
	size12 := layout_table_apply_cell_size(
		&layout.nodes[row1],
		&tracks,
		0,
		1,
		&layout.nodes[cell12],
		{},
	)
	size21 := layout_table_apply_cell_size(
		&layout.nodes[row2],
		&tracks,
		row2_track,
		0,
		&layout.nodes[cell21],
		{},
	)
	size22 := layout_table_apply_cell_size(
		&layout.nodes[row2],
		&tracks,
		row2_track,
		1,
		&layout.nodes[cell22],
		{},
	)

	expect_close(t, size11.x, 80)
	expect_close(t, size12.x, 120)
	expect_close(t, size21.x, 80)
	expect_close(t, size22.x, 120)
	expect_close(t, size11.y, 20)
	expect_close(t, size12.y, 20)
	expect_close(t, size21.y, 40)
	expect_close(t, size22.y, 40)
}

@(test)
layout_table_cell_alignment_includes_heading_cells :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	table := layout_test_append_node(&layout, -1, .TABLE)
	head := layout_test_append_node(&layout, table, .TABLE_HEAD)
	body := layout_test_append_node(&layout, table, .TABLE_BODY)
	head_row := layout_test_append_node(&layout, head, .TABLE_ROW, {x = .TABLE_CELL})
	body_row := layout_test_append_node(&layout, body, .TABLE_ROW, {x = .TABLE_CELL})
	layout_test_append_node(&layout, head_row, .TABLE_HEADING, {}, {140, 30})
	layout_test_append_node(&layout, head_row, .TABLE_HEADING, {}, {60, 30})
	layout_test_append_node(&layout, body_row, .TABLE_CELL, {}, {80, 20})
	layout_test_append_node(&layout, body_row, .TABLE_CELL, {}, {110, 20})

	layout_table_prepare_in(&layout, table)

	tracks, ok := layout.table_tracks[table]
	testing.expect(t, ok)
	expect_close(t, tracks.col_widths[0], 140)
	expect_close(t, tracks.col_widths[1], 110)
}

@(test)
layout_table_cell_alignment_respects_fixed_width_and_height :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	table := layout_test_append_node(&layout, -1, .TABLE)
	body := layout_test_append_node(&layout, table, .TABLE_BODY)
	row := layout_test_append_node(&layout, body, .TABLE_ROW, {x = .TABLE_CELL, y = .TABLE_CELL})
	cell1 := layout_test_append_node(&layout, row, .TABLE_CELL, {}, {100, 80})
	cell2 := layout_test_append_node(&layout, row, .TABLE_CELL, {}, {50, 40})
	layout.nodes[cell1].config.width = {
		kind  = .FIXED,
		value = 70,
	}
	layout.nodes[cell1].config.height = {
		kind  = .FIXED,
		value = 30,
	}

	layout_table_prepare_in(&layout, table)

	tracks, ok := layout.table_tracks[table]
	testing.expect(t, ok)
	expect_close(t, tracks.col_widths[0], 70)
	expect_close(t, tracks.col_widths[1], 50)
	expect_close(t, tracks.row_heights[0], 40)

	size1 := layout_table_apply_cell_size(
		&layout.nodes[row],
		&tracks,
		0,
		0,
		&layout.nodes[cell1],
		{},
	)
	size2 := layout_table_apply_cell_size(
		&layout.nodes[row],
		&tracks,
		0,
		1,
		&layout.nodes[cell2],
		{},
	)

	expect_close(t, size1.x, 70)
	expect_close(t, size1.y, 30)
	expect_close(t, size2.x, 50)
	expect_close(t, size2.y, 40)
}

@(test)
layout_table_cell_y_only_keeps_cell_widths :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	table := layout_test_append_node(&layout, -1, .TABLE)
	body := layout_test_append_node(&layout, table, .TABLE_BODY)
	row := layout_test_append_node(&layout, body, .TABLE_ROW, {x = .START, y = .TABLE_CELL})
	cell1 := layout_test_append_node(&layout, row, .TABLE_CELL, {}, {80, 20})
	cell2 := layout_test_append_node(&layout, row, .TABLE_CELL, {}, {120, 40})

	layout_table_prepare_in(&layout, table)

	tracks, ok := layout.table_tracks[table]
	testing.expect(t, ok)
	size1 := layout_table_apply_cell_size(
		&layout.nodes[row],
		&tracks,
		0,
		0,
		&layout.nodes[cell1],
		{},
	)
	size2 := layout_table_apply_cell_size(
		&layout.nodes[row],
		&tracks,
		0,
		1,
		&layout.nodes[cell2],
		{},
	)

	expect_close(t, size1.x, 80)
	expect_close(t, size2.x, 120)
	expect_close(t, size1.y, 40)
	expect_close(t, size2.y, 40)
}

@(test)
layout_nested_table_solve_equalizes_heading_and_cell_widths :: proc(t: ^testing.T) {
	test_state: State
	with_test_global_state(&test_state, proc(test_state: ^State, t: ^testing.T) {
			defer layout_test_end(&test_state.ui.layout)

			test_state.ui.layout.table_tracks = make(map[int]Layout_Table_Tracks)

			layout := &test_state.ui.layout
			root := layout_test_append_node(
				layout,
				-1,
				.RECT,
				{},
				{400, 300},
				{direction = .VERTICAL},
			)
			table := layout_test_append_node(
				layout,
				root,
				.TABLE,
				{x = .STRETCH, y = .STRETCH},
				{300, 200},
				{direction = .VERTICAL},
			)
			head := layout_test_append_node(
				layout,
				table,
				.TABLE_HEAD,
				{},
				{300, 40},
				{direction = .VERTICAL},
			)
			body := layout_test_append_node(
				layout,
				table,
				.TABLE_BODY,
				{},
				{300, 160},
				{direction = .VERTICAL},
			)
			head_row := layout_test_append_node(
				layout,
				head,
				.TABLE_ROW,
				{x = .TABLE_CELL, y = .TABLE_CELL},
				{300, 40},
				{direction = .HORIZONTAL},
			)
			body_row := layout_test_append_node(
				layout,
				body,
				.TABLE_ROW,
				{x = .TABLE_CELL, y = .TABLE_CELL},
				{300, 30},
				{direction = .HORIZONTAL},
			)
			heading := layout_test_append_node(layout, head_row, .TABLE_HEADING, {}, {90, 30})
			cell := layout_test_append_node(layout, body_row, .TABLE_CELL, {}, {70, 30})

			layout_solve(&layout.nodes[root], {0, 0, 400, 300})

			heading_rect := layout.nodes[heading].rect
			cell_rect := layout.nodes[cell].rect

			expect_close(t, heading_rect.w, cell_rect.w)
			expect_close(t, heading_rect.w, 90)
		}, t)
}

@(test)
table_border_compare_prefers_thicker_width :: proc(t: ^testing.T) {
	a := Table_Border_Side {
		width  = 2,
		source = .CELL,
		order  = 1,
	}
	b := Table_Border_Side {
		width  = 1,
		source = .ROW,
		order  = 0,
	}
	testing.expect(t, table_border_compare(a, b) > 0)
}

@(test)
table_border_compare_prefers_cell_source_on_equal_width :: proc(t: ^testing.T) {
	a := Table_Border_Side {
		width  = 1,
		source = .CELL,
		order  = 0,
	}
	b := Table_Border_Side {
		width  = 1,
		source = .ROW,
		order  = 1,
	}
	testing.expect(t, table_border_compare(a, b) > 0)
}

@(test)
table_border_compare_prefers_table_only_when_thicker :: proc(t: ^testing.T) {
	table := Table_Border_Side {
		width  = 2,
		source = .TABLE,
		order  = 0,
	}
	cell := Table_Border_Side {
		width  = 1,
		source = .CELL,
		order  = 1,
	}
	testing.expect(t, table_border_compare(table, cell) > 0)

	equal_table := Table_Border_Side {
		width  = 1,
		source = .TABLE,
		order  = 0,
	}
	equal_cell := Table_Border_Side {
		width  = 1,
		source = .CELL,
		order  = 1,
	}
	testing.expect(t, table_border_compare(equal_cell, equal_table) > 0)
}

@(test)
table_collapsed_borders_keep_vertical_edge_between_cells :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	border := Border(Bd{t = 1, b = 1, l = 1, r = 1})

	table := layout_test_append_node(
		&layout,
		-1,
		.TABLE,
		{},
		{},
		{gap_x = 0, gap_y = 0, border = border},
	)
	head := layout_test_append_node(&layout, table, .TABLE_HEAD, {}, {}, {border = border})
	row := layout_test_append_node(
		&layout,
		head,
		.TABLE_ROW,
		{x = .TABLE_CELL, y = .TABLE_CELL},
		{},
		{border = border},
	)
	h1 := layout_test_append_node(&layout, row, .TABLE_HEADING, {}, {80, 30}, {border = border})
	h2 := layout_test_append_node(&layout, row, .TABLE_HEADING, {}, {80, 30}, {border = border})

	layout.nodes[h1].rect = {0, 0, 80, 30}
	layout.nodes[h2].rect = {80, 0, 80, 30}

	layout_table_prepare_in(&layout, table)
	layout_table_finalize_in(&layout, table)

	collapsed := layout.nodes[h2].collapsed_borders
	testing.expect(t, collapsed.active)
	expect_close(t, collapsed.borders.l.width, 1)
	testing.expect(t, collapsed.borders.l.source == .CELL)
}

@(test)
table_collapsed_row_border_forms_vertical_grid_line :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	row_border := Border(Bd{t = 1, b = 1, l = 1, r = 1})

	table := layout_test_append_node(&layout, -1, .TABLE, {}, {}, {gap_x = 0, gap_y = 0})
	head := layout_test_append_node(&layout, table, .TABLE_HEAD)
	row := layout_test_append_node(
		&layout,
		head,
		.TABLE_ROW,
		{x = .TABLE_CELL, y = .TABLE_CELL},
		{},
		{border = row_border},
	)
	h1 := layout_test_append_node(&layout, row, .TABLE_HEADING, {}, {80, 30})
	h2 := layout_test_append_node(&layout, row, .TABLE_HEADING, {}, {80, 30})

	layout.nodes[h1].rect = {0, 0, 80, 30}
	layout.nodes[h2].rect = {80, 0, 80, 30}

	layout_table_prepare_in(&layout, table)
	layout_table_finalize_in(&layout, table)

	collapsed := layout.nodes[h2].collapsed_borders
	testing.expect(t, collapsed.active)
	expect_close(t, collapsed.borders.l.width, 1)
	testing.expect(t, collapsed.borders.l.source == .ROW)
}

@(test)
layout_push_inherited_table_border_is_concrete :: proc(t: ^testing.T) {
	test_state: State
	with_test_global_state(
		&test_state,
		proc(test_state: ^State, t: ^testing.T) {
			ui_init()
			defer ui_shutdown()

			theme = new(Theme)
			theme^ = Theme {
				palette      = palette,
				border       = 0,
				border_color = .BLACK,
				background   = .TRANSPARENT,
				gap_x        = u16(0),
				gap_y        = u16(0),
			}
			defer free(theme)

			layout_reset()
			ui_push_style(style_root(.SCREEN, Rect{0, 0, 400, 300}))
			defer ui_pop_style()

			empty: Widget_Frame_State
			event := Widget_Event(Widget_Frame_State) {
				frame_state = empty,
			}

			table_cfg := resolve_widget_config(
				{
					kind = .TABLE,
					gap_x = {mode = .Value, value = u16(0)},
					gap_y = {mode = .Value, value = u16(0)},
				},
				{border = {mode = .Value, value = f32(1)}},
				&empty,
				event,
			)
			being_children(UI_Id(1), table_cfg)

			head_cfg := resolve_widget_config(
				{kind = .TABLE_HEAD},
				{border = {mode = .Value, value = Inherit.INHERIT}},
				&empty,
				event,
			)
			being_children(UI_Id(2), head_cfg)

			row_cfg := resolve_widget_config(
				{kind = .TABLE_ROW},
				{
					border = {mode = .Value, value = Inherit.INHERIT},
					justify = {
						mode = .Value,
						value = Justify_Pos{x = .TABLE_CELL, y = .TABLE_CELL},
					},
				},
				&empty,
				event,
			)
			being_children(UI_Id(3), row_cfg)

			h1_cfg := resolve_widget_config(
				{kind = .TABLE_HEADING},
				{border = {mode = .Value, value = Inherit.INHERIT}},
				&empty,
				event,
			)
			_ = layout_push_node(UI_Id(4), h1_cfg)
			layout_pop_node()

			h2_cfg := resolve_widget_config(
				{kind = .TABLE_HEADING},
				{border = {mode = .Value, value = Inherit.INHERIT}},
				&empty,
				event,
			)
			h2 := layout_push_node(UI_Id(5), h2_cfg)
			h2_border, h2_ok := resolve_border_value(h2.config.border)
			testing.expect(t, h2_ok)
			expect_close(t, h2_border.l, 1)
			expect_close(t, h2_border.r, 1)

			// Mirror a 2-heading row and ensure collapse keeps the shared vertical edge.
			h1_index := test_state.ui.layout.id_to_node[UI_Id(4)]
			h2_index := test_state.ui.layout.id_to_node[UI_Id(5)]
			table_index := test_state.ui.layout.id_to_node[UI_Id(1)]
			test_state.ui.layout.nodes[h1_index].rect = {0, 0, 80, 30}
			test_state.ui.layout.nodes[h2_index].rect = {80, 0, 80, 30}
			test_state.ui.layout.nodes[h1_index].desired = {80, 30}
			test_state.ui.layout.nodes[h2_index].desired = {80, 30}
			layout_table_prepare_in(&test_state.ui.layout, table_index)
			layout_table_finalize_in(&test_state.ui.layout, table_index)
			collapsed := test_state.ui.layout.nodes[h2_index].collapsed_borders
			testing.expect(t, collapsed.active)
			expect_close(t, collapsed.borders.l.width, 1)
			testing.expect(t, collapsed.borders.l.source == .CELL)

			layout_pop_node()

			end_children()
			end_children()
			end_children()
		},
		t,
	)
}

@(test)
layout_table_finalize_assigns_cell_positions :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	table := layout_test_append_node(&layout, -1, .TABLE)
	body := layout_test_append_node(&layout, table, .TABLE_BODY)
	row1 := layout_test_append_node(&layout, body, .TABLE_ROW, {x = .TABLE_CELL, y = .TABLE_CELL})
	row2 := layout_test_append_node(&layout, body, .TABLE_ROW, {x = .TABLE_CELL, y = .TABLE_CELL})
	cell11 := layout_test_append_node(&layout, row1, .TABLE_CELL, {}, {80, 20})
	cell12 := layout_test_append_node(&layout, row1, .TABLE_CELL, {}, {80, 20})
	_ = layout_test_append_node(&layout, row2, .TABLE_CELL, {}, {80, 20})

	layout.nodes[table].ui_id = UI_Id(1)
	layout.nodes[table].config.gap_x = 0
	layout.nodes[table].config.gap_y = 0
	layout_table_prepare_in(&layout, table)
	layout_table_finalize_in(&layout, table)

	tracks := layout.table_tracks[table]
	pos11, ok11 := tracks.cell_positions[cell11]
	testing.expect(t, ok11)
	testing.expect(t, pos11.row == 0 && pos11.col == 0)
	pos12, ok12 := tracks.cell_positions[cell12]
	testing.expect(t, ok12)
	testing.expect(t, pos12.row == 0 && pos12.col == 1)
}

@(test)
ui_shutdown_releases_heap_state :: proc(t: ^testing.T) {
	test_state: State
	with_test_global_state(&test_state, proc(test_state: ^State, t: ^testing.T) {
			_ = test_state
			ui_init()
			defer ui_shutdown()

			layout_id := UI_Id(42)
			_ = widget_lifecycle_entry(layout_id)

			register_tabbable("tab-target")
			register_static_id("widget", "runtime-key")
			consume_hover_transition("runtime-key", true)
			consume_pointer_click("runtime-key", true, true, false)
		}, t)
}

@(test)
layout_finalize_image_node_owns_object_fit :: proc(t: ^testing.T) {
	node := Layout_Node {
		rect = {10, 20, 200, 100},
		padding = {t = 4, b = 4, l = 8, r = 8},
		border = {t = 1, b = 1, l = 1, r = 1},
		image_input = {
			src = {0, 0, 50, 50},
			fit = .CONTAIN,
			pos = {0.5, 0.5, 0, 0},
			active = true,
		},
	}

	layout_finalize_image_node(&node)

	testing.expect(t, node.image.active)
	expect_close(t, node.image.content.x, 19)
	expect_close(t, node.image.content.y, 25)
	expect_close(t, node.image.content.w, 182)
	expect_close(t, node.image.content.h, 90)
	expect_close(t, node.image.dst.w, 90)
	expect_close(t, node.image.dst.h, 90)
	expect_close(t, node.image.dst.x, 19 + (182 - 90) * 0.5)
	expect_close(t, node.image.dst.y, 25)
}

@(test)
layout_finalize_image_scale_down_large_src_fits_content :: proc(t: ^testing.T) {
	node := Layout_Node {
		rect = {0, 0, 464, 464},
		image_input = {
			src = {0, 0, 1064, 1330},
			fit = .SCALE_DOWN,
			pos = {0.5, 0.5, 0, 0},
			active = true,
		},
	}

	layout_finalize_image_node(&node)

	testing.expect(t, node.image.active)
	expect_close(t, node.image.content.w, 464)
	expect_close(t, node.image.content.h, 464)
	// min(464/1064, 464/1330) * 1064 ≈ 371.07, height fills 464
	expect_close(t, node.image.dst.h, 464)
	expect_close(t, node.image.dst.w, 1064 * (464.0 / 1330.0))
	testing.expect(t, node.image.dst.w <= node.image.content.w + 0.01)
	testing.expect(t, node.image.dst.h <= node.image.content.h + 0.01)
}

@(test)
texture_fit_rects_contain_and_scale_down_do_not_exceed_container :: proc(t: ^testing.T) {
	src := Rect{0, 0, 1064, 1330}
	container := Rect{10, 20, 464, 464}
	pos := Resolved_Texture_Pos{0.5, 0.5, 0, 0}

	fits := [2]Texture_Fit{.CONTAIN, .SCALE_DOWN}
	for fit in fits {
		_, dst := texture_fit_rects(src, container, fit, pos)
		testing.expect(t, dst.w <= container.w + 0.01)
		testing.expect(t, dst.h <= container.h + 0.01)
		testing.expect(t, dst.x >= container.x - 0.01)
		testing.expect(t, dst.y >= container.y - 0.01)
		testing.expect(t, dst.x + dst.w <= container.x + container.w + 0.01)
		testing.expect(t, dst.y + dst.h <= container.y + container.h + 0.01)
	}
}

@(test)
table_border_strip_rect_matches_side_geometry :: proc(t: ^testing.T) {
	rect := Rect{10, 20, 100, 40}

	top := table_border_strip_rect(rect, 't', 3)
	expect_close(t, top.x, 10)
	expect_close(t, top.y, 20)
	expect_close(t, top.w, 100)
	expect_close(t, top.h, 3)

	bottom := table_border_strip_rect(rect, 'b', 2)
	expect_close(t, bottom.y, 58)
	expect_close(t, bottom.h, 2)

	left := table_border_strip_rect(rect, 'l', 4)
	expect_close(t, left.w, 4)
	expect_close(t, left.h, 40)

	right := table_border_strip_rect(rect, 'r', 5)
	expect_close(t, right.x, 105)
	expect_close(t, right.w, 5)
}

@(test)
radius_inherit_resolves_parent_corners :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			parent := resolve_widget_config(
				{},
				{radius = {mode = .Value, value = f32(10)}},
				&frame,
				event,
			)
			ui_push_style(style_child_context(parent))
			defer ui_pop_style()

			child := resolve_widget_config(
				{},
				{radius = {mode = .Value, value = .INHERIT}},
				&frame,
				event,
			)
			corners, ok := resolve_radius_value(child.radius)
			testing.expect(t, ok)
			expect_close(t, corners.tl, 10)
			expect_close(t, corners.tr, 10)
			expect_close(t, corners.bl, 10)
			expect_close(t, corners.br, 10)

			partial := resolve_widget_config(
				{},
				{radius = {mode = .Value, value = Radius_corners{tl = .INHERIT, tr = .INHERIT}}},
				&frame,
				event,
			)
			pc, pok := resolve_radius_value(partial.radius)
			testing.expect(t, pok)
			expect_close(t, pc.tl, 10)
			expect_close(t, pc.tr, 10)
			expect_close(t, pc.bl, 0)
			expect_close(t, pc.br, 0)
		})
}

@(test)
table_descendant_outer_radius_matches_shared_corners :: proc(t: ^testing.T) {
	test_state: State

	with_test_global_state(&test_state, proc(test_state: ^State, t: ^testing.T) {
			_ = layout_test_begin()
			defer layout_test_end(&test_state.ui.layout)
			test_state.ui.layout.table_tracks = make(map[int]Layout_Table_Tracks)

			table := layout_test_append_node(&test_state.ui.layout, -1, .TABLE)
			head := layout_test_append_node(&test_state.ui.layout, table, .TABLE_HEAD)
			row := layout_test_append_node(&test_state.ui.layout, head, .TABLE_ROW)
			cell := layout_test_append_node(&test_state.ui.layout, row, .TABLE_HEADING)

			test_state.ui.layout.nodes[table].rect = {0, 0, 100, 100}
			test_state.ui.layout.nodes[table].border = {1, 1, 1, 1}
			test_state.ui.layout.nodes[table].config.radius = f32(10)
			test_state.ui.layout.nodes[table].ui_id = UI_Id(1)

			test_state.ui.layout.nodes[cell].rect = {1, 1, 40, 20}
			test_state.ui.layout.nodes[cell].ui_id = UI_Id(2)
			test_state.ui.layout.id_to_node[UI_Id(2)] = cell

			got := table_descendant_outer_radius(UI_Id(2), test_state.ui.layout.nodes[cell].rect)
			expect_close(t, got.tl, 9)
			expect_close(t, got.tr, 0)
			expect_close(t, got.bl, 0)
			expect_close(t, got.br, 0)
		}, t)
}

@(test)
border_px_to_bd_roundtrip_resolves :: proc(t: ^testing.T) {
	px := Bd_px {
		t = 1,
		b = 1,
		l = 1,
		r = 1,
	}
	bd := border_px_to_bd(px)
	resolved, ok := resolve_border_value(bd)
	testing.expect(t, ok)
	expect_close(t, resolved.l, 1)
	expect_close(t, resolved.r, 1)

	side := table_border_side_from_node(&Layout_Node{config = {border = bd}}, 'l', .CELL, 0, {})
	expect_close(t, side.width, 1)
}

@(test)
layout_table_prepare_equalizes_uneven_columns_across_three_rows :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	table := layout_test_append_node(&layout, -1, .TABLE, {}, {}, {direction = .VERTICAL})
	body := layout_test_append_node(&layout, table, .TABLE_BODY, {}, {}, {direction = .VERTICAL})

	row1 := layout_test_append_node(
		&layout,
		body,
		.TABLE_ROW,
		{x = .TABLE_CELL, y = .TABLE_CELL},
		{},
		{direction = .HORIZONTAL},
	)
	row2 := layout_test_append_node(
		&layout,
		body,
		.TABLE_ROW,
		{x = .TABLE_CELL, y = .TABLE_CELL},
		{},
		{direction = .HORIZONTAL},
	)
	row3 := layout_test_append_node(
		&layout,
		body,
		.TABLE_ROW,
		{x = .TABLE_CELL, y = .TABLE_CELL},
		{},
		{direction = .HORIZONTAL},
	)

	_ = layout_test_append_node(&layout, row1, .TABLE_CELL, {}, {40, 10})
	_ = layout_test_append_node(&layout, row1, .TABLE_CELL, {}, {10, 10})
	_ = layout_test_append_node(&layout, row2, .TABLE_CELL, {}, {20, 20})
	_ = layout_test_append_node(&layout, row2, .TABLE_CELL, {}, {60, 20})
	_ = layout_test_append_node(&layout, row3, .TABLE_CELL, {}, {30, 15})
	_ = layout_test_append_node(&layout, row3, .TABLE_CELL, {}, {25, 15})

	layout_table_prepare_in(&layout, table)
	tracks, ok := layout.table_tracks[table]
	testing.expect(t, ok)
	testing.expect_value(t, len(tracks.col_widths), 2)
	testing.expect_value(t, len(tracks.row_heights), 3)
	expect_close(t, tracks.col_widths[0], 40)
	expect_close(t, tracks.col_widths[1], 60)
	expect_close(t, tracks.row_heights[0], 10)
	expect_close(t, tracks.row_heights[1], 20)
	expect_close(t, tracks.row_heights[2], 15)
}

@(test)
layout_table_collect_rows_includes_foot_and_skips_caption :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	table := layout_test_append_node(&layout, -1, .TABLE)
	_ = layout_test_append_node(&layout, table, .TABLE_CAPTION)
	head := layout_test_append_node(&layout, table, .TABLE_HEAD)
	body := layout_test_append_node(&layout, table, .TABLE_BODY)
	foot := layout_test_append_node(&layout, table, .TABLE_FOOT)
	head_row := layout_test_append_node(&layout, head, .TABLE_ROW)
	body_row := layout_test_append_node(&layout, body, .TABLE_ROW)
	foot_row := layout_test_append_node(&layout, foot, .TABLE_ROW)

	rows := layout_table_collect_rows_in(&layout, table)
	defer delete(rows)
	testing.expect_value(t, len(rows), 3)
	testing.expect_value(t, rows[0], head_row)
	testing.expect_value(t, rows[1], body_row)
	testing.expect_value(t, rows[2], foot_row)
}

@(test)
layout_table_empty_prepare_is_noop :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	table := layout_test_append_node(&layout, -1, .TABLE)
	layout_table_prepare_in(&layout, table)
	_, ok := layout.table_tracks[table]
	testing.expect(t, !ok)
}

@(test)
layout_table_single_cell_finalize_assigns_origin :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	table := layout_test_append_node(&layout, -1, .TABLE)
	body := layout_test_append_node(&layout, table, .TABLE_BODY)
	row := layout_test_append_node(&layout, body, .TABLE_ROW, {x = .TABLE_CELL, y = .TABLE_CELL})
	cell := layout_test_append_node(&layout, row, .TABLE_CELL, {}, {80, 30})

	layout_table_prepare_in(&layout, table)
	layout_table_finalize_in(&layout, table)

	pos, ok := layout.table_tracks[table].cell_positions[cell]
	testing.expect(t, ok)
	testing.expect(t, pos.row == 0 && pos.col == 0)
}

@(test)
layout_find_table_ancestor_walks_parents :: proc(t: ^testing.T) {
	layout := layout_test_begin()
	defer layout_test_end(&layout)

	root := layout_test_append_node(&layout, -1, .RECT)
	table := layout_test_append_node(&layout, root, .TABLE)
	head := layout_test_append_node(&layout, table, .TABLE_HEAD)
	row := layout_test_append_node(&layout, head, .TABLE_ROW)
	cell := layout_test_append_node(&layout, row, .TABLE_CELL)

	testing.expect_value(t, layout_find_table_ancestor_in(&layout, cell), table)
	testing.expect_value(t, layout_find_table_ancestor_in(&layout, root), -1)
}

@(test)
layout_image_cover_and_none_fit_behaviors :: proc(t: ^testing.T) {
	container := Rect{0, 0, 100, 50}
	src := Rect{0, 0, 40, 40}

	_, cover := texture_fit_rects(src, container, .COVER, {})
	testing.expect(t, cover.w >= container.w - 0.01 || cover.h >= container.h - 0.01)

	_, none := texture_fit_rects(src, container, .NONE, {})
	expect_close(t, none.w, 40)
	expect_close(t, none.h, 40)

	_, fill := texture_fit_rects(src, container, .FILL, {})
	expect_close(t, fill.w, 100)
	expect_close(t, fill.h, 50)
}

@(test)
layout_space_bounds_for_screen_uses_logical_dpi :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		_ = layout
		state.dpi.logical_w = 320
		state.dpi.logical_h = 240
		bounds := layout_space_bounds(.SCREEN)
		expect_rect(t, bounds, {0, 0, 320, 240})
	})
}

// --- pure helpers ---

@(test)
layout_direction_info_covers_all_directions :: proc(t: ^testing.T) {
	h := layout_direction_info(.HORIZONTAL)
	testing.expect(t, h.is_horizontal)
	testing.expect(t, !h.is_wrap)
	testing.expect(t, !h.is_main_reverse)
	testing.expect(t, !h.is_cross_reverse)

	v := layout_direction_info(.VERTICAL)
	testing.expect(t, !v.is_horizontal)
	testing.expect(t, !v.is_wrap)

	hw := layout_direction_info(.HORIZONTAL_WRAP)
	testing.expect(t, hw.is_horizontal && hw.is_wrap)

	vw := layout_direction_info(.VERTICAL_WRAP)
	testing.expect(t, !vw.is_horizontal && vw.is_wrap)

	hr := layout_direction_info(.HORIZONTAL_REVERSE)
	testing.expect(t, hr.is_horizontal && hr.is_main_reverse && !hr.is_wrap)

	vr := layout_direction_info(.VERTICAL_REVERSE)
	testing.expect(t, !vr.is_horizontal && vr.is_main_reverse)

	hwr := layout_direction_info(.HORIZONTAL_WRAP_REVERSE)
	testing.expect(
		t,
		hwr.is_horizontal && hwr.is_wrap && hwr.is_main_reverse && hwr.is_cross_reverse,
	)

	vwr := layout_direction_info(.VERTICAL_WRAP_REVERSE)
	testing.expect(
		t,
		!vwr.is_horizontal && vwr.is_wrap && vwr.is_main_reverse && vwr.is_cross_reverse,
	)

	testing.expect(t, layout_direction_is_horizontal(.HORIZONTAL))
	testing.expect(t, !layout_direction_is_horizontal(.VERTICAL))
	testing.expect(t, layout_direction_is_wrap(.HORIZONTAL_WRAP))
	testing.expect(t, !layout_direction_is_wrap(.VERTICAL))
}

@(test)
layout_mirror_in_available_flips_within_bounds :: proc(t: ^testing.T) {
	expect_close(t, layout_mirror_in_available(0, 40, 200), 160)
	expect_close(t, layout_mirror_in_available(40, 40, 200), 120)
	expect_close(t, layout_mirror_in_available(0, 200, 200), 0)
}

@(test)
layout_clamp_axis_respects_min_and_max :: proc(t: ^testing.T) {
	expect_close(t, layout_clamp_axis(50, 0, 0), 50)
	expect_close(t, layout_clamp_axis(50, 80, 0), 80)
	expect_close(t, layout_clamp_axis(50, 0, 40), 40)
	expect_close(t, layout_clamp_axis(50, 20, 80), 50)
	expect_close(t, layout_clamp_axis(10, 20, 80), 20)
	expect_close(t, layout_clamp_axis(100, 20, 80), 80)
}

@(test)
layout_content_and_inner_rect_subtract_insets :: proc(t: ^testing.T) {
	outer := Rect{10, 20, 200, 100}
	content := layout_content_rect(outer, {t = 4, b = 6, l = 8, r = 12})
	expect_rect(t, content, {18, 24, 180, 90})

	inner := layout_inner_rect(outer, {t = 1, b = 2, l = 3, r = 4}, {t = 4, b = 6, l = 8, r = 12})
	expect_rect(t, inner, {21, 25, 173, 87})

	clamped := layout_content_rect({0, 0, 10, 10}, {t = 8, b = 8, l = 8, r = 8})
	expect_rect(t, clamped, {8, 8, 0, 0})
}

@(test)
layout_gap_main_and_cross_follow_axis :: proc(t: ^testing.T) {
	config := Resolved_Widget_Style {
		gap_x = 7,
		gap_y = 11,
	}
	expect_close(t, layout_config_gap_main(config, true), 7)
	expect_close(t, layout_config_gap_cross(config, true), 11)
	expect_close(t, layout_config_gap_main(config, false), 11)
	expect_close(t, layout_config_gap_cross(config, false), 7)
}

@(test)
layout_merge_justify_prefers_self_overrides :: proc(t: ^testing.T) {
	parent := Justify_Pos {
		x = .START,
		y = .CENTER,
	}
	self := Justify_Pos {
		x = .END,
	}
	merged := layout_merge_justify(parent, self)
	x, x_ok := resolve_justify_x(merged.x)
	y, y_ok := resolve_justify_y(merged.y)
	testing.expect(t, x_ok)
	testing.expect(t, y_ok)
	testing.expect(t, x.(Justify_Align) == .END)
	testing.expect(t, y.(Justify_Align) == .CENTER)
}

@(test)
layout_space_leading_and_between_match_modes :: proc(t: ^testing.T) {
	expect_close(t, layout_space_leading(.SPACE_BETWEEN, 60, 3), 0)
	expect_close(t, layout_space_leading(.SPACE_AROUND, 60, 3), 10)
	expect_close(t, layout_space_leading(.SPACE_EVENLY, 60, 3), 15)
	expect_close(t, layout_space_leading(.START, 60, 3), 0)
	expect_close(t, layout_space_leading(.SPACE_BETWEEN, 60, 0), 0)

	expect_close(t, layout_space_between_items(.SPACE_BETWEEN, 60, 3), 30)
	expect_close(t, layout_space_between_items(.SPACE_AROUND, 60, 3), 20)
	expect_close(t, layout_space_between_items(.SPACE_EVENLY, 60, 3), 15)
	expect_close(t, layout_space_between_items(.SPACE_BETWEEN, 60, 1), 0)
}

@(test)
layout_space_positions_distribute_free_space :: proc(t: ^testing.T) {
	sizes := []f32{40, 40, 40}

	between := layout_space_positions(.SPACE_BETWEEN, 200, sizes, 10)
	defer delete(between)
	testing.expect_value(t, len(between), 3)
	expect_close(t, between[0], 0)
	expect_close(t, between[1], 80)
	expect_close(t, between[2], 160)

	around := layout_space_positions(.SPACE_AROUND, 200, sizes, 0)
	defer delete(around)
	expect_close(t, around[0], 80.0 / 6.0)
	expect_close(t, around[1], 80)
	expect_close(t, around[2], 80 + 40 + 80.0 / 3.0)

	evenly := layout_space_positions(.SPACE_EVENLY, 200, sizes, 0)
	defer delete(evenly)
	expect_close(t, evenly[0], 20)
	expect_close(t, evenly[1], 80)
	expect_close(t, evenly[2], 140)

	empty := layout_space_positions(.SPACE_BETWEEN, 200, {}, 0)
	defer delete(empty)
	testing.expect_value(t, len(empty), 0)
}

@(test)
layout_content_align_target_and_extrema :: proc(t: ^testing.T) {
	max_t, max_ok := layout_content_align_target(.MAX_CONTENT, 90, 30)
	testing.expect(t, max_ok)
	expect_close(t, max_t, 90)

	min_t, min_ok := layout_content_align_target(.MIN_CONTENT, 90, 30)
	testing.expect(t, min_ok)
	expect_close(t, min_t, 30)

	_, start_ok := layout_content_align_target(.START, 90, 30)
	testing.expect(t, !start_ok)

	max_v, min_v, ok := layout_sibling_axis_extrema({10, 40, 25})
	testing.expect(t, ok)
	expect_close(t, max_v, 40)
	expect_close(t, min_v, 10)

	_, _, empty_ok := layout_sibling_axis_extrema({})
	testing.expect(t, !empty_ok)

	expect_close(t, layout_apply_content_align_axis(.MAX_CONTENT, 10, 40, 5), 40)
	expect_close(t, layout_apply_content_align_axis(.START, 10, 40, 5), 10)
}

@(test)
layout_main_and_cross_justify_align_follow_axis :: proc(t: ^testing.T) {
	pos := Justify_Pos {
		x = .CENTER,
		y = .END,
	}
	main_h, main_h_ok := layout_main_justify_align(pos, true)
	cross_h, cross_h_ok := layout_cross_justify_align(pos, true)
	testing.expect(t, main_h_ok && cross_h_ok)
	testing.expect(t, main_h == .CENTER)
	testing.expect(t, cross_h == .END)

	main_v, main_v_ok := layout_main_justify_align(pos, false)
	cross_v, cross_v_ok := layout_cross_justify_align(pos, false)
	testing.expect(t, main_v_ok && cross_v_ok)
	testing.expect(t, main_v == .END)
	testing.expect(t, cross_v == .CENTER)
}

@(test)
layout_wrap_helpers_read_axes_and_build_lines :: proc(t: ^testing.T) {
	expect_close(t, layout_wrap_child_main({40, 20}, true), 40)
	expect_close(t, layout_wrap_child_cross({40, 20}, true), 20)
	expect_close(t, layout_wrap_child_main({40, 20}, false), 20)
	expect_close(t, layout_wrap_child_cross({40, 20}, false), 40)

	sizes := []Vec2{{40, 10}, {40, 12}, {40, 8}}
	lines := layout_wrap_build_lines(sizes, true, 10, 100)
	defer delete(lines)
	testing.expect_value(t, len(lines), 2)
	testing.expect_value(t, lines[0].count, 2)
	testing.expect_value(t, lines[1].count, 1)
	expect_close(t, lines[0].main_sum, 90)
	expect_close(t, lines[0].cross_max, 12)
	expect_close(t, lines[1].main_sum, 40)

	no_limit := layout_wrap_build_lines(sizes, true, 10, 0)
	defer delete(no_limit)
	testing.expect_value(t, len(no_limit), 1)
	testing.expect_value(t, no_limit[0].count, 3)

	empty := layout_wrap_build_lines({}, true, 10, 100)
	defer delete(empty)
	testing.expect_value(t, len(empty), 0)
}

@(test)
layout_wrap_main_limit_subtracts_insets :: proc(t: ^testing.T) {
	node := Layout_Node {
		config = {width = layout_len_fixed(200)},
		padding = {l = 10, r = 20},
		border = {l = 2, r = 3},
	}
	expect_close(t, layout_wrap_main_limit_from_config(&node, true), 165)

	max_only := Layout_Node {
		config = {max_w = 120},
		padding = {l = 10, r = 10},
	}
	expect_close(t, layout_wrap_main_limit_from_config(&max_only, true), 100)

	auto := Layout_Node{}
	expect_close(t, layout_wrap_main_limit_from_config(&auto, true), 0)
}

@(test)
layout_child_in_main_flow_skips_self_aligned_axis :: proc(t: ^testing.T) {
	in_flow := Layout_Node{}
	testing.expect(t, layout_child_in_main_flow(&in_flow, true))
	testing.expect(t, layout_child_in_main_flow(&in_flow, false))

	out_x := Layout_Node {
		config = {self = {x = .END}},
	}
	testing.expect(t, !layout_child_in_main_flow(&out_x, true))
	testing.expect(t, layout_child_in_main_flow(&out_x, false))

	out_y := Layout_Node {
		config = {self = {y = .CENTER}},
	}
	testing.expect(t, layout_child_in_main_flow(&out_y, true))
	testing.expect(t, !layout_child_in_main_flow(&out_y, false))
}

@(test)
layout_child_main_size_prefers_fixed_then_flex_then_desired :: proc(t: ^testing.T) {
	fixed := Layout_Node {
		config = {width = layout_len_fixed(55)},
		desired = {10, 10},
	}
	expect_close(t, layout_child_main_size(&fixed, true, 100, 200), 55)

	flexed := Layout_Node {
		config = {flex = 2},
		desired = {30, 10},
	}
	expect_close(t, layout_child_main_size(&flexed, true, 40, 200), 80)

	desired_only := Layout_Node {
		desired = {33, 10},
	}
	expect_close(t, layout_child_main_size(&desired_only, true, 40, 200), 33)
}

@(test)
layout_child_cross_size_stretches_when_requested :: proc(t: ^testing.T) {
	natural := Layout_Node {
		desired = {40, 20},
	}
	expect_close(t, layout_child_cross_size(&natural, true, 100, {}), 20)

	stretch := Layout_Node {
		desired = {40, 20},
	}
	expect_close(t, layout_child_cross_size(&stretch, true, 100, {y = .STRETCH}), 100)

	fixed_h := Layout_Node {
		config = {height = layout_len_fixed(35)},
		desired = {40, 20},
	}
	expect_close(t, layout_child_cross_size(&fixed_h, true, 100, {y = .STRETCH}), 35)

	flex_child := Layout_Node {
		config = {flex = 1},
		desired = {40, 20},
	}
	expect_close(t, layout_child_cross_size(&flex_child, true, 100, {}), 100)
}

@(test)
layout_resolve_node_size_uses_desired_bounds_and_clamps :: proc(t: ^testing.T) {
	desired := Layout_Node {
		desired = {80, 40},
	}
	size := layout_resolve_node_size(&desired, {0, 0, 200, 100})
	expect_close(t, size.x, 80)
	expect_close(t, size.y, 40)

	fill := Layout_Node{}
	filled := layout_resolve_node_size(&fill, {0, 0, 200, 100})
	expect_close(t, filled.x, 200)
	expect_close(t, filled.y, 100)

	percent := Layout_Node {
		config = {
			width = layout_len_percent(50),
			height = layout_len_fixed(30),
			min_w = 120,
			max_h = 20,
		},
	}
	clamped := layout_resolve_node_size(&percent, {0, 0, 200, 100})
	expect_close(t, clamped.x, 120)
	expect_close(t, clamped.y, 20)
}

@(test)
layout_node_kind_helpers_classify_table_parts :: proc(t: ^testing.T) {
	testing.expect(t, layout_node_is_table_cell(.TABLE_CELL))
	testing.expect(t, layout_node_is_table_cell(.TABLE_HEADING))
	testing.expect(t, !layout_node_is_table_cell(.RECT))

	testing.expect(t, layout_node_participates_in_table_collapse(.TABLE))
	testing.expect(t, layout_node_participates_in_table_collapse(.TABLE_ROW))
	testing.expect(t, !layout_node_participates_in_table_collapse(.BUTTON))
}

// --- flex ---

@(test)
layout_row_places_fixed_children_left_to_right :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		b := layout_test_append_node(layout, root, .RECT, {}, {50, 20})
		c := layout_test_append_node(layout, root, .RECT, {}, {30, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})

		expect_rect(t, layout.nodes[root].rect, {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {0, 0, 40, 20})
		expect_rect(t, layout.nodes[b].rect, {40, 0, 50, 20})
		expect_rect(t, layout.nodes[c].rect, {90, 0, 30, 20})
	})
}

@(test)
layout_column_places_fixed_children_top_to_bottom :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(layout, -1, .RECT, {}, {200, 200}, {direction = .VERTICAL})
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 30})

		layout_solve(&layout.nodes[root], {0, 0, 200, 200})

		expect_rect(t, layout.nodes[a].rect, {0, 0, 40, 20})
		expect_rect(t, layout.nodes[b].rect, {0, 20, 40, 30})
	})
}

@(test)
layout_row_gap_inserts_space_between_children :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{200, 100},
			{direction = .HORIZONTAL, gap_x = 10},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		c := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})

		expect_rect(t, layout.nodes[a].rect, {0, 0, 40, 20})
		expect_rect(t, layout.nodes[b].rect, {50, 0, 40, 20})
		expect_rect(t, layout.nodes[c].rect, {100, 0, 40, 20})
	})
}

@(test)
layout_column_gap_inserts_space_between_children :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{100, 200},
			{direction = .VERTICAL, gap_y = 8},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 100, 200})

		expect_rect(t, layout.nodes[a].rect, {0, 0, 40, 20})
		expect_rect(t, layout.nodes[b].rect, {0, 28, 40, 20})
	})
}

@(test)
layout_single_child_ignores_gap :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{200, 100},
			{direction = .HORIZONTAL, gap_x = 50},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {0, 0, 40, 20})
	})
}

@(test)
layout_padding_and_border_shrink_content_and_offset_children :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		layout_test_set_insets(
			layout,
			root,
			{t = 5, b = 5, l = 10, r = 10},
			{t = 1, b = 1, l = 2, r = 2},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})

		inner := layout_inner_rect(
			layout.nodes[root].rect,
			layout.nodes[root].border,
			layout.nodes[root].padding,
		)
		expect_rect(t, inner, {12, 6, 176, 88})
		expect_rect(t, layout.nodes[a].rect, {12, 6, 40, 20})
		expect_rect_inside(t, inner, layout.nodes[a].rect)
	})
}

@(test)
layout_row_justify_center_and_end_on_main_axis :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{x = .CENTER},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {60, 0, 40, 20})
		expect_rect(t, layout.nodes[b].rect, {100, 0, 40, 20})
	})

	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{x = .END},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {120, 0, 40, 20})
		expect_rect(t, layout.nodes[b].rect, {160, 0, 40, 20})
	})
}

@(test)
layout_row_justify_cross_axis_center_and_end :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{y = .CENTER},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {0, 40, 40, 20})
	})

	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{y = .END},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {0, 80, 40, 20})
	})
}

@(test)
layout_row_stretch_expands_cross_axis :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{y = .STRETCH},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {0, 0, 40, 100})
	})
}

@(test)
layout_row_space_between_around_and_evenly :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{x = .SPACE_BETWEEN},
			{200, 100},
			{direction = .HORIZONTAL, gap_x = 10},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		c := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {0, 0, 40, 20})
		expect_rect(t, layout.nodes[b].rect, {80, 0, 40, 20})
		expect_rect(t, layout.nodes[c].rect, {160, 0, 40, 20})
	})

	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{x = .SPACE_AROUND},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		c := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {80.0 / 6.0, 0, 40, 20})
		expect_rect(t, layout.nodes[b].rect, {80, 0, 40, 20})
		expect_rect(t, layout.nodes[c].rect, {80 + 40 + 80.0 / 3.0, 0, 40, 20})
	})

	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{x = .SPACE_EVENLY},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		c := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {20, 0, 40, 20})
		expect_rect(t, layout.nodes[b].rect, {80, 0, 40, 20})
		expect_rect(t, layout.nodes[c].rect, {140, 0, 40, 20})
	})
}

@(test)
layout_flex_shares_remaining_main_space_by_weight :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {20, 20}, {flex = 1})
		b := layout_test_append_node(layout, root, .RECT, {}, {20, 20}, {flex = 3})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {0, 0, 50, 100})
		expect_rect(t, layout.nodes[b].rect, {50, 0, 150, 100})
	})
}

@(test)
layout_flex_with_fixed_sibling_takes_leftover :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{200, 100},
			{direction = .HORIZONTAL, gap_x = 10},
		)
		fixed := layout_test_append_node(
			layout,
			root,
			.RECT,
			{},
			{40, 20},
			{width = layout_len_fixed(50)},
		)
		flexed := layout_test_append_node(layout, root, .RECT, {}, {10, 20}, {flex = 1})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[fixed].rect, {0, 0, 50, 20})
		expect_rect(t, layout.nodes[flexed].rect, {60, 0, 140, 100})
	})
}

@(test)
layout_flex_does_not_shrink_below_desired_when_unit_smaller :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			root := layout_test_append_node(
				layout,
				-1,
				.RECT,
				{},
				{100, 50},
				{direction = .HORIZONTAL},
			)
			a := layout_test_append_node(layout, root, .RECT, {}, {80, 20}, {flex = 1})
			b := layout_test_append_node(layout, root, .RECT, {}, {80, 20}, {flex = 1})

			layout_solve(&layout.nodes[root], {0, 0, 100, 50})
			// flex_unit = 50, max(desired, unit) keeps 80
			expect_close(t, layout.nodes[a].rect.w, 80)
			expect_close(t, layout.nodes[b].rect.w, 80)
		},
	)
}

@(test)
layout_flex_ignored_when_main_axis_is_definite :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		a := layout_test_append_node(
			layout,
			root,
			.RECT,
			{},
			{10, 20},
			{flex = 1, width = layout_len_fixed(60)},
		)
		b := layout_test_append_node(layout, root, .RECT, {}, {10, 20}, {flex = 1})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {0, 0, 60, 100})
		expect_rect(t, layout.nodes[b].rect, {60, 0, 140, 100})
	})
}

@(test)
layout_percent_child_width_resolves_against_content :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		a := layout_test_append_node(
			layout,
			root,
			.RECT,
			{},
			{10, 20},
			{width = layout_len_percent(50)},
		)

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {0, 0, 100, 20})
	})
}

@(test)
layout_min_max_clamp_on_root_and_children :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{50, 50},
			{direction = .HORIZONTAL, min_w = 120, max_h = 40},
		)

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_close(t, layout.nodes[root].rect.w, 120)
		expect_close(t, layout.nodes[root].rect.h, 40)
	})
}

@(test)
layout_child_xy_offsets_apply_after_alignment :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20}, {x = 5, y = 7})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {5, 7, 40, 20})
	})
}

@(test)
layout_self_alignment_overrides_parent_cross_axis :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{y = .START},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20}, {self = {y = .END}})
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {0, 80, 40, 20})
		expect_rect(t, layout.nodes[b].rect, {40, 0, 40, 20})
	})
}

@(test)
layout_self_main_axis_removes_child_from_flow :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{200, 100},
			{direction = .HORIZONTAL, gap_x = 10},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		overlay := layout_test_append_node(layout, root, .RECT, {}, {30, 20}, {self = {x = .END}})
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {0, 0, 40, 20})
		expect_rect(t, layout.nodes[b].rect, {50, 0, 40, 20})
		expect_rect(t, layout.nodes[overlay].rect, {170, 0, 30, 20})
	})
}

@(test)
layout_horizontal_reverse_mirrors_main_positions :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{200, 100},
			{direction = .HORIZONTAL_REVERSE},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		b := layout_test_append_node(layout, root, .RECT, {}, {50, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {160, 0, 40, 20})
		expect_rect(t, layout.nodes[b].rect, {110, 0, 50, 20})
	})
}

@(test)
layout_vertical_reverse_mirrors_main_positions :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{100, 200},
			{direction = .VERTICAL_REVERSE},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 30})

		layout_solve(&layout.nodes[root], {0, 0, 100, 200})
		expect_rect(t, layout.nodes[a].rect, {0, 180, 40, 20})
		expect_rect(t, layout.nodes[b].rect, {0, 150, 40, 30})
	})
}

@(test)
layout_nested_row_inside_column_positions_relative_to_parent :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{200, 200},
			{direction = .VERTICAL, gap_y = 10},
		)
		top := layout_test_append_node(layout, root, .RECT, {}, {200, 40})
		row := layout_test_append_node(
			layout,
			root,
			.RECT,
			{},
			{200, 60},
			{direction = .HORIZONTAL, gap_x = 5},
		)
		a := layout_test_append_node(layout, row, .RECT, {}, {30, 20})
		b := layout_test_append_node(layout, row, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 200})

		expect_rect(t, layout.nodes[top].rect, {0, 0, 200, 40})
		expect_rect(t, layout.nodes[row].rect, {0, 50, 200, 60})
		expect_rect(t, layout.nodes[a].rect, {0, 50, 30, 20})
		expect_rect(t, layout.nodes[b].rect, {35, 50, 40, 20})
		expect_rect_inside(t, layout.nodes[row].rect, layout.nodes[a].rect)
		expect_rect_inside(t, layout.nodes[row].rect, layout.nodes[b].rect)
	})
}

@(test)
layout_empty_container_fills_bounds :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(layout, -1, .RECT, {}, {}, {direction = .HORIZONTAL})
		layout_solve(&layout.nodes[root], {10, 20, 200, 100})
		expect_rect(t, layout.nodes[root].rect, {10, 20, 200, 100})
	})
}

@(test)
layout_max_content_equalizes_cross_sizes_among_siblings :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{y = .MAX_CONTENT},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 50})
		c := layout_test_append_node(layout, root, .RECT, {}, {40, 30})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_close(t, layout.nodes[a].rect.h, 50)
		expect_close(t, layout.nodes[b].rect.h, 50)
		expect_close(t, layout.nodes[c].rect.h, 50)
	})
}

@(test)
layout_min_content_equalizes_cross_sizes_among_siblings :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{y = .MIN_CONTENT},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 50})
		c := layout_test_append_node(layout, root, .RECT, {}, {40, 30})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_close(t, layout.nodes[a].rect.h, 20)
		expect_close(t, layout.nodes[b].rect.h, 20)
		expect_close(t, layout.nodes[c].rect.h, 20)
	})
}

@(test)
layout_measure_row_sums_main_and_max_cross_with_gap_and_insets :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{},
			{direction = .HORIZONTAL, gap_x = 10},
		)
		layout_test_set_insets(layout, root, {t = 2, b = 3, l = 4, r = 5}, {})
		_ = layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		_ = layout_test_append_node(layout, root, .RECT, {}, {50, 30})

		size := layout_measure(&layout.nodes[root])
		expect_close(t, size.x, 40 + 50 + 10 + 4 + 5)
		expect_close(t, size.y, 30 + 2 + 3)
	})
}

@(test)
layout_measure_skips_flex_children_without_definite_main :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{},
			{direction = .HORIZONTAL, gap_x = 10},
		)
		_ = layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		_ = layout_test_append_node(layout, root, .RECT, {}, {80, 20}, {flex = 1})

		size := layout_measure(&layout.nodes[root])
		expect_close(t, size.x, 40 + 10)
		expect_close(t, size.y, 20)
	})
}

@(test)
layout_column_justify_center_on_main_axis :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{y = .CENTER},
			{100, 200},
			{direction = .VERTICAL},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 100, 200})
		expect_rect(t, layout.nodes[a].rect, {0, 80, 40, 20})
		expect_rect(t, layout.nodes[b].rect, {0, 100, 40, 20})
	})
}

@(test)
layout_column_stretch_expands_cross_axis :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{x = .STRETCH},
			{200, 100},
			{direction = .VERTICAL},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_rect(t, layout.nodes[a].rect, {0, 0, 200, 20})
	})
}

@(test)
layout_root_xy_offsets_shift_solved_rect :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{100, 50},
			{direction = .HORIZONTAL, x = 15, y = 25},
		)
		layout_solve(&layout.nodes[root], {10, 20, 200, 100})
		expect_rect(t, layout.nodes[root].rect, {25, 45, 100, 50})
	})
}

@(test)
layout_max_content_keeps_definite_cross_size :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{y = .MAX_CONTENT},
			{200, 100},
			{direction = .HORIZONTAL},
		)
		a := layout_test_append_node(
			layout,
			root,
			.RECT,
			{},
			{40, 20},
			{height = layout_len_fixed(25)},
		)
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 50})

		layout_solve(&layout.nodes[root], {0, 0, 200, 100})
		expect_close(t, layout.nodes[a].rect.h, 25)
		expect_close(t, layout.nodes[b].rect.h, 50)
	})
}

@(test)
layout_begin_and_end_space_solves_roots_in_bounds :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		state.dpi.logical_w = 300
		state.dpi.logical_h = 200

		layout_begin_space(.SCREEN)
		root := layout_test_append_node(layout, -1, .RECT, {}, {40, 20}, {direction = .HORIZONTAL})
		child := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		layout_end_space()

		expect_rect(t, layout.nodes[root].rect, {0, 0, 40, 20})
		expect_rect(t, layout.nodes[child].rect, {0, 0, 40, 20})
		testing.expect_value(t, len(layout.bounds_stack), 0)
		testing.expect_value(t, len(layout.space_markers), 0)
	})
}

@(test)
layout_zero_remaining_flex_keeps_desired_main_size :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			root := layout_test_append_node(
				layout,
				-1,
				.RECT,
				{},
				{100, 50},
				{direction = .HORIZONTAL},
			)
			fixed := layout_test_append_node(
				layout,
				root,
				.RECT,
				{},
				{100, 20},
				{width = layout_len_fixed(100)},
			)
			flexed := layout_test_append_node(layout, root, .RECT, {}, {30, 20}, {flex = 1})

			layout_solve(&layout.nodes[root], {0, 0, 100, 50})
			expect_rect(t, layout.nodes[fixed].rect, {0, 0, 100, 20})
			// remaining = 0 => flex_unit = 0 => desired main size
			expect_rect(t, layout.nodes[flexed].rect, {100, 0, 30, 50})
		},
	)
}

// --- wrap ---

@(test)
layout_horizontal_wrap_breaks_to_new_line_when_main_exceeds :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			root := layout_test_append_node(
				layout,
				-1,
				.RECT,
				{},
				{100, 20},
				{
					direction = .HORIZONTAL_WRAP,
					width = layout_len_fixed(100),
					gap_x = 10,
					gap_y = 5,
				},
			)
			a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
			b := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
			c := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

			layout_solve(&layout.nodes[root], {0, 0, 100, 20})

			expect_rect(t, layout.nodes[a].rect, {0, 0, 40, 20})
			expect_rect(t, layout.nodes[b].rect, {50, 0, 40, 20})
			expect_rect(t, layout.nodes[c].rect, {0, 25, 40, 20})
			// auto cross size expands parent to fit wrapped lines
			expect_close(t, layout.nodes[root].rect.h, 45)
		},
	)
}

@(test)
layout_vertical_wrap_breaks_when_main_exceeds :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{20, 100},
			{direction = .VERTICAL_WRAP, height = layout_len_fixed(100), gap_x = 5, gap_y = 10},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {20, 40})
		b := layout_test_append_node(layout, root, .RECT, {}, {20, 40})
		c := layout_test_append_node(layout, root, .RECT, {}, {20, 40})

		layout_solve(&layout.nodes[root], {0, 0, 20, 100})

		expect_rect(t, layout.nodes[a].rect, {0, 0, 20, 40})
		expect_rect(t, layout.nodes[b].rect, {0, 50, 20, 40})
		expect_rect(t, layout.nodes[c].rect, {25, 0, 20, 40})
		expect_close(t, layout.nodes[root].rect.w, 45)
	})
}

@(test)
layout_horizontal_wrap_reverse_mirrors_main_and_cross :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			root := layout_test_append_node(
				layout,
				-1,
				.RECT,
				{},
				{100, 100},
				{
					direction = .HORIZONTAL_WRAP_REVERSE,
					width = layout_len_fixed(100),
					height = layout_len_fixed(100),
					gap_x = 10,
					gap_y = 5,
				},
			)
			a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
			b := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
			c := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

			layout_solve(&layout.nodes[root], {0, 0, 100, 100})

			// Line 0 at cross_start mirrored; main positions mirrored within 100.
			expect_close(t, layout.nodes[a].rect.w, 40)
			expect_close(t, layout.nodes[b].rect.w, 40)
			expect_close(t, layout.nodes[c].rect.w, 40)

			testing.expect(t, layout.nodes[a].rect.x > layout.nodes[b].rect.x)
			testing.expect(t, layout.nodes[c].rect.y != layout.nodes[a].rect.y)
			expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[a].rect)
			expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[b].rect)
			expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[c].rect)
		},
	)
}

@(test)
layout_wrap_with_no_overflow_stays_on_one_line :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{200, 40},
			{direction = .HORIZONTAL_WRAP, width = layout_len_fixed(200), gap_x = 10},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 40})
		expect_rect(t, layout.nodes[a].rect, {0, 0, 40, 20})
		expect_rect(t, layout.nodes[b].rect, {50, 0, 40, 20})
		expect_close(t, layout.nodes[a].rect.y, layout.nodes[b].rect.y)
	})
}

@(test)
layout_wrap_flex_distributes_within_line :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{200, 40},
			{direction = .HORIZONTAL_WRAP, width = layout_len_fixed(200)},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {20, 20}, {flex = 1})
		b := layout_test_append_node(layout, root, .RECT, {}, {20, 20}, {flex = 1})

		layout_solve(&layout.nodes[root], {0, 0, 200, 40})
		expect_rect(t, layout.nodes[a].rect, {0, 0, 100, 20})
		expect_rect(t, layout.nodes[b].rect, {100, 0, 100, 20})
	})
}

@(test)
layout_wrap_measure_accounts_for_lines_and_cross_gap :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{},
			{direction = .HORIZONTAL_WRAP, width = layout_len_fixed(100), gap_x = 10, gap_y = 5},
		)
		_ = layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		_ = layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		_ = layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		size := layout_measure(&layout.nodes[root])
		expect_close(t, size.x, 100)
		expect_close(t, size.y, 20 + 5 + 20)
	})
}

@(test)
layout_wrap_definite_cross_size_is_not_auto_expanded :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{100, 30},
			{
				direction = .HORIZONTAL_WRAP,
				width = layout_len_fixed(100),
				height = layout_len_fixed(30),
				gap_y = 5,
			},
		)
		_ = layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		_ = layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		_ = layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 100, 30})
		expect_close(t, layout.nodes[root].rect.h, 30)
	})
}

@(test)
layout_wrap_justify_center_on_cross_axis_offsets_lines :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			root := layout_test_append_node(
				layout,
				-1,
				.RECT,
				{y = .CENTER},
				{100, 100},
				{
					direction = .HORIZONTAL_WRAP,
					width = layout_len_fixed(100),
					height = layout_len_fixed(100),
					gap_y = 5,
				},
			)
			a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
			b := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
			c := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

			layout_solve(&layout.nodes[root], {0, 0, 100, 100})

			// two lines: 20 + 5 + 20 = 45, centered in 100 => start 27.5
			expect_close(t, layout.nodes[a].rect.y, 27.5)
			expect_close(t, layout.nodes[b].rect.y, 27.5)
			expect_close(t, layout.nodes[c].rect.y, 52.5)
		},
	)
}

@(test)
layout_vertical_wrap_reverse_keeps_children_inside_parent :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{},
			{100, 100},
			{
				direction = .VERTICAL_WRAP_REVERSE,
				width = layout_len_fixed(100),
				height = layout_len_fixed(100),
				gap_x = 5,
				gap_y = 10,
			},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {20, 40})
		b := layout_test_append_node(layout, root, .RECT, {}, {20, 40})
		c := layout_test_append_node(layout, root, .RECT, {}, {20, 40})

		layout_solve(&layout.nodes[root], {0, 0, 100, 100})
		expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[a].rect)
		expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[b].rect)
		expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[c].rect)
		testing.expect(t, layout.nodes[a].rect.y > layout.nodes[b].rect.y)
	})
}

@(test)
layout_wrap_main_justify_end_offsets_line_items :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{x = .END},
			{200, 40},
			{direction = .HORIZONTAL_WRAP, width = layout_len_fixed(200)},
		)
		a := layout_test_append_node(layout, root, .RECT, {}, {40, 20})
		b := layout_test_append_node(layout, root, .RECT, {}, {40, 20})

		layout_solve(&layout.nodes[root], {0, 0, 200, 40})
		expect_rect(t, layout.nodes[a].rect, {120, 0, 40, 20})
		expect_rect(t, layout.nodes[b].rect, {160, 0, 40, 20})
	})
}
