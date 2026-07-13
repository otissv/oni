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
widget_pointer_focus_uses_target_not_ancestor_hover :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			parent_id := o.UI_Id(10)
			child_id := o.UI_Id(20)
			_ = o.layout_push_node(
				parent_id,
				{kind = .RECT, space = .SCREEN, width = len_fixed(100), height = len_fixed(100)},
			)
			_ = o.layout_push_node(
				child_id,
				{kind = .RECT, space = .SCREEN, width = len_fixed(40), height = len_fixed(40)},
			)
			o.layout_pop_node()
			o.layout_pop_node()
			parent_i := o.state.ui.layout.id_to_node[parent_id]
			child_i := o.state.ui.layout.id_to_node[child_id]
			o.state.ui.layout.nodes[parent_i].rect = {0, 0, 100, 100}
			o.state.ui.layout.nodes[child_i].rect = {10, 10, 40, 40}
			o.layout_finalize_stack_order()
			widget_test_finish_layout()

			o.w_ctx.mouse_x = 20
			o.w_ctx.mouse_y = 20
			widget_test_begin_draw()
			o.w_ctx.left_mouse.pressed = true

			config := o.Resolved_Widget_Config {
				space = .SCREEN,
				tabbable = true,
			}
			parent_props := Rectangle_Props{}
			child_props := Rectangle_Props{}
			parent_frame := Rectangle_State{}
			child_frame := Rectangle_State{}
			parent_handlers := widget_lifecycle_handlers(parent_props, Rectangle_State)
			child_handlers := widget_lifecycle_handlers(child_props, Rectangle_State)

			parent_got, parent_lost := widget_handle_interaction(
				parent_props,
				&parent_frame,
				parent_handlers,
				"parent",
				true, // was focused
				true,
				parent_id,
				o.state.ui.layout.nodes[parent_i].rect,
				config,
			)
			child_got, child_lost := widget_handle_interaction(
				child_props,
				&child_frame,
				child_handlers,
				"child",
				false,
				true,
				child_id,
				o.state.ui.layout.nodes[child_i].rect,
				config,
			)

			testing.expect(t, parent_frame.is_hovered)
			testing.expect(t, !parent_frame.is_pointer_target)
			testing.expect(t, parent_lost && !parent_got)
			testing.expect(t, !parent_frame.is_focused)

			testing.expect(t, child_frame.is_hovered)
			testing.expect(t, child_frame.is_pointer_target)
			testing.expect(t, child_got && !child_lost)
			testing.expect(t, child_frame.is_focused)
			testing.expect_value(t, o.w_ctx.focused_id, "child")
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
