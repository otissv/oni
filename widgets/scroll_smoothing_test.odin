#+test
package oni_widgets

import o ".."
import "core:testing"

@(test)
scroll_smoothing_advances_without_hover_and_notifies_current_offset :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		scroll_bar_test_notified_y = -1
		widget_test_begin_layout()
		scroll_bar_test_scroll_port(scroll_bar_test_tall_child)
		widget_test_finish_layout()
		widget_test_begin_draw()
		ov: o.Overflow = .SCROLL
		id := o.ui_id("vp")
		metrics, _ := o.Scrollport_Metrics_Get(id)
		o.widget_scroll_update("vp", metrics.max_scroll, {0, -1}, .HIDDEN, ov, 1)
		o.Shortcut_Consume_Wheel()
		widget_handle_scroll_wheel(id, {overflow_x = .HIDDEN, overflow_y = ov}, false, "vp", proc(x, y: f32) {
			scroll_bar_test_notified_y = y
		})
		offset := o.widget_scroll_get("vp")
		testing.expect(t, offset.y > 0 && offset.y <= 40)
		expect_close(t, scroll_bar_test_notified_y, offset.y)
		updated, _ := o.Scrollport_Metrics_Get(id)
		expect_close(t, updated.scroll.y, offset.y)
		widget_test_end_frame()
	})
}

@(test)
scrollbar_drag_cancels_pending_wheel_motion :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		ov: o.Overflow = .SCROLL
		o.widget_scroll_update("port", {100, 100}, {0, -1}, .HIDDEN, ov, 1_000_000_000)
		widget_scroll_push({element_id = "port", scroll = o.widget_scroll_ensure("port")})
		defer widget_scroll_pop()
		widget_scroll_notify(0, 12)
		o.state.frame_dirty = false
		o.widget_scroll_update("port", {100, 100}, {}, .HIDDEN, ov, 1_100_000_000)
		expect_close(t, o.widget_scroll_get("port").y, 12)
		testing.expect(t, !o.state.frame_dirty)
	})
}
