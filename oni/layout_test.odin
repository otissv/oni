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
	b := Table_Border_Side{width = 1, source = .ROW, order = 0}
	testing.expect(t, table_border_compare(a, b) > 0)
}

@(test)
table_border_compare_prefers_cell_source_on_equal_width :: proc(t: ^testing.T) {
	a := Table_Border_Side{width = 1, source = .CELL, order = 0}
	b := Table_Border_Side{width = 1, source = .ROW, order = 1}
	testing.expect(t, table_border_compare(a, b) > 0)
}

@(test)
table_border_compare_prefers_table_only_when_thicker :: proc(t: ^testing.T) {
	table := Table_Border_Side{width = 2, source = .TABLE, order = 0}
	cell := Table_Border_Side{width = 1, source = .CELL, order = 1}
	testing.expect(t, table_border_compare(table, cell) > 0)

	equal_table := Table_Border_Side{width = 1, source = .TABLE, order = 0}
	equal_cell := Table_Border_Side{width = 1, source = .CELL, order = 1}
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

	table := layout_test_append_node(
		&layout,
		-1,
		.TABLE,
		{},
		{},
		{gap_x = 0, gap_y = 0},
	)
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
				palette = palette,
				border = 0,
				border_color = .BLACK,
				background = .TRANSPARENT,
				gap_x = u16(0),
				gap_y = u16(0),
			}
			defer free(theme)

			layout_reset()
			ui_push_style(style_root(.SCREEN, Rect{0, 0, 400, 300}))
			defer ui_pop_style()

			empty: Widget_Frame_State
			event := Widget_Event(Widget_Frame_State){frame_state = empty}

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
					justify = {mode = .Value, value = Justify_Pos{x = .TABLE_CELL, y = .TABLE_CELL}},
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
	with_test_global_state(
		&test_state,
		proc(test_state: ^State, t: ^testing.T) {
			_ = test_state
			ui_init()
			defer ui_shutdown()

			layout_id := UI_Id(42)
			_ = widget_lifecycle_entry(layout_id)

			register_tabbable("tab-target")
			register_static_id("widget", "runtime-key")
			consume_hover_transition("runtime-key", true)
			consume_pointer_click("runtime-key", true, true, false)
		},
		t,
	)
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
	test_state: State

	with_test_global_state(
		&test_state,
		proc(test_state: ^State, t: ^testing.T) {
			test_theme := Theme {
				palette = palette,
				justify = Justify_Pos{x = .START, y = .START},
				direction = .HORIZONTAL,
				border_color = .BLACK,
				background = .BACKGROUND,
				padding = 0,
				radius = 0,
				border = 0,
				width = 0,
				height = 0,
			}
			theme = &test_theme
			ui_push_style(style_root(.SCREEN, Rect{0, 0, 200, 200}))
			defer clear(&test_state.ui.style_stack)

			frame: Widget_Frame_State
			event := Widget_Event(Widget_Frame_State) {
				frame_state = frame,
			}

			parent := resolve_widget_config(
				{},
				{radius = {mode = .Value, value = f32(10)}},
				&frame,
				event,
			)
			ui_push_style(style_child_context(parent))

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
				{
					radius = {
						mode = .Value,
						value = Radius_corners{tl = .INHERIT, tr = .INHERIT},
					},
				},
				&frame,
				event,
			)
			pc, pok := resolve_radius_value(partial.radius)
			testing.expect(t, pok)
			expect_close(t, pc.tl, 10)
			expect_close(t, pc.tr, 10)
			expect_close(t, pc.bl, 0)
			expect_close(t, pc.br, 0)
		},
		t,
	)
}

@(test)
table_descendant_outer_radius_matches_shared_corners :: proc(t: ^testing.T) {
	test_state: State

	with_test_global_state(
		&test_state,
		proc(test_state: ^State, t: ^testing.T) {
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
		},
		t,
	)
}

@(test)
border_px_to_bd_roundtrip_resolves :: proc(t: ^testing.T) {
	px := Bd_px{t = 1, b = 1, l = 1, r = 1}
	bd := border_px_to_bd(px)
	resolved, ok := resolve_border_value(bd)
	testing.expect(t, ok)
	expect_close(t, resolved.l, 1)
	expect_close(t, resolved.r, 1)

	side := table_border_side_from_node(
		&Layout_Node{config = {border = bd}},
		'l',
		.CELL,
		0,
		{},
	)
	expect_close(t, side.width, 1)
}
