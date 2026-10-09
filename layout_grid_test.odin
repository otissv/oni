package oni

import "core:testing"

@(test)
layout_grid_three_equal_columns :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		grid := layout_test_append_node(
			layout,
			-1,
			.GRID,
			{},
			{},
			{
				width = layout_len_fixed(300),
				height = layout_len_fixed(100),
				grid_template_columns = grid_template_columns_count(3),
				gap_x = 0,
				gap_y = 0,
			},
		)
		a := layout_test_append_node(layout, grid, .RECT, {}, {40, 40})
		b := layout_test_append_node(layout, grid, .RECT, {}, {40, 40})
		c := layout_test_append_node(layout, grid, .RECT, {}, {40, 40})

		root := &layout.nodes[grid]
		layout_solve(root, {0, 0, 300, 100})

		expect_close(t, layout.nodes[a].rect.x, 0)
		expect_close(t, layout.nodes[a].rect.w, 100)
		expect_close(t, layout.nodes[b].rect.x, 100)
		expect_close(t, layout.nodes[c].rect.x, 200)
	})
}

@(test)
layout_grid_col_span_two :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		grid := layout_test_append_node(
			layout,
			-1,
			.GRID,
			{},
			{},
			{
				width = layout_len_fixed(200),
				height = layout_len_fixed(80),
				grid_template_columns = grid_template_columns_count(2),
			},
		)
		wide := layout_test_append_node(
			layout,
			grid,
			.RECT,
			{},
			{40, 40},
			{grid_column_start = {line = 1}, grid_column_end = {line = 3}},
		)
		narrow := layout_test_append_node(layout, grid, .RECT, {}, {40, 40})

		root := &layout.nodes[grid]
		layout_solve(root, {0, 0, 200, 80})

		expect_close(t, layout.nodes[wide].rect.w, 200)
		expect_close(t, layout.nodes[narrow].rect.y, 40)
	})
}

@(test)
layout_grid_fr_tracks_fill_width :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		grid := layout_test_append_node(
			layout,
			-1,
			.GRID,
			{},
			{},
			{
				width = layout_len_fixed(100),
				height = layout_len_fixed(50),
				grid_template_columns = grid_template_columns_count(2),
			},
		)
		_ = layout_test_append_node(layout, grid, .RECT, {}, {10, 10})
		_ = layout_test_append_node(layout, grid, .RECT, {}, {10, 10})

		root := &layout.nodes[grid]
		layout_solve(root, {0, 0, 100, 50})
		child := &layout.nodes[layout.nodes[grid].child_indices[0]]
		expect_close(t, child.rect.w, 50)
	})
}
