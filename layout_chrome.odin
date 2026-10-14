package oni

LAYOUT_CALENDAR_MAX_MONTHS :: 12
LAYOUT_CALENDAR_GRID_DAYS :: 42
LAYOUT_CALENDAR_WEEK_DAYS :: 7
LAYOUT_CALENDAR_WEEK_ROWS :: 6
LAYOUT_COLOR_PICKER_CHANNEL_COUNT :: 6

/*
Author inputs for layout-owned slider track / range / thumb geometry.
*/
Layout_Slider_Input :: struct {
	orientation:     Slider_Orientation,
	values:          [SLIDER_MAX_THUMBS]f32,
	count:           int,
	min:             f32,
	max:             f32,
	inverted:        bool,
	thumb_size:      f32,
	track_thickness: f32,
	active:          bool,
}

/*
Layout-owned slider chrome after the root rect is solved.
*/
Layout_Slider :: struct {
	track:  Rect,
	range:  Rect,
	thumbs: [SLIDER_MAX_THUMBS]Rect,
	count:  int,
	active: bool,
}

/*
Author inputs for layout-owned scrollbar thumb geometry.
*/
Layout_Scroll_Bar_Input :: struct {
	axis:      Scroll_Axis,
	viewport:  f32,
	content:   f32,
	scroll:    f32,
	min_thumb: f32,
	active:    bool,
}

/*
Layout-owned scrollbar thumb rect after the track rect is solved.
*/
Layout_Scroll_Bar :: struct {
	thumb:  Rect,
	active: bool,
}

/*
Author inputs for layout-owned color-picker channel row hit geometry.
*/
Layout_Color_Picker_Channels_Input :: struct {
	row_h:  f32,
	active: bool,
}

/*
Layout-owned channel row hit rects after the panel rect is solved.
*/
Layout_Color_Picker_Channels :: struct {
	hits:   [LAYOUT_COLOR_PICKER_CHANNEL_COUNT]Rect,
	active: bool,
}

/*
Author inputs for layout-owned calendar chrome geometry.
*/
Layout_Calendar_Input :: struct {
	number_of_months:  int,
	day_size:          f32,
	gap:               f32,
	pad:               f32,
	month_gap:         f32,
	show_week_numbers: bool,
	nav_height:        f32,
	weekday_height:    f32,
	week_num_width:    f32,
	active:            bool,
}

/*
One month of layout-owned calendar chrome rects.
*/
Layout_Calendar_Month :: struct {
	origin:    Vec2,
	prev:      Rect,
	label:     Rect,
	next:      Rect,
	weekdays:  [LAYOUT_CALENDAR_WEEK_DAYS]Rect,
	days:      [LAYOUT_CALENDAR_GRID_DAYS]Rect,
	week_nums: [LAYOUT_CALENDAR_WEEK_ROWS]Rect,
}

/*
Layout-owned calendar chrome after the root rect is solved.
*/
Layout_Calendar :: struct {
	months: []Layout_Calendar_Month,
	active: bool,
}

/*
Returns the layout node for a UI id, if present in the current frame tree.
*/
layout_node_by_id :: proc(id: UI_Id) -> (^Layout_Node, bool) {
	if state == nil {
		return nil, false
	}

	idx, ok := state.ui.layout.id_to_node[id]

	if !ok {
		return nil, false
	}

	return &state.ui.layout.nodes[idx], true
}

/*
Returns the layout node currently on top of the push stack, if any.
*/
layout_current_node :: proc() -> (^Layout_Node, bool) {
	if state == nil || len(state.ui.layout.node_stack) == 0 {
		return nil, false
	}

	idx := state.ui.layout.node_stack[len(state.ui.layout.node_stack) - 1]

	return &state.ui.layout.nodes[idx], true
}

/*
Attaches slider chrome inputs for finalize after the node rect is assigned.
*/
layout_set_slider :: proc(node: ^Layout_Node, input: Layout_Slider_Input) {
	if node == nil {
		return
	}

	node.slider_input = input
	node.slider_input.active = true
	node.slider = {}
}

/*
Attaches scrollbar chrome inputs for finalize after the node rect is assigned.
*/
layout_set_scroll_bar :: proc(node: ^Layout_Node, input: Layout_Scroll_Bar_Input) {
	if node == nil {
		return
	}

	node.scroll_bar_input = input
	node.scroll_bar_input.active = true
	node.scroll_bar = {}
}

/*
Attaches color-picker channel hit inputs for finalize after the node rect is assigned.
*/
layout_set_color_picker_channels :: proc(
	node: ^Layout_Node,
	input: Layout_Color_Picker_Channels_Input,
) {
	if node == nil {
		return
	}

	node.color_picker_channels_input = input
	node.color_picker_channels_input.active = true
	node.color_picker_channels = {}
}

/*
Attaches calendar chrome inputs for finalize after the node rect is assigned.
*/
layout_set_calendar :: proc(node: ^Layout_Node, input: Layout_Calendar_Input) {
	if node == nil {
		return
	}

	node.calendar_input = input
	node.calendar_input.active = true
	node.calendar = {}
}

/*
Pure track rect inside a root/solved rect. Layout finalize and draw paint both
use this; it does not mutate layout state.
*/
layout_slider_track_rect :: proc(
	root: Rect,
	orientation: Slider_Orientation,
	thickness: f32,
) -> Rect {
	thick := max(f32(1), thickness)

	if orientation == .VERTICAL {
		x := root.x + max(f32(0), (root.w - thick) * 0.5)

		return {x = x, y = root.y, w = thick, h = root.h}
	}

	y := root.y + max(f32(0), (root.h - thick) * 0.5)

	return {x = root.x, y = y, w = root.w, h = thick}
}

/*
Pure thumb rect along a track for a value. Layout finalize and draw paint both
use this; it does not mutate layout state.
*/
layout_slider_thumb_rect :: proc(
	track: Rect,
	orientation: Slider_Orientation,
	value: f32,
	min_v, max_v: f32,
	inverted: bool,
	thumb_size: f32,
) -> Rect {
	t := slider_t_from_value(value, min_v, max_v, inverted)

	if orientation == .VERTICAL {
		size := clamp(thumb_size, 0, track.h)
		pos := slider_thumb_pos_from_t(track.h, size, t)
		x := track.x + (track.w - size) * 0.5

		return {x = x, y = track.y + pos, w = size, h = size}
	}

	size := clamp(thumb_size, 0, track.w)
	pos := slider_thumb_pos_from_t(track.w, size, t)
	y := track.y + (track.h - size) * 0.5

	return {x = track.x + pos, y = y, w = size, h = size}
}

/*
Pure range fill along a track for current values. Layout finalize and draw paint
both use this; it does not mutate layout state.
*/
layout_slider_range_rect :: proc(
	track: Rect,
	orientation: Slider_Orientation,
	values: [SLIDER_MAX_THUMBS]f32,
	count: int,
	min_v, max_v: f32,
	inverted: bool,
	thumb_size: f32,
) -> Rect {
	if count <= 0 {
		return {}
	}

	track_len := orientation == .VERTICAL ? track.h : track.w
	size := clamp(thumb_size, 0, track_len)
	start: f32
	end: f32

	if count == 1 {
		// Single thumb: fill from the track origin to the thumb center
		// Do not inset by half a virtual thumb at t=0.
		end_t := slider_t_from_value(values[0], min_v, max_v, inverted)
		start = 0
		end = slider_thumb_pos_from_t(track_len, size, end_t) + size * 0.5
	} else {
		a := slider_t_from_value(values[0], min_v, max_v, inverted)
		b := slider_t_from_value(values[1], min_v, max_v, inverted)
		start_t := min(a, b)
		end_t := max(a, b)
		start = slider_thumb_pos_from_t(track_len, size, start_t) + size * 0.5
		end = slider_thumb_pos_from_t(track_len, size, end_t) + size * 0.5
	}

	lo := min(start, end)
	hi := max(start, end)
	span := max(f32(0), hi - lo)

	if orientation == .VERTICAL {
		return {x = track.x, y = track.y + lo, w = track.w, h = span}
	}

	return {x = track.x + lo, y = track.y, w = span, h = track.h}
}

/*
Pure thumb rect along a layout-owned track. Used by layout finalize and by draw
for paint/hit-testing after scroll changes — does not mutate layout state.
*/
layout_scroll_bar_thumb_rect :: proc(
	track: Rect,
	axis: Scroll_Axis,
	viewport, content, scroll, min_thumb: f32,
) -> Rect {
	switch axis {
	case .X:
		thumb_w, thumb_x := scroll_bar_thumb_geometry(
			track.w,
			viewport,
			content,
			scroll,
			min_thumb,
		)

		return {x = track.x + thumb_x, y = track.y, w = thumb_w, h = track.h}
	case .Y:
		thumb_h, thumb_y := scroll_bar_thumb_geometry(
			track.h,
			viewport,
			content,
			scroll,
			min_thumb,
		)

		return {x = track.x, y = track.y + thumb_y, w = track.w, h = thumb_h}
	}

	return {}
}

@(private)
layout_color_picker_channel_hit_rects :: proc(
	panel: Rect,
	row_h: f32,
) -> [LAYOUT_COLOR_PICKER_CHANNEL_COUNT]Rect {
	h := max(f32(1), row_h)
	out: [LAYOUT_COLOR_PICKER_CHANNEL_COUNT]Rect

	for i in 0 ..< LAYOUT_COLOR_PICKER_CHANNEL_COUNT {
		out[i] = {
			x = panel.x,
			y = panel.y + f32(i) * h,
			w = panel.w,
			h = h,
		}
	}

	return out
}

@(private)
layout_calendar_month_width :: proc(
	day_size, gap, week_num_width: f32,
	show_week_numbers: bool,
) -> f32 {
	week_w := show_week_numbers ? week_num_width + gap : 0

	return(
		week_w +
		f32(LAYOUT_CALENDAR_WEEK_DAYS) * day_size +
		f32(LAYOUT_CALENDAR_WEEK_DAYS - 1) * gap \
	)
}

@(private)
layout_calendar_month_origin :: proc(
	root: Rect,
	month_index: int,
	day_size, gap, pad, month_gap, week_num_width: f32,
	show_week_numbers: bool,
) -> Vec2 {
	month_w := layout_calendar_month_width(day_size, gap, week_num_width, show_week_numbers)
	x := root.x + pad + f32(month_index) * (month_w + month_gap)
	y := root.y + pad

	return {x, y}
}

@(private)
layout_calendar_nav_rects :: proc(
	origin: Vec2,
	month_w, nav_height: f32,
) -> (
	prev, label, next: Rect,
) {
	prev = {
		x = origin.x,
		y = origin.y,
		w = nav_height,
		h = nav_height,
	}
	next = {
		x = origin.x + month_w - nav_height,
		y = origin.y,
		w = nav_height,
		h = nav_height,
	}
	label = {
		x = prev.x + prev.w + 4,
		y = origin.y,
		w = max(f32(0), next.x - (prev.x + prev.w) - 8),
		h = nav_height,
	}

	return
}

@(private)
layout_calendar_weekday_rect :: proc(
	origin: Vec2,
	col: int,
	day_size, gap, nav_height, weekday_height, week_num_width: f32,
	show_week_numbers: bool,
) -> Rect {
	week_w := show_week_numbers ? week_num_width + gap : 0
	x := origin.x + week_w + f32(col) * (day_size + gap)
	y := origin.y + nav_height + gap

	return {x = x, y = y, w = day_size, h = weekday_height}
}

@(private)
layout_calendar_day_rect :: proc(
	origin: Vec2,
	index: int,
	day_size, gap, nav_height, weekday_height, week_num_width: f32,
	show_week_numbers: bool,
) -> Rect {
	row := index / LAYOUT_CALENDAR_WEEK_DAYS
	col := index % LAYOUT_CALENDAR_WEEK_DAYS
	week_w := show_week_numbers ? week_num_width + gap : 0
	x := origin.x + week_w + f32(col) * (day_size + gap)
	y := origin.y + nav_height + gap + weekday_height + gap + f32(row) * (day_size + gap)

	return {x = x, y = y, w = day_size, h = day_size}
}

@(private)
layout_calendar_week_num_rect :: proc(
	origin: Vec2,
	row: int,
	day_size, gap, nav_height, weekday_height, week_num_width: f32,
) -> Rect {
	y := origin.y + nav_height + gap + weekday_height + gap + f32(row) * (day_size + gap)

	return {x = origin.x, y = y, w = week_num_width, h = day_size}
}

/*
Builds slider track / range / thumb rects from inputs and the solved node rect.
*/
layout_finalize_slider_node :: proc(node: ^Layout_Node) {
	node.slider = {}

	if node == nil || !node.slider_input.active {
		return
	}

	input := node.slider_input
	track := layout_slider_track_rect(node.rect, input.orientation, input.track_thickness)
	thumbs: [SLIDER_MAX_THUMBS]Rect
	count := clamp(input.count, 0, SLIDER_MAX_THUMBS)

	for i in 0 ..< count {
		thumbs[i] = layout_slider_thumb_rect(
			track,
			input.orientation,
			input.values[i],
			input.min,
			input.max,
			input.inverted,
			input.thumb_size,
		)
	}

	node.slider = {
		track  = track,
		range  = layout_slider_range_rect(
			track,
			input.orientation,
			input.values,
			count,
			input.min,
			input.max,
			input.inverted,
			input.thumb_size,
		),
		thumbs = thumbs,
		count  = count,
		active = true,
	}
}

/*
Builds the scrollbar thumb rect from inputs and the solved track rect.
*/
layout_finalize_scroll_bar_node :: proc(node: ^Layout_Node) {
	node.scroll_bar = {}

	if node == nil || !node.scroll_bar_input.active {
		return
	}

	input := node.scroll_bar_input
	node.scroll_bar = {
		thumb  = layout_scroll_bar_thumb_rect(
			node.rect,
			input.axis,
			input.viewport,
			input.content,
			input.scroll,
			input.min_thumb,
		),
		active = true,
	}
}

/*
Builds color-picker channel hit rects from inputs and the solved panel rect.
*/
layout_finalize_color_picker_channels_node :: proc(node: ^Layout_Node) {
	node.color_picker_channels = {}

	if node == nil || !node.color_picker_channels_input.active {
		return
	}

	node.color_picker_channels = {
		hits   = layout_color_picker_channel_hit_rects(
			node.rect,
			node.color_picker_channels_input.row_h,
		),
		active = true,
	}
}

/*
Builds calendar chrome rects from inputs and the solved root rect.
*/
layout_finalize_calendar_node :: proc(node: ^Layout_Node) {
	node.calendar = {}

	if node == nil || !node.calendar_input.active {
		return
	}

	input := node.calendar_input
	month_count := clamp(input.number_of_months, 0, LAYOUT_CALENDAR_MAX_MONTHS)

	if month_count <= 0 {
		return
	}

	months := make([]Layout_Calendar_Month, month_count, layout_frame_allocator())

	for mi in 0 ..< month_count {
		origin := layout_calendar_month_origin(
			node.rect,
			mi,
			input.day_size,
			input.gap,
			input.pad,
			input.month_gap,
			input.week_num_width,
			input.show_week_numbers,
		)
		month_w := layout_calendar_month_width(
			input.day_size,
			input.gap,
			input.week_num_width,
			input.show_week_numbers,
		)
		prev, label, next := layout_calendar_nav_rects(origin, month_w, input.nav_height)
		month: Layout_Calendar_Month
		month.origin = origin
		month.prev = prev
		month.label = label
		month.next = next

		for col in 0 ..< LAYOUT_CALENDAR_WEEK_DAYS {
			month.weekdays[col] = layout_calendar_weekday_rect(
				origin,
				col,
				input.day_size,
				input.gap,
				input.nav_height,
				input.weekday_height,
				input.week_num_width,
				input.show_week_numbers,
			)
		}

		for i in 0 ..< LAYOUT_CALENDAR_GRID_DAYS {
			month.days[i] = layout_calendar_day_rect(
				origin,
				i,
				input.day_size,
				input.gap,
				input.nav_height,
				input.weekday_height,
				input.week_num_width,
				input.show_week_numbers,
			)
		}

		if input.show_week_numbers {
			for row in 0 ..< LAYOUT_CALENDAR_WEEK_ROWS {
				month.week_nums[row] = layout_calendar_week_num_rect(
					origin,
					row,
					input.day_size,
					input.gap,
					input.nav_height,
					input.weekday_height,
					input.week_num_width,
				)
			}
		}

		months[mi] = month
	}

	node.calendar = {
		months = months,
		active = true,
	}
}

/*
Finalizes layout-owned interactive chrome geometry for a node.
*/
layout_finalize_chrome_node :: proc(node: ^Layout_Node) {
	if node == nil {
		return
	}

	layout_finalize_slider_node(node)
	layout_finalize_scroll_bar_node(node)
	layout_finalize_color_picker_channels_node(node)
	layout_finalize_calendar_node(node)
}

/*
Returns layout-owned slider chrome for a UI id after the layout pass.
*/
layout_slider_result :: proc(id: UI_Id) -> ^Layout_Slider {
	node, ok := layout_node_by_id(id)

	if !ok || !node.slider.active {
		return nil
	}

	return &node.slider
}

/*
Returns layout-owned scrollbar chrome for a UI id after the layout pass.
*/
layout_scroll_bar_result :: proc(id: UI_Id) -> ^Layout_Scroll_Bar {
	node, ok := layout_node_by_id(id)

	if !ok || !node.scroll_bar.active {
		return nil
	}

	return &node.scroll_bar
}

/*
Returns layout-owned color-picker channel hits for a UI id after the layout pass.
*/
layout_color_picker_channels_result :: proc(id: UI_Id) -> ^Layout_Color_Picker_Channels {
	node, ok := layout_node_by_id(id)

	if !ok || !node.color_picker_channels.active {
		return nil
	}

	return &node.color_picker_channels
}

/*
Returns layout-owned calendar chrome for a UI id after the layout pass.
*/
layout_calendar_result :: proc(id: UI_Id) -> ^Layout_Calendar {
	node, ok := layout_node_by_id(id)

	if !ok || !node.calendar.active {
		return nil
	}

	return &node.calendar
}

@(private)
layout_offset_chrome_geometry :: proc(node: ^Layout_Node, dx, dy: f32) {
	if node == nil || (dx == 0 && dy == 0) {
		return
	}

	if node.slider.active {
		node.slider.track.x += dx
		node.slider.track.y += dy
		node.slider.range.x += dx
		node.slider.range.y += dy

		for i in 0 ..< node.slider.count {
			node.slider.thumbs[i].x += dx
			node.slider.thumbs[i].y += dy
		}
	}

	if node.scroll_bar.active {
		node.scroll_bar.thumb.x += dx
		node.scroll_bar.thumb.y += dy
	}

	if node.color_picker_channels.active {
		for &hit in node.color_picker_channels.hits {
			hit.x += dx
			hit.y += dy
		}
	}

	if node.calendar.active {
		for &month in node.calendar.months {
			month.origin.x += dx
			month.origin.y += dy
			month.prev.x += dx
			month.prev.y += dy
			month.label.x += dx
			month.label.y += dy
			month.next.x += dx
			month.next.y += dy

			for &r in month.weekdays {
				r.x += dx
				r.y += dy
			}

			for &r in month.days {
				r.x += dx
				r.y += dy
			}

			for &r in month.week_nums {
				r.x += dx
				r.y += dy
			}
		}
	}
}
