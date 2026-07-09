package oni

import "core:sync"
import "core:testing"

expect_close :: proc(t: ^testing.T, got, want: f32, loc := #caller_location) {
	testing.expectf(t, abs(got - want) < 1e-4, "got=%v want=%v", got, want, loc = loc)
}

@(private)
test_global_state_guard: sync.Mutex

@(private)
with_test_global_state :: proc(test_state: ^State, body: proc(test_state: ^State, t: ^testing.T), t: ^testing.T) {
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
layout_test_begin :: proc() -> Layout_State {
	return Layout_State {
		table_tracks = make(map[int]Layout_Table_Tracks),
		table_border_collapse = make(map[UI_Id]Border_Collapse),
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

	append(
		&layout.nodes,
		Layout_Node {
			kind = kind,
			config = node_config,
			desired = desired,
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
layout_test_end :: proc(layout: ^Layout_State) {
	for _, tracks in layout.table_tracks {
		delete(tracks.rows)
		delete(tracks.col_widths)
		delete(tracks.row_heights)
		delete(tracks.cell_positions)
	}
	delete(layout.table_tracks)
	layout.table_tracks = nil
	delete(layout.table_border_collapse)
	layout.table_border_collapse = nil

	layout_release_node_children(layout)
	delete(layout.nodes)
	layout.nodes = nil
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

	size11 := layout_table_apply_cell_size(&layout.nodes[row1], &tracks, 0, 0, &layout.nodes[cell11], {})
	size12 := layout_table_apply_cell_size(&layout.nodes[row1], &tracks, 0, 1, &layout.nodes[cell12], {})
	size21 := layout_table_apply_cell_size(&layout.nodes[row2], &tracks, row2_track, 0, &layout.nodes[cell21], {})
	size22 := layout_table_apply_cell_size(&layout.nodes[row2], &tracks, row2_track, 1, &layout.nodes[cell22], {})

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
	layout.nodes[cell1].config.width = {kind = .FIXED, value = 70}
	layout.nodes[cell1].config.height = {kind = .FIXED, value = 30}

	layout_table_prepare_in(&layout, table)

	tracks, ok := layout.table_tracks[table]
	testing.expect(t, ok)
	expect_close(t, tracks.col_widths[0], 70)
	expect_close(t, tracks.col_widths[1], 50)
	expect_close(t, tracks.row_heights[0], 40)

	size1 := layout_table_apply_cell_size(&layout.nodes[row], &tracks, 0, 0, &layout.nodes[cell1], {})
	size2 := layout_table_apply_cell_size(&layout.nodes[row], &tracks, 0, 1, &layout.nodes[cell2], {})

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
	size1 := layout_table_apply_cell_size(&layout.nodes[row], &tracks, 0, 0, &layout.nodes[cell1], {})
	size2 := layout_table_apply_cell_size(&layout.nodes[row], &tracks, 0, 1, &layout.nodes[cell2], {})

	expect_close(t, size1.x, 80)
	expect_close(t, size2.x, 120)
	expect_close(t, size1.y, 40)
	expect_close(t, size2.y, 40)
}

@(test)
layout_nested_table_solve_equalizes_heading_and_cell_widths :: proc(t: ^testing.T) {
	test_state: State
	with_test_global_state(
		&test_state,
		proc(test_state: ^State, t: ^testing.T) {
			defer layout_test_end(&test_state.ui.layout)

			test_state.ui.layout.table_tracks = make(map[int]Layout_Table_Tracks)

			layout := &test_state.ui.layout
			root := layout_test_append_node(layout, -1, .RECT, {}, {400, 300}, {direction = .VERTICAL})
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
		},
		t,
	)
}

@(test)
table_border_compare_prefers_thicker_width :: proc(t: ^testing.T) {
	a := Table_Border_Side{width = 2, source = .CELL, order = 1}
	b := Table_Border_Side{width = 1, source = .TABLE, order = 0}
	testing.expect(t, table_border_compare(a, b) > 0)
}

@(test)
table_border_compare_prefers_cell_source_on_equal_width :: proc(t: ^testing.T) {
	a := Table_Border_Side{width = 1, source = .CELL, order = 0}
	b := Table_Border_Side{width = 1, source = .ROW, order = 1}
	testing.expect(t, table_border_compare(a, b) > 0)
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
	layout.table_border_collapse[UI_Id(1)] = .COLLAPSE
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
	with_test_global_state(
		&test_state,
		proc(test_state: ^State, t: ^testing.T) {
			_ = test_state
			ui_init()
			defer ui_shutdown()

			layout_id := UI_Id(42)
			entry := widget_lifecycle_entry(layout_id)
			entry.shaped = new(Shaped_Text)
			entry.shaped.pool_slot = INVALID_SHAPE_POOL_SLOT

			register_tabbable("tab-target")
			register_static_id("widget", "runtime-key")
			consume_hover_transition("runtime-key", true)
			consume_pointer_click("runtime-key", true, true, false)
		},
		t,
	)
}
