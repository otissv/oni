package oni

import "core:slice"

@(private)
Layout_Grid_Item :: struct {
	child_index: int,
	c0, c1:      int,
	r0, r1:      int,
	explicit:    bool,
}

@(private)
layout_grid_flow_column_major :: proc(flow: Grid_Auto_Flow) -> bool {
	switch flow {
	case .COLUMN, .COLUMN_DENSE:
		return true
	case .ROW, .ROW_DENSE:
		return false
	}
	return false
}

@(private)
layout_grid_flow_dense :: proc(flow: Grid_Auto_Flow) -> bool {
	return flow == .ROW_DENSE || flow == .COLUMN_DENSE
}

@(private)
layout_grid_normalize_lines :: proc(
	c0, c1, r0, r1: int,
) -> (
	nc0, nc1, nr0, nr1: int,
	ok: bool,
) {
	if c0 <= 0 && c1 <= 0 && r0 <= 0 && r1 <= 0 do return 0, 0, 0, 0, false

	nc0, nc1, nr0, nr1 = c0, c1, r0, r1
	if nc0 > 0 && nc1 <= 0 do nc1 = nc0 + 1
	if nr0 > 0 && nr1 <= 0 do nr1 = nr0 + 1
	if nc0 <= 0 do nc0 = 1
	if nr0 <= 0 do nr0 = 1
	if nc1 <= nc0 do nc1 = nc0 + 1
	if nr1 <= nr0 do nr1 = nr0 + 1

	return nc0, nc1, nr0, nr1, true
}

@(private)
layout_grid_expand_tracks :: proc(
	explicit: Grid_Template_Tracks,
	needed: int,
	auto_track: Grid_Track_Size,
	allocator := context.temp_allocator,
) -> []Grid_Track_Size {
	track_count := needed
	if track_count <= 0 do track_count = 1
	count := max(explicit.count, track_count)
	if count > GRID_MAX_IMPLICIT_TRACKS do count = GRID_MAX_IMPLICIT_TRACKS

	tracks := make([]Grid_Track_Size, count, allocator)
	for i in 0 ..< explicit.count {
		tracks[i] = explicit.tracks[i]
	}
	for i in explicit.count ..< count {
		tracks[i] = auto_track
	}
	return tracks
}

@(private)
layout_grid_cell_occupied :: proc(
	occupied: []bool,
	cols: int,
	c0, c1, r0, r1: int,
) -> bool {
	if cols <= 0 do return true
	for r in r0 ..< r1 {
		for c in c0 ..< c1 {
			idx := (r - 1) * cols + (c - 1)
			if idx < 0 || idx >= len(occupied) do return true
			if occupied[idx] do return true
		}
	}
	return false
}

@(private)
layout_grid_mark_occupied :: proc(
	occupied: []bool,
	cols: int,
	c0, c1, r0, r1: int,
) {
	if cols <= 0 do return
	for r in r0 ..< r1 {
		for c in c0 ..< c1 {
			idx := (r - 1) * cols + (c - 1)
			if idx >= 0 && idx < len(occupied) {
				occupied[idx] = true
			}
		}
	}
}

@(private)
layout_grid_find_auto_slot :: proc(
	occupied: []bool,
	cols, rows: int,
	span_c, span_r: int,
	flow: Grid_Auto_Flow,
	dense: bool,
) -> (
	c0, r0: int,
	ok: bool,
) {
	width := span_c
	height := span_r
	if width <= 0 do width = 1
	if height <= 0 do height = 1
	track_cols := cols
	if track_cols <= 0 do track_cols = 1

	column_major := layout_grid_flow_column_major(flow)

	slot_fits :: proc(
		occupied: []bool,
		track_cols, rows: int,
		c0, r0, width, height: int,
	) -> bool {
		if c0 + width - 1 > track_cols do return false
		if r0 + height - 1 > rows do return false
		return !layout_grid_cell_occupied(occupied, track_cols, c0, c0 + width, r0, r0 + height)
	}

	if dense {
		max_r := rows + height
		max_c := track_cols + width
		for r in 1 ..= max_r {
			for c in 1 ..= max_c {
				if slot_fits(occupied, track_cols, rows, c, r, width, height) {
					return c, r, true
				}
			}
		}
		return 1, 1, true
	}

	c := 1
	r := 1
	for attempt in 0 ..< GRID_MAX_IMPLICIT_TRACKS * GRID_MAX_IMPLICIT_TRACKS {
		if slot_fits(occupied, track_cols, rows, c, r, width, height) {
			return c, r, true
		}
		if column_major {
			r += 1
			if r + height - 1 > rows {
				r = 1
				c += 1
			}
		} else {
			c += 1
			if c + width - 1 > track_cols {
				c = 1
				r += 1
			}
		}
		_ = attempt
	}

	return 1, 1, false
}

@(private)
layout_grid_collect_items :: proc(
	node: ^Layout_Node,
	areas: map[string]Grid_Area_Lines,
	allocator := context.temp_allocator,
) -> []Layout_Grid_Item {
	items := make([dynamic]Layout_Grid_Item, allocator)

	for child_index in node.child_indices {
		child := &state.ui.layout.nodes[child_index]
		if !layout_position_in_flex_flow(child.config.position) do continue

		placement, placement_ok := grid_item_placement(child.config, areas)
		if !placement_ok do continue

		c0, c1, r0, r1, norm_ok := layout_grid_normalize_lines(
			placement.c0,
			placement.c1,
			placement.r0,
			placement.r1,
		)

		explicit := placement.explicit && norm_ok
		if !explicit {
			c0, c1, r0, r1 = 0, 0, 0, 0
		}

		append(
			&items,
			Layout_Grid_Item {
				child_index = child_index,
				c0 = c0,
				c1 = c1,
				r0 = r0,
				r1 = r1,
				explicit = explicit,
			},
		)
	}

	return items[:]
}

@(private)
layout_grid_auto_place :: proc(
	node: ^Layout_Node,
	items: []Layout_Grid_Item,
	cols, rows: int,
	flow: Grid_Auto_Flow,
) -> (
	out_cols, out_rows: int,
) {
	out_cols = max(cols, 1)
	out_rows = max(rows, 1)

	occupied := make(
		[]bool,
		out_cols * out_rows,
		context.temp_allocator,
	)
	dense := layout_grid_flow_dense(flow)

	for i in 0 ..< len(items) {
		item := &items[i]
		if item.explicit {
			out_cols = max(out_cols, item.c1 - 1)
			out_rows = max(out_rows, item.r1 - 1)
			if item.c1 > out_cols || item.r1 > out_rows {
				new_cols := max(out_cols, item.c1 - 1)
				new_rows := max(out_rows, item.r1 - 1)
				new_occ := make([]bool, new_cols * new_rows, context.temp_allocator)
				for r in 1 ..= out_rows {
					for c in 1 ..= out_cols {
						old_idx := (r - 1) * out_cols + (c - 1)
						new_idx := (r - 1) * new_cols + (c - 1)
						if old_idx < len(occupied) && new_idx < len(new_occ) {
							new_occ[new_idx] = occupied[old_idx]
						}
					}
				}
				occupied = new_occ
				out_cols = new_cols
				out_rows = new_rows
			}
			layout_grid_mark_occupied(occupied, out_cols, item.c0, item.c1, item.r0, item.r1)
			continue
		}

		span_c := 1
		span_r := 1
		if item.c1 > item.c0 do span_c = item.c1 - item.c0
		if item.r1 > item.r0 do span_r = item.r1 - item.r0

		placed := false
		for grow in 0 ..< GRID_MAX_IMPLICIT_TRACKS {
			c0, r0, ok := layout_grid_find_auto_slot(
				occupied,
				out_cols,
				out_rows,
				span_c,
				span_r,
				flow,
				dense,
			)
			if ok {
				item.c0 = c0
				item.c1 = c0 + span_c
				item.r0 = r0
				item.r1 = r0 + span_r
				placed = true
				break
			}

			out_rows += 1
			if len(occupied) < out_cols * out_rows {
				new_occ := make([]bool, out_cols * out_rows, context.temp_allocator)
				for j in 0 ..< min(len(occupied), len(new_occ)) {
					new_occ[j] = occupied[j]
				}
				occupied = new_occ
			}
			_ = grow
		}
		if !placed do continue

		out_cols = max(out_cols, item.c1 - 1)
		out_rows = max(out_rows, item.r1 - 1)
		if item.c1 > out_cols + 1 || item.r1 > out_rows + 1 {
			out_cols = max(out_cols, item.c1 - 1)
			out_rows = max(out_rows, item.r1 - 1)
		}

		if len(occupied) < out_cols * out_rows {
			new_occ := make([]bool, out_cols * out_rows, context.temp_allocator)
			for j in 0 ..< min(len(occupied), len(new_occ)) {
				new_occ[j] = occupied[j]
			}
			occupied = new_occ
		}

		layout_grid_mark_occupied(occupied, out_cols, item.c0, item.c1, item.r0, item.r1)
	}

	return out_cols, out_rows
}

@(private)
layout_grid_item_content_mins :: proc(
	items: []Layout_Grid_Item,
	col_tracks, row_tracks: []Grid_Track_Size,
	gap_x, gap_y: f32,
) -> (
	col_mins, row_mins: []f32,
) {
	col_mins = make([]f32, len(col_tracks), context.temp_allocator)
	row_mins = make([]f32, len(row_tracks), context.temp_allocator)

	for item in items {
		child := &state.ui.layout.nodes[item.child_index]
		span_c := max(1, item.c1 - item.c0)
		span_r := max(1, item.r1 - item.r0)
		gap_c := span_c > 1 ? gap_x * f32(span_c - 1) : 0
		gap_r := span_r > 1 ? gap_y * f32(span_r - 1) : 0

		outer := layout_size_with_margin(child.desired, child.margin)
		min_w := max(0, outer.x - gap_c)
		min_h := max(0, outer.y - gap_r)
		per_col := min_w / f32(span_c)
		per_row := min_h / f32(span_r)

		for c in item.c0 - 1 ..< item.c1 - 1 {
			if c >= 0 && c < len(col_mins) {
				col_mins[c] = max(col_mins[c], per_col)
			}
		}
		for r in item.r0 - 1 ..< item.r1 - 1 {
			if r >= 0 && r < len(row_mins) {
				row_mins[r] = max(row_mins[r], per_row)
			}
		}
	}

	return col_mins, row_mins
}

@(private)
layout_grid_track_sizes :: proc(
	tracks: []Grid_Track_Size,
	gap: f32,
	available: f32,
	content_mins: []f32,
) -> []f32 {
	sizes := make([]f32, len(tracks), context.temp_allocator)
	grid_distribute_tracks(tracks, gap, available, content_mins, sizes)
	return sizes
}

@(private)
layout_grid_sum_tracks :: proc(sizes: []f32, gap: f32) -> f32 {
	if len(sizes) == 0 do return 0
	total: f32
	for s in sizes do total += s
	if len(sizes) > 1 do total += gap * f32(len(sizes) - 1)
	return total
}

@(private)
layout_grid_offset_for_line :: proc(
	line: int,
	sizes: []f32,
	gap: f32,
) -> f32 {
	if line <= 1 do return 0
	pos: f32
	for i in 0 ..< line - 1 {
		if i < len(sizes) do pos += sizes[i]
		if i + 1 < line - 1 do pos += gap
	}
	return pos
}

@(private)
layout_grid_span_size :: proc(
	start, end: int,
	sizes: []f32,
	gap: f32,
) -> f32 {
	if end <= start do return 0
	total: f32
	for i in start - 1 ..< end - 1 {
		if i >= 0 && i < len(sizes) do total += sizes[i]
	}
	span := end - start
	if span > 1 do total += gap * f32(span - 1)
	return total
}

@(private)
layout_grid_cell_rect :: proc(
	c0, c1, r0, r1: int,
	content: Rect,
	col_sizes, row_sizes: []f32,
	gap_x, gap_y: f32,
) -> Rect {
	x := content.x + layout_grid_offset_for_line(c0, col_sizes, gap_x)
	y := content.y + layout_grid_offset_for_line(r0, row_sizes, gap_y)
	w := layout_grid_span_size(c0, c1, col_sizes, gap_x)
	h := layout_grid_span_size(r0, r1, row_sizes, gap_y)
	return {x, y, w, h}
}

@(private)
layout_grid_place_item :: proc(
	child: ^Layout_Node,
	cell: Rect,
	container_justify: Justify_Pos,
) {
	child_justify := layout_merge_justify(container_justify, child.config.self)
	m := child.margin
	inner_w := max(0, cell.w - m.l - m.r)
	inner_h := max(0, cell.h - m.t - m.b)

	size := child.desired
	if !length_is_definite(child.config.width) {
		size.x = inner_w
	}
	if !length_is_definite(child.config.height) {
		size.y = inner_h
	}
	layout_apply_definite_size(child, {cell.x + m.l, cell.y + m.t, inner_w, inner_h}, &size)

	x := cell.x + m.l + justify_align_position_offset_x(inner_w, size.x, child_justify.x)
	y := cell.y + m.t + justify_align_position_offset_y(inner_h, size.y, child_justify.y)
	x += child.config.x
	y += child.config.y

	child.rect = {x, y, size.x, size.y}
	layout_finalize_after_rect(child)
}

/*
Measures a grid container's intrinsic size from track definitions and children.
*/
layout_grid_measure :: proc(node: ^Layout_Node) -> Vec2 {
	padding := node.padding
	border := node.border
	gap_x := f32(node.config.gap_x)
	gap_y := f32(node.config.gap_y)

	areas: map[string]Grid_Area_Lines
	if node.config.grid_template_areas != "" {
		_, _, areas, _ = grid_parse_template_areas(
			node.config.grid_template_areas,
			context.temp_allocator,
		)
	}

	items := layout_grid_collect_items(node, areas)
	initial_cols := node.config.grid_template_columns.count
	initial_rows := node.config.grid_template_rows.count
	if initial_cols <= 0 && len(items) > 0 do initial_cols = 1

	max_col := initial_cols
	max_row := initial_rows
	for item in items {
		if item.c1 > 0 do max_col = max(max_col, item.c1 - 1)
		if item.r1 > 0 do max_row = max(max_row, item.r1 - 1)
	}

	items_mut := slice.clone(items, context.temp_allocator)
	out_cols, out_rows := layout_grid_auto_place(
		node,
		items_mut,
		max_col,
		max_row,
		node.config.grid_auto_flow,
	)

	col_tracks := layout_grid_expand_tracks(
		node.config.grid_template_columns,
		out_cols,
		node.config.grid_auto_columns,
	)
	row_tracks := layout_grid_expand_tracks(
		node.config.grid_template_rows,
		out_rows,
		node.config.grid_auto_rows,
	)

	col_mins, row_mins := layout_grid_item_content_mins(items_mut, col_tracks, row_tracks, gap_x, gap_y)
	col_sizes := layout_grid_track_sizes(col_tracks, gap_x, 0, col_mins)
	row_sizes := layout_grid_track_sizes(row_tracks, gap_y, 0, row_mins)

	width := length_resolve(node.config.width, 0)
	height := length_resolve(node.config.height, 0)

	inset_w := padding.l + padding.r + border.l + border.r
	inset_h := padding.t + padding.b + border.t + border.b

	if width <= 0 do width = layout_grid_sum_tracks(col_sizes, gap_x) + inset_w
	if height <= 0 do height = layout_grid_sum_tracks(row_sizes, gap_y) + inset_h

	return {
		layout_clamp_axis(width, node.config.min_w, node.config.max_w),
		layout_clamp_axis(height, node.config.min_h, node.config.max_h),
	}
}

/*
Positions grid children using CSS grid track sizing and placement.
*/
layout_grid_position_children :: proc(node: ^Layout_Node, content: Rect) {
	gap_x := f32(node.config.gap_x)
	gap_y := f32(node.config.gap_y)
	justify := layout_config_justify(node.config)

	areas: map[string]Grid_Area_Lines
	if node.config.grid_template_areas != "" {
		_, _, areas, _ = grid_parse_template_areas(
			node.config.grid_template_areas,
			context.temp_allocator,
		)
	}

	items := layout_grid_collect_items(node, areas)
	items_mut := slice.clone(items, context.temp_allocator)

	initial_cols := node.config.grid_template_columns.count
	initial_rows := node.config.grid_template_rows.count
	if initial_cols <= 0 && len(items_mut) > 0 do initial_cols = 1

	max_col := initial_cols
	max_row := initial_rows
	for item in items_mut {
		if item.c1 > 0 do max_col = max(max_col, item.c1 - 1)
		if item.r1 > 0 do max_row = max(max_row, item.r1 - 1)
	}

	out_cols, out_rows := layout_grid_auto_place(
		node,
		items_mut,
		max_col,
		max_row,
		node.config.grid_auto_flow,
	)

	col_tracks := layout_grid_expand_tracks(
		node.config.grid_template_columns,
		out_cols,
		node.config.grid_auto_columns,
	)
	row_tracks := layout_grid_expand_tracks(
		node.config.grid_template_rows,
		out_rows,
		node.config.grid_auto_rows,
	)

	col_mins, row_mins := layout_grid_item_content_mins(items_mut, col_tracks, row_tracks, gap_x, gap_y)
	col_sizes := layout_grid_track_sizes(col_tracks, gap_x, content.w, col_mins)
	row_sizes := layout_grid_track_sizes(row_tracks, gap_y, content.h, row_mins)

	for i in 0 ..< len(items_mut) {
		item := items_mut[i]
		child := &state.ui.layout.nodes[item.child_index]
		cell := layout_grid_cell_rect(
			item.c0,
			item.c1,
			item.r0,
			item.r1,
			content,
			col_sizes,
			row_sizes,
			gap_x,
			gap_y,
		)
		layout_grid_place_item(child, cell, justify)
	}

	layout_position_out_of_flow_children(node)
	layout_finalize_scrollport(node, content)
}
