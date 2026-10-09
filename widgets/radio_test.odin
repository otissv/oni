package oni_widgets

import o ".."
import set "../set"
import "core:fmt"
import "core:testing"

@(private)
radio_test_value: string

@(private)
radio_test_changes: int

@(private)
radio_test_last: string

@(private)
radio_test_clicks: int

@(private)
radio_test_click_key: o.Scancode

@(private)
radio_test_focus: int

@(private)
radio_test_blur: int

@(private)
radio_test_child: int

@(private)
radio_test_write_back: bool

@(private)
radio_test_seen_name: string

@(private)
radio_test_seen_required: bool

@(private)
radio_test_seen_loop: bool

@(private)
radio_test_seen_orientation: Radio_Orientation

@(private)
radio_test_group_value: string

@(private)
radio_test_group_ok: bool

@(private)
radio_test_outer_changes: int

@(private)
radio_test_inner_changes: int

@(private)
radio_test_on_change :: proc(value: string) {
	radio_test_changes += 1
	radio_test_last = value

	if radio_test_write_back {
		radio_test_value = value
	}
}

@(private)
radio_test_on_click :: proc(event: Radio_Event) {
	radio_test_clicks += 1
	radio_test_click_key = event.key
}

@(private)
radio_test_on_focus :: proc(_: Radio_Event) {
	radio_test_focus += 1
}

@(private)
radio_test_on_blur :: proc(_: Radio_Event) {
	radio_test_blur += 1
}

@(private)
radio_test_child_proc :: proc(_: Radio_State) {
	radio_test_child += 1
}

@(private)
radio_test_reset :: proc() {
	radio_test_value = ""
	radio_test_changes = 0
	radio_test_last = ""
	radio_test_clicks = 0
	radio_test_click_key = {}
	radio_test_focus = 0
	radio_test_blur = 0
	radio_test_child = 0
	radio_test_write_back = false
	radio_test_seen_name = ""
	radio_test_seen_required = false
	radio_test_seen_loop = false
	radio_test_seen_orientation = .VERTICAL
	radio_test_group_value = ""
	radio_test_group_ok = false
	radio_test_outer_changes = 0
	radio_test_inner_changes = 0
}

@(private)
radio_test_item :: proc(id, value: string, disabled: bool) {
	Radio(
		{
			config = {id = id},
			value = value,
			disabled = disabled,
			on_click = radio_test_on_click,
			on_focus = radio_test_on_focus,
			on_blur = radio_test_on_blur,
		},
	)
}

@(private)
radio_test_abc :: proc(_: Radio_Group_State) {
	radio_test_group_value, radio_test_group_ok = Radio_Group_Get_Value()
	radio_test_item("a", "a", false)
	radio_test_item("b", "b", false)
	radio_test_item("c", "c", false)
}

@(private)
radio_test_group_abc :: proc() {
	Radio_Group(
		{
			config = {id = "rg"},
			value = radio_test_value,
			on_value_change = radio_test_on_change,
			child = radio_test_abc,
		},
	)
}

@(private)
radio_test_press :: proc(id: string, key: o.Scancode) {
	o.widget_set_focused_id(id)
	widget_test_press_shortcut(key)
}

@(private)
expect_tab_ids :: proc(t: ^testing.T, ids: []string, loc := #caller_location) {
	testing.expectf(
		t,
		o.w_ctx.tab_order != nil && len(o.w_ctx.tab_order) == len(ids),
		"tab len=%v want=%v",
		len(o.w_ctx.tab_order),
		len(ids),
		loc = loc,
	)

	if o.w_ctx.tab_order == nil || len(o.w_ctx.tab_order) != len(ids) {
		return
	}

	for id, i in ids {
		testing.expectf(t, o.w_ctx.tab_order[i] == id, "tab[%v]=%v want=%v", i, o.w_ctx.tab_order[i], id, loc = loc)
	}
}

@(test)
radio_loop_and_orientation_normalize :: proc(t: ^testing.T) {
	testing.expect(t, radio_loop_enabled(.ON))
	testing.expect(t, !radio_loop_enabled(.OFF))
	testing.expect(t, radio_loop_enabled(Radio_Loop(99)))
	testing.expect(t, radio_orientation_normalize(.HORIZONTAL) == .HORIZONTAL)
	testing.expect(t, radio_orientation_normalize(.VERTICAL) == .VERTICAL)
	testing.expect(t, radio_orientation_normalize(Radio_Orientation(99)) == .VERTICAL)
}

@(test)
radio_theme_base_is_circular_control :: proc(t: ^testing.T) {
	frame := Radio_State{checked = true}
	base := radio_theme_base(&frame)

	testing.expect(t, base.kind == .RADIO)
	testing.expect(t, !o.cfg_style_bool(base.tabbable))
	testing.expect(t, base.radius.mode == .Value)
	testing.expect(t, base.border.mode == .Value)
}

@(test)
radio_group_theme_follows_orientation :: proc(t: ^testing.T) {
	vertical := Radio_Group_State{orientation = .VERTICAL}
	horizontal := Radio_Group_State{orientation = .HORIZONTAL}
	vbase := radio_group_theme_base(&vertical)
	hbase := radio_group_theme_base(&horizontal)

	testing.expect(t, vbase.kind == .RADIO_GROUP)
	testing.expect(t, !o.cfg_style_bool(vbase.tabbable))
	testing.expect(t, hbase.gap_x.mode == .Value)
	testing.expect(t, vbase.gap_y.mode == .Value)
}

@(test)
radio_item_limit_rejects_overflow :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		testing.expect(t, radio_ctx_push({key = "cap", loop = true}))
		defer radio_ctx_pop()

		for i in 0 ..< RADIO_ITEMS_MAX {
			ok := radio_register_item(
				{value = fmt.tprintf("v%v", i), element_id = fmt.tprintf("e%v", i)},
			)
			testing.expect(t, ok)
		}

		testing.expect(t, !radio_register_item({value = "overflow", element_id = "overflow"}))
		testing.expect_value(t, radio_ctx_top().item_count, RADIO_ITEMS_MAX)
		testing.expect(t, !radio_register_item({value = "v0", element_id = "dup"}))
		testing.expect(t, !radio_register_item({value = "", element_id = "empty"}))
	})
}

@(test)
radio_group_layout_registers_one_tab_stop :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		radio_test_value = "b"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		radio_test_group_abc()
		expect_registered_id(t, "rg")
		expect_layout_kind(t, "rg", .RADIO_GROUP)
		testing.expect_value(t, radio_test_kind_count(.RADIO), 3)
		expect_in_tab_order(t, "a", false)
		expect_in_tab_order(t, "b", true)
		expect_in_tab_order(t, "c", false)
		expect_in_tab_order(t, "rg", false)
		testing.expect(t, radio_test_group_ok)
		testing.expect(t, radio_test_group_value == "b")
		widget_test_finish_layout()
		_, value_ok := Radio_Group_Get_Value()
		testing.expect(t, !value_ok)
	})
}

@(test)
radio_group_none_checked_tabs_first_enabled :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "rg"},
				child = proc(_: Radio_Group_State) {
					radio_test_item("a", "a", true)
					radio_test_item("b", "b", false)
					radio_test_item("c", "c", false)
				},
			},
		)
		expect_in_tab_order(t, "a", false)
		expect_in_tab_order(t, "b", true)
		expect_in_tab_order(t, "c", false)
		widget_test_finish_layout()
	})
}

@(test)
radio_checked_disabled_falls_back_to_first_enabled :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "rg"},
				value = "a",
				child = proc(_: Radio_Group_State) {
					radio_test_item("a", "a", true)
					radio_test_item("b", "b", false)
				},
			},
		)
		expect_in_tab_order(t, "a", false)
		expect_in_tab_order(t, "b", true)
		widget_test_finish_layout()
	})
}

@(test)
radio_group_disabled_has_no_tab_stop :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "rg"},
				value = "a",
				disabled = true,
				child = radio_test_abc,
			},
		)
		expect_in_tab_order(t, "a", false)
		expect_in_tab_order(t, "b", false)
		expect_in_tab_order(t, "c", false)
		widget_test_finish_layout()
	})
}

@(test)
radio_tab_stop_stays_with_checked_item_around_other_controls :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "rg"},
				value = "a",
				child = proc(_: Radio_Group_State) {
					radio_test_item("a", "a", false)
					Button({config = {id = "mid", tabbable = set.Tabbable(true)}})
					radio_test_item("b", "b", false)
				},
			},
		)
		expect_tab_ids(t, {"a", "mid"})
		widget_test_finish_layout()
	})
}

@(test)
radio_later_checked_item_replaces_provisional_tab_stop :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "rg"},
				value = "b",
				child = proc(_: Radio_Group_State) {
					radio_test_item("a", "a", false)
					Button({config = {id = "mid", tabbable = set.Tabbable(true)}})
					radio_test_item("b", "b", false)
				},
			},
		)
		expect_tab_ids(t, {"mid", "b"})
		widget_test_finish_layout()
	})
}

@(test)
radio_duplicate_and_empty_values_are_rejected :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "rg"},
				value = "a",
				child = proc(_: Radio_Group_State) {
					Radio({config = {id = "empty"}, value = ""})
					Radio({config = {id = "a1"}, value = "a"})
					Radio({config = {id = "a2"}, value = "a"})
					Radio({config = {id = "b"}, value = "b"})
				},
			},
		)
		snap := radio_snapshot_find("rg")
		testing.expect(t, snap != nil)

		if snap != nil {
			testing.expect_value(t, snap.count, 2)
			testing.expect(t, snap.items[0].value == "a")
			testing.expect(t, snap.items[1].value == "b")
		}

		expect_in_tab_order(t, "a1", true)
		expect_in_tab_order(t, "a2", false)
		expect_in_tab_order(t, "empty", false)
		widget_test_finish_layout()
	})
}

@(test)
radio_orphan_is_not_tabbable :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio(
			{
				config = {id = "orphan"},
				value = "a",
				on_click = radio_test_on_click,
			},
		)
		expect_in_tab_order(t, "orphan", false)
		expect_layout_kind(t, "orphan", .RADIO)
		widget_test_finish_layout()
		widget_test_begin_draw()
		o.widget_set_focused_id("orphan")
		o.w_ctx.keys[int(o.Scancode.SPACE)] = {down = true, pressed = true}
		Radio(
			{
				config = {id = "orphan"},
				value = "a",
				on_click = radio_test_on_click,
			},
		)
		testing.expect_value(t, radio_test_clicks, 0)
	})
}

@(test)
radio_space_checks_focused_item_and_enter_does_not :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		radio_test_group_abc()
		widget_test_finish_layout()
		widget_test_begin_draw()
		radio_test_press("a", .SPACE)
		radio_test_group_abc()
		testing.expect_value(t, radio_test_changes, 1)
		testing.expect(t, radio_test_last == "a")
		testing.expect_value(t, radio_test_clicks, 1)
		testing.expect(t, radio_test_click_key == .SPACE)

		radio_test_changes = 0
		radio_test_clicks = 0
		o.w_ctx.keys[int(o.Scancode.SPACE)] = {}
		radio_test_press("a", .RETURN)
		radio_test_group_abc()
		testing.expect_value(t, radio_test_changes, 0)
		testing.expect_value(t, radio_test_clicks, 0)
	})
}

@(test)
radio_space_on_checked_item_does_not_report_a_new_value :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		radio_test_value = "a"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		radio_test_group_abc()
		widget_test_finish_layout()
		widget_test_begin_draw()
		radio_test_press("a", .SPACE)
		radio_test_group_abc()
		testing.expect_value(t, radio_test_changes, 0)
		testing.expect_value(t, radio_test_clicks, 1)
	})
}

@(test)
radio_arrow_down_selects_next_and_moves_focus :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		radio_test_write_back = true
		radio_test_value = "a"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		radio_test_group_abc()
		widget_test_finish_layout()
		widget_test_begin_draw()
		radio_test_press("a", .DOWN)
		before := len(o.batch_current().vertices)
		radio_test_group_abc()
		testing.expect_value(t, len(o.batch_current().vertices) - before, 16)
		testing.expect_value(t, radio_test_changes, 1)
		testing.expect(t, radio_test_last == "b")
		testing.expect(t, o.w_ctx.focused_id == "b")
		testing.expect_value(t, radio_test_focus, 1)
		testing.expect_value(t, radio_test_blur, 1)
		testing.expect_value(t, radio_test_clicks, 0)
		widget_test_end_frame()

		widget_test_begin_layout()
		radio_test_group_abc()
		expect_in_tab_order(t, "b", true)
		expect_in_tab_order(t, "a", false)
		widget_test_finish_layout()
		widget_test_begin_draw()
		testing.expect(t, o.w_ctx.focused_id == "b")
	})
}

@(test)
radio_arrow_up_selects_previous :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		radio_test_value = "c"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		radio_test_group_abc()
		widget_test_finish_layout()
		widget_test_begin_draw()
		radio_test_press("c", .UP)
		before := len(o.batch_current().vertices)
		radio_test_group_abc()
		// Earlier items must paint the new disc in the same frame.
		testing.expect_value(t, len(o.batch_current().vertices) - before, 16)
		testing.expect(t, radio_test_last == "b")
		testing.expect(t, o.w_ctx.focused_id == "b")
		testing.expect_value(t, radio_test_focus, 1)
		testing.expect_value(t, radio_test_blur, 1)
	})
}

@(test)
radio_arrow_loops_and_can_stop_at_ends :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		radio_test_value = "c"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		radio_test_group_abc()
		widget_test_finish_layout()
		widget_test_begin_draw()
		radio_test_press("c", .DOWN)
		radio_test_group_abc()
		testing.expect(t, radio_test_last == "a")
		widget_test_end_frame()

		radio_test_reset()
		radio_test_value = "c"
		widget_test_begin_layout()
		Radio_Group(
			{
				config = {id = "rg"},
				value = radio_test_value,
				loop = .OFF,
				on_value_change = radio_test_on_change,
				child = radio_test_abc,
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()
		radio_test_press("c", .DOWN)
		Radio_Group(
			{
				config = {id = "rg"},
				value = radio_test_value,
				loop = .OFF,
				on_value_change = radio_test_on_change,
				child = radio_test_abc,
			},
		)
		testing.expect_value(t, radio_test_changes, 0)
		testing.expect(t, o.w_ctx.focused_id == "c")
	})
}

@(test)
radio_vertical_ignores_left_right :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		radio_test_value = "a"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		radio_test_group_abc()
		widget_test_finish_layout()
		widget_test_begin_draw()
		radio_test_press("a", .RIGHT)
		radio_test_group_abc()
		testing.expect_value(t, radio_test_changes, 0)
		testing.expect(t, o.w_ctx.focused_id == "a")
	})
}

@(test)
radio_horizontal_uses_left_right :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		radio_test_value = "b"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "rg"},
				value = radio_test_value,
				orientation = .HORIZONTAL,
				on_value_change = radio_test_on_change,
				child = radio_test_abc,
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()
		radio_test_press("b", .DOWN)
		Radio_Group(
			{
				config = {id = "rg"},
				value = radio_test_value,
				orientation = .HORIZONTAL,
				on_value_change = radio_test_on_change,
				child = radio_test_abc,
			},
		)
		testing.expect_value(t, radio_test_changes, 0)
		testing.expect(t, o.w_ctx.focused_id == "b")
		widget_test_end_frame()

		widget_test_begin_layout()
		Radio_Group(
			{
				config = {id = "rg"},
				value = radio_test_value,
				orientation = .HORIZONTAL,
				on_value_change = radio_test_on_change,
				child = radio_test_abc,
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()
		radio_test_press("b", .LEFT)
		Radio_Group(
			{
				config = {id = "rg"},
				value = radio_test_value,
				orientation = .HORIZONTAL,
				on_value_change = radio_test_on_change,
				child = radio_test_abc,
			},
		)
		testing.expect(t, radio_test_last == "a")
		testing.expect(t, o.w_ctx.focused_id == "a")
	})
}

@(test)
radio_arrows_skip_disabled_items :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		radio_test_value = "a"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "rg"},
				value = radio_test_value,
				on_value_change = radio_test_on_change,
				child = proc(_: Radio_Group_State) {
					radio_test_item("a", "a", false)
					radio_test_item("b", "b", true)
					radio_test_item("c", "c", false)
				},
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()
		radio_test_press("a", .DOWN)
		Radio_Group(
			{
				config = {id = "rg"},
				value = radio_test_value,
				on_value_change = radio_test_on_change,
				child = proc(_: Radio_Group_State) {
					radio_test_item("a", "a", false)
					radio_test_item("b", "b", true)
					radio_test_item("c", "c", false)
				},
			},
		)
		testing.expect(t, radio_test_last == "c")
		testing.expect(t, o.w_ctx.focused_id == "c")
	})
}

@(test)
radio_home_and_end_jump_ends :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		radio_test_value = "b"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		radio_test_group_abc()
		widget_test_finish_layout()
		widget_test_begin_draw()
		radio_test_press("b", .END)
		radio_test_group_abc()
		testing.expect(t, radio_test_last == "c")

		o.w_ctx.keys[int(o.Scancode.END)] = {}
		radio_test_value = "c"
		radio_test_press("c", .HOME)
		radio_test_group_abc()
		testing.expect(t, radio_test_last == "a")
		testing.expect(t, o.w_ctx.focused_id == "a")
	})
}

@(test)
radio_key_repeat_moves_one_item :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		radio_test_value = "a"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		radio_test_group_abc()
		widget_test_finish_layout()
		widget_test_begin_draw()
		o.widget_set_focused_id("a")
		o.w_ctx.keys[int(o.Scancode.DOWN)] = {down = true, repeat = true}
		radio_test_group_abc()
		testing.expect_value(t, radio_test_changes, 1)
		testing.expect(t, radio_test_last == "b")
	})
}

@(test)
radio_only_item_arrow_does_not_reselect :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "rg"},
				on_value_change = radio_test_on_change,
				child = proc(_: Radio_Group_State) {
					radio_test_item("a", "a", false)
				},
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()
		radio_test_press("a", .DOWN)
		Radio_Group(
			{
				config = {id = "rg"},
				on_value_change = radio_test_on_change,
				child = proc(_: Radio_Group_State) {
					radio_test_item("a", "a", false)
				},
			},
		)
		testing.expect_value(t, radio_test_changes, 0)
		testing.expect(t, o.w_ctx.focused_id == "a")
	})
}

@(test)
radio_pointer_release_selects_once :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()

		widget_test_begin_layout()
		radio_test_group_abc()
		widget_test_finish_layout()
		rects, n := radio_test_radio_rects()
		testing.expect_value(t, n, 3)
		rect := rects[1]
		testing.expect(t, rect.w > 0 && rect.h > 0)
		o.w_ctx.mouse_x = rect.x + rect.w * 0.5
		o.w_ctx.mouse_y = rect.y + rect.h * 0.5
		widget_test_begin_draw()
		o.w_ctx.left_mouse = {down = true, pressed = true}
		radio_test_group_abc()
		widget_test_end_frame()

		widget_test_begin_layout()
		radio_test_group_abc()
		widget_test_finish_layout()
		o.w_ctx.mouse_x = rect.x + rect.w * 0.5
		o.w_ctx.mouse_y = rect.y + rect.h * 0.5
		widget_test_begin_draw()
		o.w_ctx.left_mouse = {released = true}
		radio_test_group_abc()
		widget_test_end_frame()

		testing.expect_value(t, radio_test_changes, 1)
		testing.expect(t, radio_test_last == "b")
		testing.expect_value(t, radio_test_clicks, 1)
	})
}

@(test)
radio_pointer_on_checked_item_does_not_report_a_new_value :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		radio_test_value = "a"

		widget_test_begin_layout()
		radio_test_group_abc()
		widget_test_finish_layout()
		rects, n := radio_test_radio_rects()
		testing.expect_value(t, n, 3)
		rect := rects[0]
		testing.expect(t, rect.w > 0 && rect.h > 0)
		o.w_ctx.mouse_x = rect.x + rect.w * 0.5
		o.w_ctx.mouse_y = rect.y + rect.h * 0.5
		widget_test_begin_draw()
		o.w_ctx.left_mouse = {down = true, pressed = true}
		radio_test_group_abc()
		widget_test_end_frame()

		widget_test_begin_layout()
		radio_test_group_abc()
		widget_test_finish_layout()
		o.w_ctx.mouse_x = rect.x + rect.w * 0.5
		o.w_ctx.mouse_y = rect.y + rect.h * 0.5
		widget_test_begin_draw()
		o.w_ctx.left_mouse = {released = true}
		radio_test_group_abc()
		widget_test_end_frame()

		testing.expect_value(t, radio_test_changes, 0)
		testing.expect_value(t, radio_test_clicks, 1)
	})
}

@(test)
radio_disabled_blocks_keyboard_and_group_disable_blocks_all :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "rg", disabled = set.Disabled(true)},
				value = "a",
				on_value_change = radio_test_on_change,
				child = radio_test_abc,
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()
		radio_test_press("a", .SPACE)
		Radio_Group(
			{
				config = {id = "rg", disabled = set.Disabled(true)},
				value = "a",
				on_value_change = radio_test_on_change,
				child = radio_test_abc,
			},
		)
		testing.expect_value(t, radio_test_changes, 0)
	})
}

@(test)
radio_mounting_blocks_activation :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "rg"},
				on_value_change = radio_test_on_change,
				child = proc(_: Radio_Group_State) {
					Radio(
						{
							config = {id = "a"},
							value = "a",
							on_mount = proc(_: Radio_State) -> o.Mount {
								return .RUNNING
							},
						},
					)
				},
			},
		)
		expect_in_tab_order(t, "a", false)
		widget_test_finish_layout()
		widget_test_begin_draw()
		radio_test_press("a", .SPACE)
		Radio_Group(
			{
				config = {id = "rg"},
				on_value_change = radio_test_on_change,
				child = proc(_: Radio_Group_State) {
					Radio(
						{
							config = {id = "a"},
							value = "a",
							on_mount = proc(_: Radio_State) -> o.Mount {
								return .RUNNING
							},
						},
					)
				},
			},
		)
		testing.expect_value(t, radio_test_changes, 0)
	})
}

@(test)
radio_label_activation_selects :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		radio_test_group_abc()
		widget_test_finish_layout()
		widget_test_begin_draw()
		widget_request_label_activate("b")
		radio_test_group_abc()
		testing.expect_value(t, radio_test_changes, 1)
		testing.expect(t, radio_test_last == "b")
	})
}

@(test)
radio_nested_groups_are_independent :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "outer"},
				value = "o1",
				on_value_change = proc(value: string) {
					radio_test_outer_changes += 1
					radio_test_last = value
				},
				child = proc(_: Radio_Group_State) {
					radio_test_item("o1", "o1", false)
					radio_test_item("o2", "o2", false)
					Radio_Group(
						{
							config = {id = "inner"},
							value = "i1",
							on_value_change = proc(value: string) {
								radio_test_inner_changes += 1
								radio_test_value = value
							},
							child = proc(_: Radio_Group_State) {
								radio_test_item("i1", "i1", false)
								radio_test_item("i2", "i2", false)
							},
						},
					)
				},
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()
		radio_test_press("i1", .DOWN)
		Radio_Group(
			{
				config = {id = "outer"},
				value = "o1",
				on_value_change = proc(value: string) {
					radio_test_outer_changes += 1
					radio_test_last = value
				},
				child = proc(_: Radio_Group_State) {
					radio_test_item("o1", "o1", false)
					radio_test_item("o2", "o2", false)
					Radio_Group(
						{
							config = {id = "inner"},
							value = "i1",
							on_value_change = proc(value: string) {
								radio_test_inner_changes += 1
								radio_test_value = value
							},
							child = proc(_: Radio_Group_State) {
								radio_test_item("i1", "i1", false)
								radio_test_item("i2", "i2", false)
							},
						},
					)
				},
			},
		)
		testing.expect_value(t, radio_test_inner_changes, 1)
		testing.expect(t, radio_test_value == "i2")
		testing.expect_value(t, radio_test_outer_changes, 0)
		testing.expect(t, o.w_ctx.focused_id == "i2")
	})
}

@(test)
radio_group_exposes_form_metadata :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "rg"},
				value = "a",
				name = "plan",
				required = true,
				loop = .OFF,
				orientation = .HORIZONTAL,
				child = proc(state: Radio_Group_State) {
					radio_test_seen_name = state.name
					radio_test_seen_required = state.required
					radio_test_seen_loop = state.loop
					radio_test_seen_orientation = state.orientation
					radio_test_item("a", "a", false)
				},
			},
		)
		testing.expect(t, radio_test_seen_name == "plan")
		testing.expect(t, radio_test_seen_required)
		testing.expect(t, !radio_test_seen_loop)
		testing.expect(t, radio_test_seen_orientation == .HORIZONTAL)
		widget_test_finish_layout()
	})
}

@(test)
radio_auto_focus_lands_on_checked_item :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "rg", auto_focus = set.Bool(true)},
				value = "c",
				child = radio_test_abc,
			},
		)
		testing.expect(t, o.w_ctx.focused_id == "c")
		widget_test_finish_layout()
	})
}

@(test)
radio_custom_indicator_runs_only_when_checked :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "rg"},
				value = "b",
				child = proc(_: Radio_Group_State) {
					Radio({config = {id = "a"}, value = "a", child = radio_test_child_proc})
					Radio({config = {id = "b"}, value = "b", child = radio_test_child_proc})
				},
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()
		Radio_Group(
			{
				config = {id = "rg"},
				value = "b",
				child = proc(_: Radio_Group_State) {
					Radio({config = {id = "a"}, value = "a", child = radio_test_child_proc})
					Radio({config = {id = "b"}, value = "b", child = radio_test_child_proc})
				},
			},
		)
		testing.expect_value(t, radio_test_child, 2)
	})
}

@(test)
radio_builtin_indicator_emits_only_when_checked :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "off-group"},
				child = proc(_: Radio_Group_State) {
					Radio({config = {id = "off"}, value = "off"})
				},
			},
		)
		Radio_Group(
			{
				config = {id = "on-group"},
				value = "on",
				child = proc(_: Radio_Group_State) {
					Radio({config = {id = "on"}, value = "on"})
				},
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()
		before := len(o.batch_current().vertices)
		Radio_Group(
			{
				config = {id = "off-group"},
				child = proc(_: Radio_Group_State) {
					Radio({config = {id = "off"}, value = "off"})
				},
			},
		)
		off := len(o.batch_current().vertices) - before
		Radio_Group(
			{
				config = {id = "on-group"},
				value = "on",
				child = proc(_: Radio_Group_State) {
					Radio({config = {id = "on"}, value = "on"})
				},
			},
		)
		on := len(o.batch_current().vertices) - before - off

		// Border only while unchecked. Checked adds the inner disc.
		testing.expect_value(t, off, 4)
		testing.expect_value(t, on, 8)
	})
}

@(test)
radio_unmount_skips_layout_node :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "rg"},
				unmount = true,
				on_unmount = proc(_: Radio_Group_State) -> o.Mount {
					return .COMPLETED
				},
				child = radio_test_abc,
			},
		)
		_, ok := widget_test_layout_node("rg")
		testing.expect(t, !ok)
		widget_test_finish_layout()
	})
}

@(test)
radio_caller_keeps_ownership_of_value :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		held := "a"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Radio_Group(
			{
				config = {id = "rg"},
				value = held,
				on_value_change = radio_test_on_change,
				child = radio_test_abc,
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()
		radio_test_press("a", .DOWN)
		Radio_Group(
			{
				config = {id = "rg"},
				value = held,
				on_value_change = radio_test_on_change,
				child = radio_test_abc,
			},
		)
		testing.expect(t, held == "a")
		testing.expect(t, radio_test_last == "b")
	})
}

@(private)
radio_test_kind_count :: proc(kind: o.Widget_Kind) -> int {
	if o.state == nil {
		return 0
	}

	n := 0

	for &node in o.state.ui.layout.nodes {
		if node.kind == kind {
			n += 1
		}
	}

	return n
}

@(private)
radio_test_radio_rects :: proc() -> (rects: [8]o.Rect, n: int) {
	if o.state == nil {
		return
	}

	for &node in o.state.ui.layout.nodes {
		if node.kind != .RADIO || n >= len(rects) {
			continue
		}

		rects[n] = node.rect
		n += 1
	}

	for i in 1 ..< n {
		key := rects[i]
		j := i

		for j > 0 &&
		    (rects[j - 1].y > key.y || (rects[j - 1].y == key.y && rects[j - 1].x > key.x)) {
			rects[j] = rects[j - 1]
			j -= 1
		}

		rects[j] = key
	}

	return
}

@(test)
radio_config_override_preserves_kind :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
	props := Radio_Props {
		config = {id = "styled", background = set.Background(o.Color.ACCENT)},
		value = "a",
	}
	frame := Radio_State{}
	config := widget_config(props, &frame, radio_theme_base)
	testing.expect(t, config.kind == .RADIO)
	testing.expect_value(t, config.id, "styled")

	group_props := Radio_Group_Props {
		config = {id = "group-styled"},
		orientation = .HORIZONTAL,
	}
	group_frame := Radio_Group_State{orientation = .HORIZONTAL}
	group_config := widget_config(group_props, &group_frame, radio_group_theme_base)
	testing.expect(t, group_config.kind == .RADIO_GROUP)
	testing.expect_value(t, group_config.id, "group-styled")
	})
}

@(test)
radio_shutdown_drops_snapshots :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		radio_test_reset()
		widget_test_begin_layout()
		radio_test_group_abc()
		widget_test_finish_layout()
		testing.expect(t, radio_snapshot_count > 0)
		radio_shutdown()
		testing.expect_value(t, radio_snapshot_count, 0)
		testing.expect_value(t, radio_ctx_depth, 0)
		widget_test_end_frame()
	})
}
