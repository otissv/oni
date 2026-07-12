package widgets

import o ".."
import "core:testing"

@(test)
widget_register_tab_order_respects_flags :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_register_tab_order("a", false, true)
			widget_register_tab_order("b", true, false)
			widget_register_tab_order("c", true, true)
			testing.expect_value(t, len(o.w_ctx.tab_order), 1)
			testing.expect_value(t, o.w_ctx.tab_order[0], "c")
		},
	)
}

@(test)
widget_should_auto_focus_requires_flags_and_fresh_id :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			config := o.Resolved_Widget_Config {
				auto_focus = true,
				tabbable = true,
			}
			testing.expect(t, widget_should_auto_focus(config, "one"))

			widget_apply_auto_focus("one", true)
			testing.expect(t, !widget_should_auto_focus(config, "one"))
			testing.expect_value(t, o.w_ctx.focused_id, "one")
			testing.expect_value(t, o.w_ctx.auto_focused_id, "one")

			no_tab := o.Resolved_Widget_Config {
				auto_focus = true,
				tabbable = false,
			}
			testing.expect(t, !widget_should_auto_focus(no_tab, "two"))
		},
	)
}

@(test)
widget_is_focused_matches_context :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			o.w_ctx.focused_id = "focused"
			testing.expect(t, widget_is_focused("focused"))
			testing.expect(t, !widget_is_focused("other"))
		},
	)
}

@(test)
widget_handle_pointer_focus_gains_and_loses_on_press :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			focused := false
			o.w_ctx.left_mouse.pressed = true

			got, lost := widget_handle_pointer_focus("btn", true, false, true, &focused)
			testing.expect(t, got && !lost)
			testing.expect(t, focused)
			testing.expect_value(t, o.w_ctx.focused_id, "btn")

			got, lost = widget_handle_pointer_focus("btn", true, true, false, &focused)
			testing.expect(t, !got && lost)
			testing.expect(t, !focused)
			testing.expect_value(t, o.w_ctx.focused_id, "")

			got, lost = widget_handle_pointer_focus("btn", false, false, true, &focused)
			testing.expect(t, !got && !lost)
		},
	)
}

@(test)
widget_tab_focus_transition_helpers :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			o.w_ctx.tab_focus_changed = true
			o.w_ctx.focused_id = "next"
			o.w_ctx.tab_focus_previous_id = "prev"

			testing.expect(t, widget_got_tab_focus("next"))
			testing.expect(t, !widget_got_tab_focus("prev"))
			testing.expect(t, widget_lost_tab_focus("prev"))
			testing.expect(t, !widget_lost_tab_focus("next"))
		},
	)
}
