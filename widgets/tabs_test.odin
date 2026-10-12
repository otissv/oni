package oni_widgets

import o ".."
import "core:fmt"
import "core:testing"

@(private)
tabs_test_value: string

@(private)
tabs_test_changes: int

@(private)
tabs_test_last: string

@(private)
tabs_test_clicks: int

@(private)
tabs_test_click_key: o.Scancode

@(private)
tabs_test_focus: int

@(private)
tabs_test_blur: int

@(private)
tabs_test_child: int

@(private)
tabs_test_write_back: bool

@(private)
tabs_test_group_value: string

@(private)
tabs_test_group_ok: bool

@(private)
tabs_test_content_a: int

@(private)
tabs_test_content_b: int

@(private)
tabs_test_on_change :: proc(value: string) {
	tabs_test_changes += 1
	tabs_test_last = value

	if tabs_test_write_back {
		tabs_test_value = value
	}
}

@(private)
tabs_test_on_click :: proc(event: Tabs_Trigger_Event) {
	tabs_test_clicks += 1
	tabs_test_click_key = event.key
}

@(private)
tabs_test_on_focus :: proc(_: Tabs_Trigger_Event) {
	tabs_test_focus += 1
}

@(private)
tabs_test_on_blur :: proc(_: Tabs_Trigger_Event) {
	tabs_test_blur += 1
}

@(private)
tabs_test_reset :: proc() {
	tabs_test_value = ""
	tabs_test_changes = 0
	tabs_test_last = ""
	tabs_test_clicks = 0
	tabs_test_click_key = {}
	tabs_test_focus = 0
	tabs_test_blur = 0
	tabs_test_child = 0
	tabs_test_write_back = false
	tabs_test_group_value = ""
	tabs_test_group_ok = false
	tabs_test_content_a = 0
	tabs_test_content_b = 0
}

@(private)
tabs_test_trigger :: proc(id, value: string, disabled: bool) {
	Tabs_Trigger(
		{
			config = {id = id},
			value = value,
			disabled = disabled,
			on_click = tabs_test_on_click,
			on_focus = tabs_test_on_focus,
			on_blur = tabs_test_on_blur,
			child = proc(_: Tabs_Trigger_State) {
				tabs_test_child += 1
			},
		},
	)
}

@(private)
tabs_test_list_abc :: proc(_: Tabs_List_State) {
	tabs_test_trigger("ta", "a", false)
	tabs_test_trigger("tb", "b", false)
	tabs_test_trigger("tc", "c", false)
}

@(private)
tabs_test_content_a_child :: proc(_: Tabs_Content_State) {
	tabs_test_content_a += 1
}

@(private)
tabs_test_content_b_child :: proc(_: Tabs_Content_State) {
	tabs_test_content_b += 1
}

@(private)
tabs_test_root_child :: proc(_: Tabs_State) {
	tabs_test_group_value, tabs_test_group_ok = Tabs_Get_Value()
	Tabs_List({config = {id = "tl"}, child = tabs_test_list_abc})
	Tabs_Content({config = {id = "ca"}, value = "a", child = tabs_test_content_a_child})
	Tabs_Content({config = {id = "cb"}, value = "b", child = tabs_test_content_b_child})
}

@(private)
tabs_test_root_abc :: proc() {
	Tabs(
		{
			config = {id = "tabs"},
			value = tabs_test_value,
			on_value_change = tabs_test_on_change,
			child = tabs_test_root_child,
		},
	)
}

@(private)
tabs_test_press :: proc(id: string, key: o.Scancode) {
	o.w_ctx.keys = {}
	o.state.shortcuts.consumed_keys = {}
	o.widget_set_focused_id(id)
	widget_test_press_shortcut(key)
}

@(private)
tabs_test_kind_count :: proc(kind: o.Widget_Kind) -> int {
	count := 0

	for node in o.state.ui.layout.nodes {
		if node.kind == kind {
			count += 1
		}
	}

	return count
}

@(test)
tabs_loop_orientation_variant_normalize :: proc(t: ^testing.T) {
	testing.expect(t, tabs_loop_enabled(.ON))
	testing.expect(t, !tabs_loop_enabled(.OFF))
	testing.expect(t, tabs_loop_enabled(Tabs_Loop(99)))
	testing.expect(t, tabs_orientation_normalize(.HORIZONTAL) == .HORIZONTAL)
	testing.expect(t, tabs_orientation_normalize(.VERTICAL) == .VERTICAL)
	testing.expect(t, tabs_orientation_normalize(Tabs_Orientation(99)) == .HORIZONTAL)
	testing.expect(t, tabs_variant_normalize(.DEFAULT) == .DEFAULT)
	testing.expect(t, tabs_variant_normalize(.LINE) == .LINE)
	testing.expect(t, tabs_variant_normalize(Tabs_List_Variant(99)) == .DEFAULT)
}

@(test)
tabs_theme_kinds_match_parts :: proc(t: ^testing.T) {
	root := Tabs_State{}
	list := Tabs_List_State{orientation = .HORIZONTAL, variant = .DEFAULT}
	trigger := Tabs_Trigger_State{active = true, variant = .DEFAULT}
	content := Tabs_Content_State{active = true}

	testing.expect(t, tabs_theme_base(&root).kind == .TABS)
	testing.expect(t, tabs_list_theme_base(&list).kind == .TABS_LIST)
	testing.expect(t, tabs_trigger_theme_base(&trigger).kind == .TABS_TRIGGER)
	testing.expect(t, tabs_content_theme_base(&content).kind == .TABS_CONTENT)
	testing.expect(t, !o.cfg_style_bool(tabs_theme_base(&root).tabbable))
}

@(test)
tabs_list_theme_follows_orientation_and_variant :: proc(t: ^testing.T) {
	horizontal := Tabs_List_State{orientation = .HORIZONTAL, variant = .DEFAULT}
	vertical := Tabs_List_State{orientation = .VERTICAL, variant = .DEFAULT}
	line := Tabs_List_State{orientation = .HORIZONTAL, variant = .LINE}
	hbase := tabs_list_theme_base(&horizontal)
	vbase := tabs_list_theme_base(&vertical)
	lbase := tabs_list_theme_base(&line)

	testing.expect(t, hbase.gap_x.mode == .Value)
	testing.expect(t, vbase.gap_y.mode == .Value)
	testing.expect(t, lbase.background.mode == .Value)
}

@(test)
tabs_trigger_limit_rejects_overflow :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		testing.expect(t, tabs_ctx_push({key = "cap", loop = true}))
		defer tabs_ctx_pop()

		for i in 0 ..< TABS_TRIGGERS_MAX {
			ok := tabs_register_trigger(
				{value = fmt.tprintf("v%v", i), element_id = fmt.tprintf("e%v", i)},
			)
			testing.expect(t, ok)
		}

		testing.expect(t, !tabs_register_trigger({value = "overflow", element_id = "overflow"}))
		testing.expect_value(t, tabs_ctx_top().trigger_count, TABS_TRIGGERS_MAX)
		testing.expect(t, !tabs_register_trigger({value = "v0", element_id = "dup"}))
		testing.expect(t, !tabs_register_trigger({value = "", element_id = "empty"}))
	})
}

@(test)
tabs_layout_registers_one_tab_stop_and_active_content :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tabs_test_reset()
		tabs_test_value = "b"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		tabs_test_root_abc()
		expect_registered_id(t, "tabs")
		expect_layout_kind(t, "tabs", .TABS)
		testing.expect_value(t, tabs_test_kind_count(.TABS_LIST), 1)
		testing.expect_value(t, tabs_test_kind_count(.TABS_TRIGGER), 3)
		expect_in_tab_order(t, "ta", false)
		expect_in_tab_order(t, "tb", true)
		expect_in_tab_order(t, "tc", false)
		expect_in_tab_order(t, "tabs", false)
		testing.expect(t, tabs_test_group_ok)
		testing.expect(t, tabs_test_group_value == "b")
		testing.expect_value(t, tabs_test_content_a, 0)
		testing.expect_value(t, tabs_test_content_b, 1)
		widget_test_finish_layout()
		_, value_ok := Tabs_Get_Value()
		testing.expect(t, !value_ok)
	})
}

@(test)
tabs_none_selected_tabs_first_enabled :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tabs_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Tabs(
			{
				config = {id = "tabs"},
				child = proc(_: Tabs_State) {
					Tabs_List(
						{
							config = {id = "tl"},
							child = proc(_: Tabs_List_State) {
								tabs_test_trigger("ta", "a", true)
								tabs_test_trigger("tb", "b", false)
								tabs_test_trigger("tc", "c", false)
							},
						},
					)
				},
			},
		)
		expect_in_tab_order(t, "ta", false)
		expect_in_tab_order(t, "tb", true)
		expect_in_tab_order(t, "tc", false)
		widget_test_finish_layout()
	})
}

@(test)
tabs_disabled_root_has_no_tab_stop :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tabs_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Tabs(
			{
				config = {id = "tabs"},
				value = "a",
				disabled = true,
				child = tabs_test_root_child,
			},
		)
		expect_in_tab_order(t, "ta", false)
		expect_in_tab_order(t, "tb", false)
		expect_in_tab_order(t, "tc", false)
		widget_test_finish_layout()
	})
}

@(test)
tabs_duplicate_and_empty_values_are_rejected :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tabs_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Tabs(
			{
				config = {id = "tabs"},
				value = "a",
				child = proc(_: Tabs_State) {
					Tabs_List(
						{
							config = {id = "tl"},
							child = proc(_: Tabs_List_State) {
								Tabs_Trigger({config = {id = "empty"}, value = ""})
								Tabs_Trigger({config = {id = "a1"}, value = "a"})
								Tabs_Trigger({config = {id = "a2"}, value = "a"})
								Tabs_Trigger({config = {id = "b"}, value = "b"})
							},
						},
					)
				},
			},
		)
		snap := tabs_snapshot_find("tabs")
		testing.expect(t, snap != nil)

		if snap != nil {
			testing.expect_value(t, snap.count, 2)
			testing.expect(t, snap.triggers[0].value == "a")
			testing.expect(t, snap.triggers[1].value == "b")
		}

		expect_in_tab_order(t, "a1", true)
		expect_in_tab_order(t, "a2", false)
		expect_in_tab_order(t, "empty", false)
		widget_test_finish_layout()
	})
}

@(test)
tabs_orphan_trigger_is_not_tabbable :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tabs_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Tabs_Trigger(
			{
				config = {id = "orphan"},
				value = "a",
				on_click = tabs_test_on_click,
			},
		)
		expect_in_tab_order(t, "orphan", false)
		expect_layout_kind(t, "orphan", .TABS_TRIGGER)
		widget_test_finish_layout()
		widget_test_begin_draw()
		o.widget_set_focused_id("orphan")
		o.w_ctx.keys[int(o.Scancode.SPACE)] = {down = true, pressed = true}
		Tabs_Trigger(
			{
				config = {id = "orphan"},
				value = "a",
				on_click = tabs_test_on_click,
			},
		)
		testing.expect_value(t, tabs_test_clicks, 0)
	})
}

@(test)
tabs_space_and_enter_activate_focused_trigger :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tabs_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		tabs_test_root_abc()
		widget_test_finish_layout()
		widget_test_begin_draw()
		tabs_test_press("ta", .SPACE)
		tabs_test_root_abc()
		testing.expect_value(t, tabs_test_changes, 1)
		testing.expect(t, tabs_test_last == "a")
		testing.expect_value(t, tabs_test_clicks, 1)
		testing.expect(t, tabs_test_click_key == .SPACE)

		tabs_test_changes = 0
		tabs_test_clicks = 0
		o.w_ctx.keys[int(o.Scancode.SPACE)] = {}
		tabs_test_press("tb", .RETURN)
		tabs_test_root_abc()
		testing.expect_value(t, tabs_test_changes, 1)
		testing.expect(t, tabs_test_last == "b")
		testing.expect_value(t, tabs_test_clicks, 1)
		testing.expect(t, tabs_test_click_key == .RETURN)
	})
}

@(test)
tabs_space_on_active_trigger_does_not_report_new_value :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tabs_test_reset()
		tabs_test_value = "a"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		tabs_test_root_abc()
		widget_test_finish_layout()
		widget_test_begin_draw()
		tabs_test_press("ta", .SPACE)
		tabs_test_root_abc()
		testing.expect_value(t, tabs_test_changes, 0)
		testing.expect_value(t, tabs_test_clicks, 1)
	})
}

@(test)
tabs_arrow_moves_focus_without_activate_by_default :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tabs_test_reset()
		tabs_test_value = "a"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		tabs_test_root_abc()
		widget_test_finish_layout()
		widget_test_begin_draw()
		tabs_test_press("ta", .RIGHT)
		tabs_test_root_abc()
		testing.expect_value(t, tabs_test_changes, 0)
		testing.expect(t, o.w_ctx.focused_id == "tb")
		testing.expect_value(t, tabs_test_focus, 1)
		testing.expect_value(t, tabs_test_blur, 1)
	})
}

@(test)
tabs_activate_on_focus_selects_with_arrows :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tabs_test_reset()
		tabs_test_write_back = true
		tabs_test_value = "a"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Tabs(
			{
				config = {id = "tabs"},
				value = tabs_test_value,
				on_value_change = tabs_test_on_change,
				child = proc(_: Tabs_State) {
					Tabs_List(
						{
							config = {id = "tl"},
							activate_on_focus = true,
							child = tabs_test_list_abc,
						},
					)
				},
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()
		tabs_test_press("ta", .RIGHT)
		Tabs(
			{
				config = {id = "tabs"},
				value = tabs_test_value,
				on_value_change = tabs_test_on_change,
				child = proc(_: Tabs_State) {
					Tabs_List(
						{
							config = {id = "tl"},
							activate_on_focus = true,
							child = tabs_test_list_abc,
						},
					)
				},
			},
		)
		testing.expect_value(t, tabs_test_changes, 1)
		testing.expect(t, tabs_test_last == "b")
		testing.expect(t, o.w_ctx.focused_id == "tb")
	})
}

@(test)
tabs_arrow_loops_and_can_stop_at_ends :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tabs_test_reset()
		tabs_test_value = "c"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		tabs_test_root_abc()
		widget_test_finish_layout()
		widget_test_begin_draw()
		tabs_test_press("tc", .RIGHT)
		tabs_test_root_abc()
		testing.expect(t, o.w_ctx.focused_id == "ta")
		widget_test_end_frame()

		tabs_test_reset()
		tabs_test_value = "c"
		widget_test_begin_layout()
		Tabs(
			{
				config = {id = "tabs"},
				value = tabs_test_value,
				loop = .OFF,
				on_value_change = tabs_test_on_change,
				child = tabs_test_root_child,
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()
		tabs_test_press("tc", .RIGHT)
		Tabs(
			{
				config = {id = "tabs"},
				value = tabs_test_value,
				loop = .OFF,
				on_value_change = tabs_test_on_change,
				child = tabs_test_root_child,
			},
		)
		testing.expect_value(t, tabs_test_changes, 0)
		testing.expect(t, o.w_ctx.focused_id == "tc")
	})
}

@(test)
tabs_horizontal_ignores_up_down :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tabs_test_reset()
		tabs_test_value = "a"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		tabs_test_root_abc()
		widget_test_finish_layout()
		widget_test_begin_draw()
		tabs_test_press("ta", .DOWN)
		tabs_test_root_abc()
		testing.expect_value(t, tabs_test_changes, 0)
		testing.expect(t, o.w_ctx.focused_id == "ta")
	})
}

@(test)
tabs_vertical_uses_up_down :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tabs_test_reset()
		tabs_test_value = "b"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Tabs(
			{
				config = {id = "tabs"},
				value = tabs_test_value,
				orientation = .VERTICAL,
				on_value_change = tabs_test_on_change,
				child = tabs_test_root_child,
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()
		tabs_test_press("tb", .RIGHT)
		Tabs(
			{
				config = {id = "tabs"},
				value = tabs_test_value,
				orientation = .VERTICAL,
				on_value_change = tabs_test_on_change,
				child = tabs_test_root_child,
			},
		)
		testing.expect(t, o.w_ctx.focused_id == "tb")
		widget_test_end_frame()

		widget_test_begin_layout()
		Tabs(
			{
				config = {id = "tabs"},
				value = tabs_test_value,
				orientation = .VERTICAL,
				on_value_change = tabs_test_on_change,
				child = tabs_test_root_child,
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()
		tabs_test_press("tb", .UP)
		Tabs(
			{
				config = {id = "tabs"},
				value = tabs_test_value,
				orientation = .VERTICAL,
				on_value_change = tabs_test_on_change,
				child = tabs_test_root_child,
			},
		)
		testing.expect(t, o.w_ctx.focused_id == "ta")
	})
}

@(test)
tabs_home_end_jump_to_enabled_ends :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tabs_test_reset()
		tabs_test_value = "b"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		tabs_test_root_abc()
		widget_test_finish_layout()
		widget_test_begin_draw()
		tabs_test_press("tb", .HOME)
		tabs_test_root_abc()
		testing.expect(t, o.w_ctx.focused_id == "ta")
		tabs_test_press("ta", .END)
		tabs_test_root_abc()
		testing.expect(t, o.w_ctx.focused_id == "tc")
	})
}

@(test)
tabs_content_force_mount_keeps_inactive_panel :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tabs_test_reset()
		tabs_test_value = "a"
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Tabs(
			{
				config = {id = "tabs"},
				value = tabs_test_value,
				child = proc(_: Tabs_State) {
					Tabs_List({config = {id = "tl"}, child = tabs_test_list_abc})
					Tabs_Content(
						{
							config = {id = "ca"},
							value = "a",
							child = tabs_test_content_a_child,
						},
					)
					Tabs_Content(
						{
							config = {id = "cb"},
							value = "b",
							force_mount = true,
							child = tabs_test_content_b_child,
						},
					)
				},
			},
		)
		testing.expect_value(t, tabs_test_content_a, 1)
		testing.expect_value(t, tabs_test_content_b, 1)
		expect_registered_id(t, "cb")
		widget_test_finish_layout()
	})
}

@(test)
tabs_shutdown_drops_snapshots :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		tabs_test_reset()
		widget_test_begin_layout()
		tabs_test_root_abc()
		testing.expect(t, tabs_snapshot_find("tabs") != nil)
		widget_test_finish_layout()
		widget_test_end_frame()

		tabs_shutdown()
		testing.expect(t, tabs_snapshot_find("tabs") == nil)
		testing.expect_value(t, tabs_snapshot_count, 0)
		testing.expect_value(t, tabs_ctx_depth, 0)
	})
}
