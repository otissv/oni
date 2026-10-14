package oni_widgets

import o ".."
import set "../set"
import "core:testing"

@(private)
date_picker_test_selected: Calendar_Date

@(private)
date_picker_test_has_selected: bool

@(private)
date_picker_test_range: Calendar_Range

@(private)
date_picker_test_open: bool

@(private)
date_picker_test_select_count: int

@(private)
date_picker_test_open_count: int

@(private)
date_picker_test_trigger_clicks: int

@(private)
date_picker_test_reset :: proc() {
	date_picker_test_selected = {}
	date_picker_test_has_selected = false
	date_picker_test_range = {}
	date_picker_test_open = false
	date_picker_test_select_count = 0
	date_picker_test_open_count = 0
	date_picker_test_trigger_clicks = 0
}

@(private)
date_picker_test_on_select :: proc(selection: Calendar_Selection) {
	date_picker_test_select_count += 1

	switch selection.mode {
	case .SINGLE:
		date_picker_test_selected = selection.single
		date_picker_test_has_selected = selection.has_single
	case .RANGE:
		date_picker_test_range = selection.range
	case .MULTIPLE, .NONE:
	}
}

@(private)
date_picker_test_on_open :: proc(open: bool) {
	date_picker_test_open = open
	date_picker_test_open_count += 1
}

@(private)
date_picker_test_on_trigger_click :: proc(_: Date_Picker_Trigger_Event) {
	date_picker_test_trigger_clicks += 1
}

@(private)
date_picker_test_trigger_child :: proc(_: Date_Picker_Trigger_State) {
	Date_Picker_Value({
		config = {id = "dp-value"},
		placeholder = "Pick a date",
	})
}

@(private)
date_picker_test_child :: proc(_: Date_Picker_State) {
	Date_Picker_Trigger({
		config = {
			id = "dp-trigger",
			width = set.Width(f32(220)),
			height = set.Height(f32(36)),
		},
		child = date_picker_test_trigger_child,
		on_click = date_picker_test_on_trigger_click,
	})
}

@(test)
date_picker_theme_base_sets_kind :: proc(t: ^testing.T) {
	frame := Date_Picker_State{}
	base := date_picker_theme_base(&frame)
	testing.expect(t, base.kind == .DATE_PICKER)
}

@(test)
date_picker_trigger_theme_base_sets_kind_and_tabbable :: proc(t: ^testing.T) {
	frame := Date_Picker_Trigger_State{}
	base := date_picker_trigger_theme_base(&frame)
	testing.expect(t, base.kind == .DATE_PICKER_TRIGGER)
	testing.expect(t, o.cfg_style_bool(base.tabbable))
}

@(test)
date_picker_value_theme_base_sets_kind :: proc(t: ^testing.T) {
	frame := Date_Picker_Value_State{}
	base := date_picker_value_theme_base(&frame)
	testing.expect(t, base.kind == .DATE_PICKER_VALUE)
}

@(test)
date_picker_input_theme_base_sets_kind :: proc(t: ^testing.T) {
	frame := Date_Picker_Input_State{}
	base := date_picker_input_theme_base(&frame)
	testing.expect(t, base.kind == .DATE_PICKER_INPUT)
}

@(test)
date_picker_format_selection_covers_modes :: proc(t: ^testing.T) {
	single := date_picker_format_selection_default(
		{mode = .SINGLE, single = {2024, 6, 5}, has_single = true},
		context.temp_allocator,
	)
	testing.expect(t, single == "June 5, 2024")

	range := date_picker_format_selection_default(
		{
			mode = .RANGE,
			range = {
				from = {2024, 1, 20},
				to = {2024, 2, 9},
				has_from = true,
				has_to = true,
			},
		},
		context.temp_allocator,
	)
	testing.expect(t, range == "Jan 20, 2024 - Feb 9, 2024")

	dates := []Calendar_Date{{2024, 6, 5}, {2024, 6, 6}}
	multi := date_picker_format_selection_default(
		{mode = .MULTIPLE, multiple = dates},
		context.temp_allocator,
	)
	testing.expect(t, multi == "2 selected")
}

@(private)
date_picker_test_find_trigger_and_popover_content :: proc(
	root: ^o.Layout_Node,
) -> (
	trigger: ^o.Layout_Node,
	content: ^o.Layout_Node,
) {
	if root == nil {
		return
	}

	stack: [64]int
	depth := 0

	for child_index in root.child_indices {
		if depth >= len(stack) {
			break
		}

		stack[depth] = child_index
		depth += 1
	}

	for depth > 0 {
		depth -= 1
		node := &o.state.ui.layout.nodes[stack[depth]]

		if node.kind == .DATE_PICKER_TRIGGER {
			trigger = node
		} else if node.space == .POPOVER &&
		   node.kind == .RECT &&
		   node.config.position == .ABSOLUTE {
			// Prefer the popover panel itself; nested calendar chrome also inherits
			// POPOVER space after flex composition.
			content = node
		}

		for child_index in node.child_indices {
			if depth >= len(stack) {
				break
			}

			stack[depth] = child_index
			depth += 1
		}
	}

	return
}

@(test)
date_picker_content_anchors_below_trigger :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		date_picker_test_reset()
		widget_test_begin_layout()
		defer {
			date_picker_shutdown()
			widget_test_end_frame()
		}

		Date_Picker({
			config = {
				id = "dp-anchor",
				x = set.F32(35),
				y = set.F32(60),
				width = set.Width(f32(240)),
			},
			mode = .SINGLE,
			open = true,
			on_open_change = date_picker_test_on_open,
			month = {2024, 6, 1},
			today = {2024, 6, 5},
			child = date_picker_test_child,
		})
		widget_test_finish_layout()

		root, root_ok := widget_test_layout_node("dp-anchor")
		testing.expect(t, root_ok)

		if !root_ok {
			return
		}

		trigger, content := date_picker_test_find_trigger_and_popover_content(root)
		testing.expect(t, trigger != nil)
		testing.expect(t, content != nil)

		if trigger == nil || content == nil {
			return
		}

		testing.expect(t, content.space == .POPOVER)
		testing.expect(t, content.config.position == .ABSOLUTE)

		widget_test_begin_draw()

		expect_close(t, content.rect.x, trigger.rect.x)
		expect_close(t, content.rect.y, trigger.rect.y + trigger.rect.h + DATE_PICKER_POPOVER_GAP_PX)
		testing.expect(t, content.rect.w > 0)
		testing.expect(t, content.rect.w < f32(o.state.dpi.logical_w) * 0.5)
		testing.expect(t, content.rect.w + 0.5 >= DATE_PICKER_DEFAULT_CALENDAR_WIDTH)
	})
}

@(test)
date_picker_range_two_months_sizes_panel :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		date_picker_test_reset()
		widget_test_begin_layout()
		defer {
			date_picker_shutdown()
			widget_test_end_frame()
		}

		Date_Picker({
			config = {
				id = "dp-range-2m",
				x = set.F32(20),
				y = set.F32(40),
				width = set.Width(f32(280)),
			},
			mode = .RANGE,
			open = true,
			number_of_months = 2,
			on_open_change = date_picker_test_on_open,
			month = {2024, 6, 1},
			today = {2024, 6, 5},
			child = date_picker_test_child,
		})
		widget_test_finish_layout()

		root, root_ok := widget_test_layout_node("dp-range-2m")
		testing.expect(t, root_ok)

		if !root_ok {
			return
		}

		_, content := date_picker_test_find_trigger_and_popover_content(root)
		testing.expect(t, content != nil)

		if content == nil {
			return
		}

		widget_test_begin_draw()

		calendar: ^o.Layout_Node

		for &node in o.state.ui.layout.nodes {
			if node.kind == .CALENDAR {
				calendar = &node

				break
			}
		}

		testing.expect(t, calendar != nil)

		if calendar == nil {
			return
		}

		expected_w := date_picker_default_calendar_width(2, {}, {}, false)
		testing.expect(t, expected_w > DATE_PICKER_DEFAULT_CALENDAR_WIDTH)
		expect_close(t, calendar.rect.w, expected_w)
		testing.expect(t, content.rect.w + 0.5 >= expected_w)

		chrome := o.layout_calendar_result(calendar.ui_id)
		testing.expect(t, chrome != nil)

		if chrome == nil {
			return
		}

		testing.expect(t, len(chrome.months) == 2)

		if len(chrome.months) < 2 {
			return
		}

		testing.expect(t, chrome.months[1].origin.x > chrome.months[0].origin.x)
		testing.expect(
			t,
			chrome.months[1].origin.x + CALENDAR_DEFAULT_DAY_SIZE <=
			calendar.rect.x + calendar.rect.w + 0.5,
		)
	})
}

@(test)
date_picker_layout_registers_compound_kinds :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		date_picker_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Date_Picker({
			config = {
				id = "dp",
				width = set.Width(f32(240)),
			},
			mode = .SINGLE,
			open = true,
			on_open_change = date_picker_test_on_open,
			selected = {2024, 6, 5},
			has_selected = true,
			month = {2024, 6, 1},
			today = {2024, 6, 5},
			child = date_picker_test_child,
		})
		widget_test_finish_layout()

		expect_registered_id(t, "dp")
		expect_layout_kind(t, "dp", .DATE_PICKER)
		expect_registered_id(t, "dp-trigger")
		expect_registered_id(t, "dp-value")
		expect_registered_id(t, "dp/__date_picker_popover")
		expect_registered_id(t, "dp/__date_picker_popover/__popover_content")
		expect_registered_id(t, "dp/calendar")
		expect_registered_id(t, "dp/calendar/month_0/nav/prev")
		expect_registered_id(t, "dp/calendar/month_0/day-0-2024-06-01")

		root, root_ok := widget_test_layout_node("dp")
		testing.expect(t, root_ok)

		if !root_ok {
			return
		}

		testing.expect(t, len(root.child_indices) >= 1)

		if len(root.child_indices) < 1 {
			return
		}

		popover := &o.state.ui.layout.nodes[root.child_indices[0]]
		testing.expect(t, popover.kind == .POPOVER)

		trigger_ok := false

		for child_index in popover.child_indices {
			child := &o.state.ui.layout.nodes[child_index]

			if child.kind == .DATE_PICKER_TRIGGER {
				trigger_ok = true

				break
			}
		}

		testing.expect(t, trigger_ok)
	})
}

@(test)
date_picker_trigger_tabbable_registers_in_tab_order :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Date_Picker({
			config = {id = "dp-tab"},
			child = proc(_: Date_Picker_State) {
				Date_Picker_Trigger({config = {id = "dp-tab-trigger"}})
			},
		})
		expect_in_tab_order(t, "dp-tab-trigger", true)
		widget_test_finish_layout()
	})
}

@(test)
date_picker_open_toggle_notifies_callback :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		date_picker_test_reset()
		defer date_picker_shutdown()

		date_picker_ctx_push(
			{
				picker_key = "toggle",
				open = false,
				mode = .SINGLE,
				on_open_change = date_picker_test_on_open,
			},
		)
		defer date_picker_ctx_pop()

		date_picker_toggle_open()
		testing.expect(t, Date_Picker_Is_Open())
		testing.expect(t, date_picker_test_open)
		testing.expect_value(t, date_picker_test_open_count, 1)

		date_picker_set_open(false)
		testing.expect(t, !Date_Picker_Is_Open())
		testing.expect(t, !date_picker_test_open)
		testing.expect_value(t, date_picker_test_open_count, 2)
	})
}

@(test)
date_picker_select_single_closes_and_notifies :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		date_picker_test_reset()
		defer date_picker_shutdown()

		date_picker_ctx_push(
			{
				picker_key = "pick-single",
				open = true,
				mode = .SINGLE,
				on_select = date_picker_test_on_select,
			},
		)
		defer date_picker_ctx_pop()

		Date_Picker_Notify_Select(
			{mode = .SINGLE, single = {2024, 6, 5}, has_single = true},
		)
		testing.expect_value(t, date_picker_test_select_count, 1)
		testing.expect(t, date_picker_test_has_selected)
		testing.expect(t, Calendar_Date_Equal(date_picker_test_selected, {2024, 6, 5}))
		testing.expect(t, !Date_Picker_Is_Open())
	})
}

@(test)
date_picker_select_range_closes_when_complete :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		date_picker_test_reset()
		defer date_picker_shutdown()

		date_picker_ctx_push(
			{
				picker_key = "pick-range",
				open = true,
				mode = .RANGE,
				on_select = date_picker_test_on_select,
			},
		)
		defer date_picker_ctx_pop()

		Date_Picker_Notify_Select(
			{
				mode = .RANGE,
				range = {from = {2024, 1, 20}, has_from = true},
			},
		)
		testing.expect(t, Date_Picker_Is_Open())

		Date_Picker_Notify_Select(
			{
				mode = .RANGE,
				range = {
					from = {2024, 1, 20},
					to = {2024, 2, 9},
					has_from = true,
					has_to = true,
				},
			},
		)
		testing.expect(t, !Date_Picker_Is_Open())
		testing.expect(t, date_picker_test_range.has_to)
	})
}

@(test)
date_picker_keep_open_prevents_close_on_select :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		date_picker_test_reset()
		defer date_picker_shutdown()

		date_picker_ctx_push(
			{
				picker_key = "keep",
				open = true,
				mode = .SINGLE,
				keep_open = true,
				on_select = date_picker_test_on_select,
			},
		)
		defer date_picker_ctx_pop()

		Date_Picker_Notify_Select(
			{mode = .SINGLE, single = {2024, 6, 5}, has_single = true},
		)
		testing.expect(t, Date_Picker_Is_Open())
	})
}

@(test)
date_picker_shutdown_clears_runtimes :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		rt := date_picker_runtime_ensure("shutdown-key")
		testing.expect(t, rt != nil)

		if rt == nil {
			return
		}

		date_picker_runtime_set_string(&rt.input_text, "2024-06-05")
		testing.expect(t, date_picker_runtimes != nil)
		testing.expect(t, len(date_picker_runtimes) >= 1)

		date_picker_shutdown()
		testing.expect(t, date_picker_runtimes == nil)
		testing.expect_value(t, date_picker_ctx_depth, 0)
	})
}

@(test)
date_picker_unmount_clears_runtime :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		_ = date_picker_runtime_ensure("dp-unmount")
		testing.expect(t, date_picker_runtimes != nil)

		Date_Picker({
			config = {id = "dp-unmount"},
			unmount = true,
			on_unmount = proc(_: Date_Picker_State) -> o.Mount {
				return .COMPLETED
			},
			child = proc(_: Date_Picker_State) {
				Date_Picker_Trigger({config = {id = "dp-unmount-trigger"}})
			},
		})
		widget_test_finish_layout()

		_, ok := date_picker_runtimes["dp-unmount"]
		testing.expect(t, !ok)
	})
}

@(test)
date_picker_escape_closes_open_popover :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		date_picker_test_reset()
		defer date_picker_shutdown()

		date_picker_ctx_push(
			{
				picker_key = "esc",
				open = true,
				mode = .SINGLE,
				on_open_change = date_picker_test_on_open,
			},
		)
		defer date_picker_ctx_pop()

		o.w_ctx.keys[int(o.Scancode.ESCAPE)] = {pressed = true, down = true}
		date_picker_handle_keys()
		testing.expect(t, !date_picker_test_open)
	})
}

@(test)
date_picker_value_shows_placeholder_and_selection :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		date_picker_ctx_push(
			{
				picker_key = "val",
				mode = .SINGLE,
				has_selected = false,
			},
		)
		text, has := date_picker_resolve_value_text("Pick a date")
		testing.expect(t, !has)
		testing.expect(t, text == "Pick a date")
		date_picker_ctx_pop()

		date_picker_ctx_push(
			{
				picker_key = "val2",
				mode = .SINGLE,
				selected = {2024, 6, 5},
				has_selected = true,
			},
		)
		text, has = date_picker_resolve_value_text("Pick a date")
		testing.expect(t, has)
		testing.expect(t, text == "June 5, 2024")
		date_picker_ctx_pop()
	})
}

@(test)
date_picker_input_parses_iso_on_commit :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		date_picker_test_reset()
		defer date_picker_shutdown()

		date_picker_ctx_push(
			{
				picker_key = "input",
				mode = .SINGLE,
				open = true,
				on_select = date_picker_test_on_select,
			},
		)
		defer date_picker_ctx_pop()

		ok := date_picker_input_commit_text("2024-06-05")
		testing.expect(t, ok)
		testing.expect(t, date_picker_test_has_selected)
		testing.expect(t, Calendar_Date_Equal(date_picker_test_selected, {2024, 6, 5}))

		ok = date_picker_input_commit_text("not-a-date")
		testing.expect(t, !ok)
	})
}

@(test)
date_picker_input_layout_registers_field :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Date_Picker({
			config = {id = "dpi"},
			mode = .SINGLE,
			open = true,
			on_open_change = date_picker_test_on_open,
			month = {2024, 6, 1},
			today = {2024, 6, 5},
			child = proc(_: Date_Picker_State) {
				Date_Picker_Input({
					config = {id = "dpi-input", width = set.Width(f32(220))},
					placeholder = "YYYY-MM-DD",
				})
			},
		})
		widget_test_finish_layout()

		expect_registered_id(t, "dpi")
		expect_layout_kind(t, "dpi", .DATE_PICKER)
		expect_registered_id(t, "dpi-input")
		expect_registered_id(t, "dpi-input/field")
		expect_registered_id(t, "dpi/__date_picker_popover")
		expect_registered_id(t, "dpi/__date_picker_popover/__popover_content")

		root, root_ok := widget_test_layout_node("dpi")
		testing.expect(t, root_ok)

		if !root_ok {
			return
		}

		testing.expect(t, len(root.child_indices) >= 1)

		if len(root.child_indices) < 1 {
			return
		}

		popover := &o.state.ui.layout.nodes[root.child_indices[0]]
		testing.expect(t, popover.kind == .POPOVER)

		input_ok := false

		for child_index in popover.child_indices {
			child := &o.state.ui.layout.nodes[child_index]

			if child.kind == .DATE_PICKER_INPUT {
				input_ok = true

				break
			}
		}

		testing.expect(t, input_ok)
	})
}

@(test)
date_picker_trigger_click_toggles_open :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		date_picker_test_reset()
		defer date_picker_shutdown()

		date_picker_ctx_push(
			{
				picker_key = "click",
				open = false,
				mode = .SINGLE,
				on_open_change = date_picker_test_on_open,
				trigger_user_click = date_picker_test_on_trigger_click,
			},
		)
		defer date_picker_ctx_pop()

		date_picker_trigger_on_click({})
		testing.expect(t, date_picker_ctx_top().open)
		testing.expect(t, date_picker_test_open)
		testing.expect_value(t, date_picker_test_trigger_clicks, 1)
	})
}

@(test)
date_picker_effective_mode_defaults_none_to_single :: proc(t: ^testing.T) {
	testing.expect(t, date_picker_effective_mode(.NONE) == .SINGLE)
	testing.expect(t, date_picker_effective_mode(.RANGE) == .RANGE)
}
