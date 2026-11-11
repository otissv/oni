#+test
package oni_widgets

import o ".."
import set "../set"
import "core:testing"
import sdl "vendor:sdl3"

@(private)
tooltip_test_open := false

@(private)
tooltip_test_open_changes := 0

@(private)
tooltip_test_content_runs := 0

@(private)
tooltip_test_reset :: proc() {
	tooltip_test_open = false
	tooltip_test_open_changes = 0
	tooltip_test_content_runs = 0
}

@(private)
tooltip_test_tree :: proc(show_delay: f32 = 0) {
	delay := show_delay
	if delay <= 0 {
		delay = 0.15
	}

	Tooltip({
		config = {id = "tip-root", open = tooltip_test_open, show_delay = delay},
		on_open_change = proc(open: bool) {
			tooltip_test_open = open
			tooltip_test_open_changes += 1
		},
		child = proc(_: Tooltip_State) {
			Tooltip_Trigger({
				config = {
					id = "tip-trigger",
					width = set.Width(f32(80)),
					height = set.Height(f32(32)),
				},
			})
			Tooltip_Content({
				config = {
					width = set.Width(f32(120)),
					height = set.Height(f32(40)),
				},
				child = proc(_: Tooltip_Content_Props_State) {
					tooltip_test_content_runs += 1
				},
			})
		},
	})
}

@(private)
tooltip_test_hover_trigger :: proc() {
	for node in o.state.ui.layout.nodes {
		if node.kind != .TOOLTIP_TRIGGER do continue

		o.w_ctx.mouse_x = node.rect.x + node.rect.w * 0.5
		o.w_ctx.mouse_y = node.rect.y + node.rect.h * 0.5

		return
	}
}

@(private)
tooltip_test_frame :: proc(hover: bool, elapsed: f64) {
	widget_test_begin_layout()
	tooltip_test_tree(0.2)
	widget_test_finish_layout()

	if hover {
		tooltip_test_hover_trigger()
	} else {
		o.w_ctx.mouse_x = 790
		o.w_ctx.mouse_y = 590
	}

	widget_test_begin_draw()
	o.state.perf_frequency = sdl.GetPerformanceFrequency()
	tooltip_tick_last_counter = sdl.GetPerformanceCounter() - u64(elapsed * f64(o.state.perf_frequency))
	tooltip_test_tree(0.2)
	widget_test_end_frame()
}

@(test)
tooltip_hover_delay_survives_layout_and_draw_frames :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tooltip_test_reset()
		tooltip_test_frame(true, 0)
		testing.expect_value(t, tooltip_global_pending, "tip-root")
		tooltip_test_frame(true, 0.11)
		testing.expect(t, !tooltip_test_open)
		tooltip_test_frame(true, 0.11)
		testing.expect(t, tooltip_test_open)
		testing.expect_value(t, tooltip_test_open_changes, 1)
		tooltip_test_frame(true, 0)
		testing.expect(t, tooltip_test_content_runs > 0)
		tooltip_test_frame(false, 0)
		testing.expect(t, !tooltip_test_open)
		testing.expect_value(t, tooltip_test_open_changes, 2)
	})
}

@(test)
tooltip_leaving_before_delay_cancels_and_reentry_restarts_timer :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tooltip_test_reset()
		tooltip_test_frame(true, 0)
		tooltip_test_frame(true, 0.1)
		tooltip_test_frame(false, 0)
		testing.expect_value(t, tooltip_global_pending, "")
		tooltip_test_frame(false, 0.5)
		testing.expect(t, !tooltip_test_open)
		tooltip_test_frame(true, 0)
		tooltip_test_frame(true, 0.1)
		testing.expect(t, !tooltip_test_open)
		tooltip_test_frame(true, 0.11)
		testing.expect(t, tooltip_test_open)
	})
}

@(test)
tooltip_timer_completion_keeps_key_alive_until_open :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tooltip_test_reset()
		tooltip_register_owner("owned-key", {
			show_delay = 0.2,
			on_open_change = proc(open: bool) { tooltip_test_open = open },
		})
		tooltip_on_trigger_enter("owned-key")
		tooltip_test_advance_pending(0.3)
		testing.expect(t, tooltip_test_open)
		testing.expect_value(t, tooltip_global_active, "owned-key")
		testing.expect_value(t, tooltip_global_pending, "")
	})
}

@(test)
tooltip_repeated_open_does_not_allocate_or_notify_again :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tooltip_test_reset()
		tooltip_register_owner("owned-key", {
			on_open_change = proc(_: bool) { tooltip_test_open_changes += 1 },
		})
		tooltip_open_key("owned-key")
		tooltip_open_key("owned-key")
		testing.expect_value(t, tooltip_test_open_changes, 1)
		testing.expect_value(t, tooltip_global_active, "owned-key")
	})
}

@(test)
tooltip_leaving_on_expiry_frame_does_not_open :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tooltip_test_reset()
		tooltip_test_frame(true, 0)
		tooltip_test_frame(false, 0.3)
		testing.expect(t, !tooltip_test_open)
		testing.expect_value(t, tooltip_test_open_changes, 0)
	})
}

@(test)
tooltip_theme_base_sets_kinds :: proc(t: ^testing.T) {
	root := Tooltip_State{}
	testing.expect(t, tooltip_root_theme_base(&root).kind == .TOOLTIP)

	trigger := Tooltip_Trigger_State{}
	testing.expect(t, tooltip_trigger_theme_base(&trigger).kind == .TOOLTIP_TRIGGER)

	content := Tooltip_Content_Props_State{open = true}
	testing.expect(t, tooltip_content_props_theme_base(&content).kind == .TOOLTIP_CONTENT)
}

@(test)
tooltip_root_layout_registers_kind :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer tooltip_shutdown()
		tooltip_test_reset()

		widget_test_begin_layout()
		defer widget_test_end_frame()

		Tooltip({
			config = {id = "tip-kind", open = false},
			child = proc(_: Tooltip_State) {},
		})
		widget_test_finish_layout()

		expect_registered_id(t, "tip-kind")
		expect_layout_kind(t, "tip-kind", .TOOLTIP)
	})
}

@(test)
tooltip_content_skips_layout_when_closed :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer tooltip_shutdown()
		tooltip_test_reset()

		widget_test_begin_layout()
		defer widget_test_end_frame()

		Tooltip({
			config = {id = "tip-closed", open = false},
			child = proc(_: Tooltip_State) {
				Tooltip_Content({
					config = {width = set.Width(f32(80)), height = set.Height(f32(40))},
				})
			},
		})
		widget_test_finish_layout()

		_, ok := widget_test_layout_node("tip-closed/__tooltip_content")
		testing.expect(t, !ok)
	})
}

@(test)
tooltip_compound_content_layouts_when_open :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer tooltip_shutdown()
		tooltip_test_open = true

		widget_test_begin_layout()
		defer widget_test_end_frame()

		Tooltip({
			config = {id = "tip-open", open = true},
			child = proc(_: Tooltip_State) {
				Tooltip_Trigger({config = {id = "tip-open-trigger"}})
				Tooltip_Content({
					config = {width = set.Width(f32(120)), height = set.Height(f32(60))},
				})
			},
		})
		widget_test_finish_layout()

		found := false
		for &n in o.state.ui.layout.nodes {
			if n.space == .POPOVER && n.kind == .RECT {
				found = true
				break
			}
		}
		testing.expect(t, found)
	})
}

@(test)
tooltip_show_delay_opens_after_hover :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer tooltip_shutdown()
		tooltip_test_reset()

		widget_test_begin_layout()
		defer widget_test_end_frame()

		tooltip_test_tree(0.2)
		widget_test_finish_layout()
		tooltip_test_hover_trigger()
		widget_test_begin_draw()
		tooltip_test_tree(0.2)

		testing.expect(t, !tooltip_test_open)
		tooltip_test_advance_pending(0.25)
		tooltip_test_tree(0.2)

		testing.expect(t, tooltip_test_open)
		testing.expect(t, tooltip_test_open_changes >= 1)
	})
}

@(test)
tooltip_trigger_click_does_not_toggle :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer tooltip_shutdown()
		tooltip_test_reset()

		widget_test_begin_layout()
		defer widget_test_end_frame()

		tooltip_test_tree(10)
		widget_test_finish_layout()
		tooltip_test_hover_trigger()
		widget_test_begin_draw()
		o.w_ctx.left_mouse.pressed = true
		o.w_ctx.left_mouse.down = true
		tooltip_test_tree(10)
		o.w_ctx.left_mouse.pressed = false
		o.w_ctx.left_mouse.down = false
		o.w_ctx.left_mouse.released = true
		tooltip_test_tree(10)

		testing.expect(t, !tooltip_test_open)
	})
}

@(private)
tooltip_test_closed_a := false

@(private)
tooltip_test_opened_b := false

@(test)
tooltip_one_active_closes_other :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer tooltip_shutdown()

		tooltip_test_closed_a = false
		tooltip_test_opened_b = false

		tooltip_register_owner(
			"tip-a",
			{
				on_open_change = proc(open: bool) {
					if !open {
						tooltip_test_closed_a = true
					}
				},
				show_delay = 0.1,
				disabled = false,
			},
		)
		tooltip_register_owner(
			"tip-b",
			{
				on_open_change = proc(open: bool) {
					if open {
						tooltip_test_opened_b = true
					}
				},
				show_delay = 0.1,
				disabled = false,
			},
		)

		tooltip_global_active = tooltip_retain_key("tip-a")
		tooltip_open_key("tip-b")

		testing.expect(t, tooltip_test_closed_a)
		testing.expect(t, tooltip_test_opened_b)
	})
}
