#+test
package oni

import "core:testing"

@(test)
scroll_smoothing_is_independent_of_frame_rate :: proc(t: ^testing.T) {
	for fps in ([3]int{30, 60, 144}) {
		value: f32
		for _ in 0..<fps {
			value = scroll_smooth_axis(value, 400, 1.0 / f64(fps))
		}
		testing.expect(t, abs(value - 400) < 0.01)
	}
	coarse := scroll_smooth_axis(0, 400, 0.1)
	fine: f32
	for _ in 0..<10 {
		fine = scroll_smooth_axis(fine, 400, 0.01)
	}
	testing.expect(t, coarse > 0 && coarse < 400)
	testing.expect(t, abs(coarse - fine) < 0.001)
	expect_close(t, scroll_smooth_axis(20, 80, 0), 20)
}

@(test)
scroll_smoothing_accumulates_clamps_and_stops_waking :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		ov: Overflow = .SCROLL
		testing.expect(t, widget_scroll_update("port", {100, 100}, {0, -1}, ov, ov, 1_000_000_000))
		expect_close(t, widget_scroll_get("port").y, 0)
		testing.expect(t, state.frame_dirty)
		testing.expect(t, widget_scroll_update("port", {100, 100}, {0, -1}, ov, ov, 1_016_666_667))
		value := widget_scroll_get("port").y
		testing.expect(t, value > 0 && value < 40)
		testing.expect(t, !widget_scroll_update("port", {100, 100}, {}, ov, ov, 1_100_000_000))
		testing.expect(t, widget_scroll_get("port").y > value)
		widget_scroll_update("port", {100, 100}, {}, ov, ov, 2_000_000_000)
		expect_close(t, widget_scroll_get("port").y, 80)
		state.frame_dirty = false
		widget_scroll_update("port", {100, 100}, {}, ov, ov, 2_100_000_000)
		testing.expect(t, !state.frame_dirty)
		widget_scroll_update("port", {100, 20}, {}, ov, ov, 2_200_000_000)
		expect_close(t, widget_scroll_get("port").y, 20)
		testing.expect(t, !widget_scroll_update("port", {100, 20}, {0, -1}, ov, ov, 2_300_000_000))
	})
}

@(test)
scroll_smoothing_yields_to_explicit_offsets :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		ov: Overflow = .SCROLL
		widget_scroll_update("port", {100, 100}, {-1, -1}, ov, ov, 1_000_000_000)
		widget_scroll_set("port", {10, 15})
		widget_scroll_update("port", {100, 100}, {}, ov, ov, 1_100_000_000)
		testing.expect_value(t, widget_scroll_get("port"), Vec2{10, 15})
		// Controlled callbacks may echo the current offset without cancelling motion.
		widget_scroll_update("port", {100, 100}, {-1, -1}, ov, ov, 1_200_000_000)
		config := Resolved_Widget_Config{overflow_x = ov, overflow_y = ov}
		widget_scroll_apply("port", {scroll_x = f32(10), scroll_y = f32(5)}, &config)
		widget_scroll_update("port", {100, 100}, {}, ov, ov, 1_300_000_000)
		testing.expect(t, widget_scroll_get("port").x > 10)
		expect_close(t, widget_scroll_get("port").y, 5)
	})
}

@(test)
scroll_smoothing_reverses_and_disables_axes :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		ov: Overflow = .SCROLL
		widget_scroll_update("port", {100, 100}, {-1, -1}, ov, ov, 1_000_000_000)
		widget_scroll_update("port", {100, 100}, {}, ov, ov, 1_050_000_000)
		widget_scroll_update("port", {100, 100}, {1, 1}, ov, ov, 1_050_000_000)
		previous := widget_scroll_get("port")
		widget_scroll_update("port", {100, 100}, {}, ov, ov, 1_100_000_000)
		testing.expect(t, widget_scroll_get("port").y < previous.y)
		widget_scroll_update("port", {100, 100}, {-1, -1}, .HIDDEN, ov, 1_150_000_000)
		expect_close(t, widget_scroll_get("port").x, 0)
	})
}

@(test)
scroll_smoothing_does_not_reapply_stale_props_during_draw :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		ov: Overflow = .SCROLL
		widget_scroll_update("port", {100, 100}, {0, -1}, .HIDDEN, ov, 1_000_000_000)
		widget_scroll_update("port", {100, 100}, {}, .HIDDEN, ov, 1_050_000_000)
		before := widget_scroll_get("port")
		state.ui.pass = .Draw
		config := Resolved_Widget_Config{overflow_y = ov}
		widget_scroll_apply("port", {scroll_y = f32(0)}, &config)
		testing.expect_value(t, widget_scroll_get("port"), before)
		widget_scroll_update("port", {100, 100}, {}, .HIDDEN, ov, 1_100_000_000)
		testing.expect(t, widget_scroll_get("port").y > before.y)
	})
}

@(test)
scroll_delta_moves_children_and_updates_metrics :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		ui_begin_frame()
		ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
		defer ui_pop_style()
		layout_begin_space(.SCREEN)
		ov: Overflow = .SCROLL
		layout_push_node(UI_Id(1), {kind = .RECT, direction = .VERTICAL, width = layout_len_fixed(100), height = layout_len_fixed(100), overflow_y = ov})
		spacer := layout_push_node(UI_Id(3), {kind = .RECT, width = layout_len_fixed(80), height = layout_len_fixed(30)})
		layout_set_measure_size(spacer, {80, 30})
		layout_pop_node()
		child := layout_push_node(UI_Id(2), {kind = .RECT, width = layout_len_fixed(80), height = layout_len_fixed(200), overflow_y = .HIDDEN})
		layout_set_measure_size(child, {80, 200})
		layout_pop_node()
		layout_pop_node()
		layout_end_space()
		parent_index := state.ui.layout.id_to_node[UI_Id(1)]
		layout_resolve_clips(parent_index, {}, false)
		child_index := state.ui.layout.id_to_node[UI_Id(2)]
		before := state.ui.layout.nodes[child_index].rect.y
		testing.expect(t, layout_apply_scroll_delta(UI_Id(1), {0, 12.5}))
		expect_close(t, state.ui.layout.nodes[child_index].rect.y, before - 12.5)
		expect_close(t, state.ui.layout.nodes[child_index].clip_rect.y, before - 12.5)
		metrics, ok := ui_scrollport_metrics(UI_Id(1))
		testing.expect(t, ok)
		expect_close(t, metrics.scroll.y, 12.5)
	})
}
