package oni

import "core:testing"

@(test)
layout_slider_finalize_builds_track_and_thumb :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		idx := layout_test_append_node(layout, -1, .SLIDER, desired = {200, 20})
		node := &layout.nodes[idx]
		node.rect = {x = 10, y = 20, w = 200, h = 20}
		node.ui_id = UI_Id(1)
		layout.id_to_node[node.ui_id] = idx

		layout_set_slider(
			node,
			{
				orientation = .HORIZONTAL,
				values = {50, 0},
				count = 1,
				min = 0,
				max = 100,
				thumb_size = 16,
				track_thickness = 6,
				active = true,
			},
		)
		layout_finalize_slider_node(node)

		chrome := layout_slider_result(node.ui_id)
		testing.expect(t, chrome != nil)

		if chrome == nil {
			return
		}

		testing.expect(t, chrome.active)
		testing.expect(t, chrome.count == 1)
		expect_close(t, chrome.track.x, 10)
		expect_close(t, chrome.track.w, 200)
		testing.expect(t, chrome.thumbs[0].w > 0)
		testing.expect(t, chrome.thumbs[0].h > 0)
	})
}

@(test)
layout_slider_single_thumb_range_starts_at_track :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		idx := layout_test_append_node(layout, -1, .SLIDER, desired = {200, 20})
		node := &layout.nodes[idx]
		node.rect = {x = 10, y = 20, w = 200, h = 20}
		node.ui_id = UI_Id(11)
		layout.id_to_node[node.ui_id] = idx

		layout_set_slider(
			node,
			{
				orientation = .HORIZONTAL,
				values = {50, 0},
				count = 1,
				min = 0,
				max = 100,
				thumb_size = 16,
				track_thickness = 6,
				active = true,
			},
		)
		layout_finalize_slider_node(node)

		chrome := layout_slider_result(node.ui_id)
		testing.expect(t, chrome != nil)

		if chrome == nil {
			return
		}

		expect_close(t, chrome.range.x, chrome.track.x)
		testing.expect(t, chrome.range.w > 0)
		expect_close(t, chrome.range.y, chrome.track.y)
		expect_close(t, chrome.range.h, chrome.track.h)
	})
}

@(test)
layout_slider_finalize_moves_thumb_with_value :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		idx := layout_test_append_node(layout, -1, .SLIDER, desired = {100, 20})
		node := &layout.nodes[idx]
		node.rect = {x = 0, y = 0, w = 100, h = 20}
		node.ui_id = UI_Id(2)
		layout.id_to_node[node.ui_id] = idx

		layout_set_slider(
			node,
			{
				orientation = .HORIZONTAL,
				values = {0, 0},
				count = 1,
				min = 0,
				max = 100,
				thumb_size = 10,
				track_thickness = 4,
				active = true,
			},
		)
		layout_finalize_slider_node(node)

		before := layout_slider_result(node.ui_id)
		testing.expect(t, before != nil)

		if before == nil {
			return
		}

		x0 := before.thumbs[0].x
		node.slider_input.values[0] = 100
		layout_finalize_slider_node(node)
		after := layout_slider_result(node.ui_id)
		testing.expect(t, after != nil)

		if after == nil {
			return
		}

		testing.expect(t, after.thumbs[0].x > x0)

		// Paint helper must match finalize without mutating layout state.
		paint := layout_slider_thumb_rect(
			after.track,
			.HORIZONTAL,
			100,
			0,
			100,
			false,
			10,
		)
		testing.expect(t, paint.x == after.thumbs[0].x)
		testing.expect(t, paint.y == after.thumbs[0].y)
	})
}

@(test)
layout_scroll_bar_finalize_builds_thumb :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		idx := layout_test_append_node(layout, -1, .SCROLL_BAR, desired = {12, 100})
		node := &layout.nodes[idx]
		node.rect = {x = 0, y = 0, w = 12, h = 100}
		node.ui_id = UI_Id(3)
		layout.id_to_node[node.ui_id] = idx

		layout_set_scroll_bar(
			node,
			{
				axis = .Y,
				viewport = 50,
				content = 200,
				scroll = 0,
				min_thumb = 24,
				active = true,
			},
		)
		layout_finalize_scroll_bar_node(node)

		chrome := layout_scroll_bar_result(node.ui_id)
		testing.expect(t, chrome != nil)

		if chrome == nil {
			return
		}

		testing.expect(t, chrome.thumb.h >= 24)
		testing.expect(t, chrome.thumb.y == 0)

		node.scroll_bar_input.scroll = 150
		layout_finalize_scroll_bar_node(node)
		chrome = layout_scroll_bar_result(node.ui_id)
		testing.expect(t, chrome != nil)

		if chrome == nil {
			return
		}

		testing.expect(t, chrome.thumb.y > 0)

		paint := layout_scroll_bar_thumb_rect(node.rect, .Y, 50, 200, 150, 24)
		testing.expect(t, paint.y == chrome.thumb.y)
		testing.expect(t, paint.h == chrome.thumb.h)
	})
}

@(test)
layout_color_picker_channels_finalize_hits :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		idx := layout_test_append_node(layout, -1, .COLOR_PICKER, desired = {120, 132})
		node := &layout.nodes[idx]
		node.rect = {x = 5, y = 10, w = 120, h = 132}
		node.ui_id = UI_Id(4)
		layout.id_to_node[node.ui_id] = idx

		layout_set_color_picker_channels(node, {row_h = 22, active = true})
		layout_finalize_color_picker_channels_node(node)

		chrome := layout_color_picker_channels_result(node.ui_id)
		testing.expect(t, chrome != nil)

		if chrome == nil {
			return
		}

		expect_close(t, chrome.hits[0].x, 5)
		expect_close(t, chrome.hits[0].y, 10)
		expect_close(t, chrome.hits[0].h, 22)
		expect_close(t, chrome.hits[5].y, 10 + 22 * 5)
	})
}

@(test)
layout_calendar_finalize_builds_day_rects :: proc(t: ^testing.T) {
	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		idx := layout_test_append_node(layout, -1, .CALENDAR, desired = {320, 360})
		node := &layout.nodes[idx]
		node.rect = {x = 0, y = 0, w = 320, h = 360}
		node.ui_id = UI_Id(5)
		layout.id_to_node[node.ui_id] = idx

		layout_set_calendar(
			node,
			{
				number_of_months = 1,
				day_size = 36,
				gap = 4,
				pad = 12,
				month_gap = 12,
				show_week_numbers = false,
				nav_height = 36,
				weekday_height = 28,
				week_num_width = 28,
				active = true,
			},
		)
		layout_finalize_calendar_node(node)

		chrome := layout_calendar_result(node.ui_id)
		testing.expect(t, chrome != nil)

		if chrome == nil {
			return
		}

		testing.expect(t, len(chrome.months) == 1)
		testing.expect(t, chrome.months[0].days[0].w == 36)
		testing.expect(t, chrome.months[0].days[0].h == 36)
		testing.expect(t, chrome.months[0].prev.w == 36)
		testing.expect(t, chrome.months[0].next.w == 36)
	})
}
