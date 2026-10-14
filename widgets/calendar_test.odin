package oni_widgets

import o ".."
import set "../set"
import "core:testing"
import sdl "vendor:sdl3"

@(private)
calendar_test_select_count: int

@(private)
calendar_test_last_selection: Calendar_Selection

@(private)
calendar_test_month_count: int

@(private)
calendar_test_last_month: Calendar_Date

@(private)
calendar_test_day_click_count: int

@(private)
calendar_test_last_day: Calendar_Date

@(private)
calendar_test_on_select :: proc(selection: Calendar_Selection) {
	calendar_test_select_count += 1

	if calendar_test_last_selection.multiple != nil {
		delete(calendar_test_last_selection.multiple)
		calendar_test_last_selection.multiple = nil
	}

	calendar_test_last_selection = selection
	calendar_test_last_selection.multiple = nil

	if selection.mode == .MULTIPLE {
		calendar_test_last_selection.multiple = Calendar_Dates_Clone(
			selection.multiple,
			context.allocator,
		)
	}
}

@(private)
calendar_test_on_month :: proc(month: Calendar_Date) {
	calendar_test_month_count += 1
	calendar_test_last_month = month
}

@(private)
calendar_test_on_day_click :: proc(date: Calendar_Date) {
	calendar_test_day_click_count += 1
	calendar_test_last_day = date
}

@(private)
calendar_test_reset :: proc() {
	if calendar_test_last_selection.multiple != nil {
		delete(calendar_test_last_selection.multiple)
	}

	calendar_test_select_count = 0
	calendar_test_last_selection = {}
	calendar_test_month_count = 0
	calendar_test_last_month = {}
	calendar_test_day_click_count = 0
	calendar_test_last_day = {}
}

@(private)
calendar_test_fixed_today :: proc() -> Calendar_Date {
	return {year = 2024, month = 6, day = 15}
}

@(private)
calendar_test_month_child :: proc(_: Calendar_State) {
	Calendar_Month({config = {id = "calendar-test/month"}, month_index = 0})
}

@(private)
calendar_test_last_state: Calendar_State

@(private)
calendar_test_first_child_rect :: proc(root_id: string) -> (rect: o.Rect, ok: bool) {
	root, root_ok := o.layout_node_by_id(o.ui_id(root_id))

	if !root_ok || len(root.child_indices) < 1 {
		return {}, false
	}

	child := o.state.ui.layout.nodes[root.child_indices[0]]

	return child.rect, true
}

@(private)
calendar_test_day_rect_in_month :: proc(
	month: o.Rect,
	day_index: int,
	show_week_numbers: bool,
) -> o.Rect {
	day_size := CALENDAR_DEFAULT_DAY_SIZE
	gap := CALENDAR_DEFAULT_GAP
	week_w := show_week_numbers ? CALENDAR_WEEK_NUM_WIDTH + gap : 0
	row := day_index / CALENDAR_WEEK_DAYS
	col := day_index % CALENDAR_WEEK_DAYS
	x := month.x + week_w + f32(col) * (day_size + gap)
	y :=
		month.y +
		CALENDAR_NAV_HEIGHT +
		gap +
		CALENDAR_WEEKDAY_HEIGHT +
		gap +
		f32(row) * (day_size + gap)

	return {x = x, y = y, w = day_size, h = day_size}
}

@(private)
calendar_test_nav_next_rect :: proc(month: o.Rect) -> o.Rect {
	return {
		x = month.x + month.w - CALENDAR_NAV_HEIGHT,
		y = month.y,
		w = CALENDAR_NAV_HEIGHT,
		h = CALENDAR_NAV_HEIGHT,
	}
}

@(test)
calendar_part_outside_context_noop :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Calendar_Month({config = {id = "orphan-month"}, month_index = 0})
		Calendar_Grid({config = {}, month_index = 0})
		widget_test_finish_layout()
	})
}

@(test)
calendar_composable_registers_day_labels :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Calendar({
			config = {id = "calendar-parts"},
			mode = .SINGLE,
			month = {2024, 6, 1},
			today = calendar_test_fixed_today(),
			child = proc(_: Calendar_State) {
				Calendar_Month({config = {id = "calendar-parts/month"}, month_index = 0})
			},
		})
		widget_test_finish_layout()

		expect_registered_id(t, "calendar-parts/month/day-0-2024-06-01")
	})
}

@(test)
calendar_date_valid_and_compare :: proc(t: ^testing.T) {
	testing.expect(t, Calendar_Date_Valid({2024, 2, 29}))
	testing.expect(t, !Calendar_Date_Valid({2023, 2, 29}))
	testing.expect(t, !Calendar_Date_Valid({}))
	testing.expect(t, Calendar_Date_Equal({2024, 1, 1}, {2024, 1, 1}))
	testing.expect(t, Calendar_Date_Before({2024, 1, 1}, {2024, 1, 2}))
	testing.expect(t, Calendar_Date_After({2024, 3, 1}, {2024, 2, 28}))
}

@(test)
calendar_date_add_months_and_days :: proc(t: ^testing.T) {
	d := Calendar_Date{2024, 1, 31}
	feb := Calendar_Date_Add_Months(d, 1)
	testing.expect(t, Calendar_Date_Equal(feb, {2024, 2, 29}))

	prev := Calendar_Date_Add_Months({2024, 3, 15}, -1)
	testing.expect(t, Calendar_Date_Equal(prev, {2024, 2, 15}))

	next := Calendar_Date_Add_Days({2024, 2, 28}, 1)
	testing.expect(t, Calendar_Date_Equal(next, {2024, 2, 29}))

	year_back := Calendar_Date_Add_Months({2024, 6, 1}, -12)
	testing.expect(t, Calendar_Date_Equal(year_back, {2023, 6, 1}))
}

@(test)
calendar_weekday_and_week_number :: proc(t: ^testing.T) {
	// 2024-06-15 is Saturday.
	wd, ok := Calendar_Date_Weekday({2024, 6, 15})
	testing.expect(t, ok)
	testing.expect(t, wd == .SATURDAY)

	week, week_ok := Calendar_Week_Number({2024, 1, 1})
	testing.expect(t, week_ok)
	testing.expect(t, week >= 1 && week <= 53)
}

@(test)
calendar_range_normalize_and_contains :: proc(t: ^testing.T) {
	range := Calendar_Range_Normalize(
		{from = {2024, 6, 10}, to = {2024, 6, 5}, has_from = true, has_to = true},
	)
	testing.expect(t, Calendar_Date_Equal(range.from, {2024, 6, 5}))
	testing.expect(t, Calendar_Date_Equal(range.to, {2024, 6, 10}))
	testing.expect(t, Calendar_Range_Contains(range, {2024, 6, 7}))
	testing.expect(t, !Calendar_Range_Contains(range, {2024, 6, 11}))
}

@(test)
calendar_selection_helpers :: proc(t: ^testing.T) {
	next, has, changed := Calendar_Apply_Single_Click({}, false, {2024, 6, 1}, false)
	testing.expect(t, changed && has)
	testing.expect(t, Calendar_Date_Equal(next, {2024, 6, 1}))

	cleared, has_cleared, cleared_ok := Calendar_Apply_Single_Click(next, true, next, false)
	testing.expect(t, cleared_ok && !has_cleared)
	testing.expect(t, !Calendar_Date_Valid(cleared))

	_, _, required_block := Calendar_Apply_Single_Click(next, true, next, true)
	testing.expect(t, !required_block)

	multi, multi_changed := Calendar_Toggle_Multiple(
		nil,
		{2024, 6, 1},
		0,
		0,
		context.temp_allocator,
	)
	testing.expect(t, multi_changed)
	testing.expect_value(t, len(multi), 1)

	multi2, multi2_changed := Calendar_Toggle_Multiple(
		multi,
		{2024, 6, 1},
		0,
		0,
		context.temp_allocator,
	)
	testing.expect(t, multi2_changed)
	testing.expect_value(t, len(multi2), 0)

	range1, r1 := Calendar_Apply_Range_Click({}, {2024, 6, 1}, 0, 0)
	testing.expect(t, r1 && range1.has_from && !range1.has_to)

	range2, r2 := Calendar_Apply_Range_Click(range1, {2024, 6, 5}, 0, 0)
	testing.expect(t, r2 && range2.has_from && range2.has_to)
	testing.expect(t, Calendar_Date_Equal(range2.to, {2024, 6, 5}))
}

@(test)
calendar_build_month_grid_offsets :: proc(t: ^testing.T) {
	cells, ok := Calendar_Build_Month_Grid(
		{2024, 6, 1},
		.SUNDAY,
		{2024, 6, 15},
		true,
		nil,
		nil,
		nil,
		{},
		{},
	)
	testing.expect(t, ok)
	testing.expect(t, cells[0].outside || cells[0].date.day == 26)

	// June 2024 starts on Saturday → first cell is May 26 when week starts Sunday.
	testing.expect(t, Calendar_Date_Equal(cells[0].date, {2024, 5, 26}))
	testing.expect(t, cells[0].outside)

	// June 1 is index 6.
	testing.expect(t, Calendar_Date_Equal(cells[6].date, {2024, 6, 1}))
	testing.expect(t, !cells[6].outside)
	testing.expect(t, cells[20].today) // June 15 → index 6+14=20
}

@(test)
calendar_clamp_and_navigate_bounds :: proc(t: ^testing.T) {
	start := Calendar_Date{2024, 1, 1}
	end := Calendar_Date{2024, 12, 1}
	clamped := Calendar_Clamp_Month({2025, 2, 1}, start, end)
	testing.expect(t, Calendar_Date_Equal(clamped, {2024, 12, 1}))
	testing.expect(t, !Calendar_Can_Navigate({2024, 12, 1}, 1, start, end))
	testing.expect(t, Calendar_Can_Navigate({2024, 11, 1}, 1, start, end))

	// Multi-month span: next disabled when last visible month would leave end.
	testing.expect(t, Calendar_Can_Navigate({2024, 10, 1}, 1, start, end, 2))
	testing.expect(t, !Calendar_Can_Navigate({2024, 11, 1}, 1, start, end, 2))
	testing.expect(
		t,
		Calendar_Date_Equal(Calendar_Clamp_Month({2024, 12, 1}, start, end, 2), {2024, 11, 1}),
	)
}

@(test)
calendar_resolve_nav_bounds_from_dates :: proc(t: ^testing.T) {
	start, end := Calendar_Resolve_Nav_Bounds({}, {}, {2024, 6, 10}, {2024, 6, 20})
	testing.expect(t, Calendar_Date_Equal(start, {2024, 6, 1}))
	testing.expect(t, Calendar_Date_Equal(end, {2024, 6, 1}))
	testing.expect(t, !Calendar_Can_Navigate(start, -1, start, end))
	testing.expect(t, !Calendar_Can_Navigate(start, 1, start, end))

	// Tighter date window wins over looser month bounds.
	start, end = Calendar_Resolve_Nav_Bounds(
		{2024, 1, 1},
		{2024, 12, 1},
		{2024, 6, 10},
		{2024, 8, 5},
	)
	testing.expect(t, Calendar_Date_Equal(start, {2024, 6, 1}))
	testing.expect(t, Calendar_Date_Equal(end, {2024, 8, 1}))
	testing.expect(t, !Calendar_Can_Navigate(start, -1, start, end))
	testing.expect(t, Calendar_Can_Navigate(start, 1, start, end))
	testing.expect(t, !Calendar_Can_Navigate({2024, 8, 1}, 1, start, end))
}

@(test)
calendar_theme_base_sets_kind_and_tabbable :: proc(t: ^testing.T) {
	frame := Calendar_State {
		number_of_months = 1,
		content_width    = 300,
		content_height   = 320,
	}
	base := calendar_theme_base(&frame)

	testing.expect(t, base.kind == .CALENDAR)
	testing.expect(t, o.cfg_style_bool(base.tabbable))
}

@(test)
calendar_layout_registers_kind_and_tab_order :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Calendar({
			config = {id = "calendar-layout"},
			mode = .SINGLE,
			month = {2024, 6, 1},
			today = calendar_test_fixed_today(),
			child = proc(_: Calendar_State) {
				Calendar_Month({config = {id = "calendar-layout/month"}, month_index = 0})
			},
		})
		widget_test_finish_layout()

		expect_registered_id(t, "calendar-layout")
		expect_layout_kind(t, "calendar-layout", .CALENDAR)
		expect_in_tab_order(t, "calendar-layout", true)

		chrome := o.layout_calendar_result(o.ui_id("calendar-layout"))
		testing.expect(t, chrome != nil)

		if chrome != nil {
			testing.expect(t, chrome.active)
			testing.expect(t, len(chrome.months) >= 1)
			testing.expect(t, chrome.months[0].days[0].w > 0)
		}
	})
}

@(test)
calendar_disabled_not_tabbable :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Calendar(
			{
				config = {id = "calendar-disabled"},
				mode = .SINGLE,
				month = {2024, 6, 1},
				today = calendar_test_fixed_today(),
				disabled = true,
				child = calendar_test_month_child,
			},
		)
		widget_test_finish_layout()

		expect_in_tab_order(t, "calendar-disabled", false)
	})
}

@(test)
calendar_shutdown_clears_runtimes :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Calendar(
			{
				config = {id = "calendar-shutdown"},
				month = {2024, 6, 1},
				today = calendar_test_fixed_today(),
				child = calendar_test_month_child,
			},
		)
		widget_test_finish_layout()

		testing.expect(t, calendar_runtimes != nil)
		testing.expect(t, len(calendar_runtimes) > 0)

		calendar_shutdown()
		testing.expect(t, calendar_runtimes == nil)
	})
}

@(test)
calendar_unmount_clears_runtime :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Calendar({
			config = {id = "calendar-unmount"},
			month = {2024, 6, 1},
			today = calendar_test_fixed_today(),
			unmount = true,
			child = calendar_test_month_child,
			on_unmount = proc(_: Calendar_State) -> o.Mount {
				return .COMPLETED
			},
		})
		widget_test_finish_layout()

		_, ok := calendar_runtimes["calendar-unmount"]
		testing.expect(t, !ok)
	})
}

@(test)
calendar_keyboard_selects_focused_day :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		calendar_test_reset()
		defer calendar_test_reset()

		selected := Calendar_Date{}
		has_selected := false

		widget_test_begin_layout()
		defer widget_test_end_frame()

		props := Calendar_Props {
			config = {id = "calendar-keyboard"},
			mode = .SINGLE,
			month = {2024, 6, 1},
			today = calendar_test_fixed_today(),
			selected = selected,
			has_selected = has_selected,
			on_select = calendar_test_on_select,
			child = calendar_test_month_child,
		}
		Calendar(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("calendar-keyboard")
		o.w_ctx.keys[int(sdl.Scancode.SPACE)] = {
			down    = true,
			pressed = true,
		}
		Calendar(props)

		testing.expect_value(t, calendar_test_select_count, 1)
		testing.expect(t, calendar_test_last_selection.has_single)
		testing.expect(t, Calendar_Date_Valid(calendar_test_last_selection.single))
	})
}

@(test)
calendar_arrow_moves_focus_month :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		calendar_test_reset()
		defer calendar_test_reset()

		month := Calendar_Date{2024, 6, 1}

		widget_test_begin_layout()
		defer widget_test_end_frame()

		props := Calendar_Props {
			config = {id = "calendar-arrows"},
			mode = .SINGLE,
			month = month,
			on_month_change = calendar_test_on_month,
			today = calendar_test_fixed_today(),
			child = calendar_test_month_child,
		}
		Calendar(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("calendar-arrows")
		o.state.input.modifiers = {
			shift = true,
		}
		o.w_ctx.keys[int(sdl.Scancode.RIGHT)] = {
			down    = true,
			pressed = true,
		}
		Calendar(props)

		testing.expect_value(t, calendar_test_month_count, 1)
		testing.expect(t, Calendar_Date_Equal(calendar_test_last_month, {2024, 7, 1}))
	})
}

@(test)
calendar_pointer_selects_day :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			calendar_test_reset()
			defer calendar_test_reset()

			widget_test_begin_layout()
			defer widget_test_end_frame()

			props := Calendar_Props {
				config = {id = "calendar-pointer"},
				mode = .SINGLE,
				month = {2024, 6, 1},
				today = calendar_test_fixed_today(),
				on_select = calendar_test_on_select,
				on_day_click = calendar_test_on_day_click,
				child = calendar_test_month_child,
			}
			Calendar(props)
			widget_test_finish_layout()

			// Nested ui_ids are parent-scoped; resolve the month from the calendar child list.
			month_rect, month_ok := calendar_test_first_child_rect("calendar-pointer")
			testing.expect(t, month_ok && month_rect.w > 0 && month_rect.h > 0)

			// June 15 2024 is grid index 20 when week starts Sunday.
			day_rect := calendar_test_day_rect_in_month(month_rect, 20, false)

			widget_test_begin_draw()

			o.w_ctx.mouse_x = day_rect.x + day_rect.w * 0.5
			o.w_ctx.mouse_y = day_rect.y + day_rect.h * 0.5
			o.w_ctx.pointer_hit_valid = false
			o.widget_set_focused_id("calendar-pointer")

			o.w_ctx.left_mouse = {
				pressed = true,
				down    = true,
			}
			Calendar(props)
			testing.expect_value(t, calendar_test_select_count, 0)

			o.w_ctx.left_mouse = {
				pressed  = false,
				down     = false,
				released = true,
			}
			Calendar(props)

			testing.expect(t, calendar_test_day_click_count >= 1)
			testing.expect(t, calendar_test_select_count >= 1)
			testing.expect(
				t,
				Calendar_Date_Equal(calendar_test_last_selection.single, {2024, 6, 15}),
			)
		},
	)
}

@(test)
calendar_nav_button_click_advances_once :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			calendar_test_reset()
			defer calendar_test_reset()

			widget_test_begin_layout()
			defer widget_test_end_frame()

			props := Calendar_Props {
				config = {id = "calendar-nav-click"},
				mode = .SINGLE,
				month = {2024, 6, 1},
				today = calendar_test_fixed_today(),
				on_month_change = calendar_test_on_month,
				child = calendar_test_month_child,
			}
			Calendar(props)
			widget_test_finish_layout()

			month_rect, month_ok := calendar_test_first_child_rect("calendar-nav-click")
			testing.expect(t, month_ok && month_rect.w > 0 && month_rect.h > 0)
			next_r := calendar_test_nav_next_rect(month_rect)

			widget_test_begin_draw()

			o.w_ctx.mouse_x = next_r.x + next_r.w * 0.5
			o.w_ctx.mouse_y = next_r.y + next_r.h * 0.5
			o.w_ctx.pointer_hit_valid = false
			o.widget_set_focused_id("calendar-nav-click")

			o.w_ctx.left_mouse = {
				pressed = true,
				down    = true,
			}
			Calendar(props)
			testing.expect_value(t, calendar_test_month_count, 0)

			o.w_ctx.left_mouse = {
				pressed  = false,
				down     = false,
				released = true,
			}
			Calendar(props)

			testing.expect_value(t, calendar_test_month_count, 1)
			testing.expect(t, Calendar_Date_Equal(calendar_test_last_month, {2024, 7, 1}))
		},
	)
}

@(test)
calendar_disabled_matcher_blocks_select :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			calendar_test_reset()
			defer calendar_test_reset()

			widget_test_begin_layout()
			defer widget_test_end_frame()

			props := Calendar_Props {
				config = {id = "calendar-matcher"},
				mode = .SINGLE,
				month = {2024, 6, 1},
				today = calendar_test_fixed_today(),
				on_select = calendar_test_on_select,
				disabled_matcher = proc(date: Calendar_Date) -> bool {
					return date.day == 15
				},
				child = calendar_test_month_child,
			}
			Calendar(props)
			widget_test_finish_layout()
			widget_test_begin_draw()

			o.widget_set_focused_id("calendar-matcher")
			// Focus is today (15); Space should not select.
			rt := calendar_runtime_ensure("calendar-matcher")
			testing.expect(t, rt != nil)
			rt.focused_day = {2024, 6, 15}
			rt.focus_set = true

			o.w_ctx.keys[int(sdl.Scancode.SPACE)] = {
				down    = true,
				pressed = true,
			}
			Calendar(props)

			testing.expect_value(t, calendar_test_select_count, 0)
		},
	)
}

@(test)
calendar_multiple_and_range_modes :: proc(t: ^testing.T) {
	dates := []Calendar_Date{{2024, 6, 1}}
	next, changed := Calendar_Toggle_Multiple(dates, {2024, 6, 3}, 0, 2, context.temp_allocator)
	testing.expect(t, changed)
	testing.expect_value(t, len(next), 2)

	_, blocked := Calendar_Toggle_Multiple(next, {2024, 6, 4}, 0, 2, context.temp_allocator)
	testing.expect(t, !blocked)

	range, ok := Calendar_Apply_Range_Click(
		{from = {2024, 6, 1}, has_from = true},
		{2024, 6, 10},
		3,
		5,
	)
	testing.expect(t, !ok)

	range2, ok2 := Calendar_Apply_Range_Click(
		{from = {2024, 6, 1}, has_from = true},
		{2024, 6, 3},
		3,
		5,
	)
	testing.expect(t, ok2)
	testing.expect(t, range2.has_to)
	_ = range
}

@(test)
calendar_formatters :: proc(t: ^testing.T) {
	testing.expect(t, Calendar_Format_ISO({2024, 6, 5}, context.temp_allocator) == "2024-06-05")
	testing.expect(t, Calendar_Format_Month({2024, 6, 1}, context.temp_allocator) == "June 2024")
	testing.expect(t, Calendar_Format_Weekday(.SUNDAY, context.temp_allocator) == "Su")
	testing.expect(t, Calendar_Format_Day({2024, 6, 5}, context.temp_allocator) == "5")
	testing.expect(t, Calendar_Format_Long({2024, 6, 5}, context.temp_allocator) == "June 5, 2024")
	testing.expect(
		t,
		Calendar_Format_Medium({2024, 6, 5}, context.temp_allocator) == "Jun 5, 2024",
	)

	parsed, ok := Calendar_Parse_ISO("2024-06-05")
	testing.expect(t, ok)
	testing.expect(t, Calendar_Date_Equal(parsed, {2024, 6, 5}))

	_, bad := Calendar_Parse_ISO("2024-13-01")
	testing.expect(t, !bad)

	_, short := Calendar_Parse_ISO("2024-6-5")
	testing.expect(t, !short)
}

@(test)
calendar_start_end_date_blocks_select :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		calendar_test_reset()
		defer calendar_test_reset()

		widget_test_begin_layout()
		defer widget_test_end_frame()

		props := Calendar_Props {
			config = {id = "calendar-bounds"},
			mode = .SINGLE,
			month = {2024, 6, 1},
			today = calendar_test_fixed_today(),
			start_date = {2024, 6, 10},
			end_date = {2024, 6, 20},
			on_select = calendar_test_on_select,
			child = calendar_test_month_child,
		}
		Calendar(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		rt := calendar_runtime_ensure("calendar-bounds")
		testing.expect(t, rt != nil)
		rt.focused_day = {2024, 6, 5}
		rt.focus_set = true

		o.widget_set_focused_id("calendar-bounds")
		o.w_ctx.keys[int(sdl.Scancode.SPACE)] = {
			down    = true,
			pressed = true,
		}
		Calendar(props)
		testing.expect_value(t, calendar_test_select_count, 0)

		rt.focused_day = {2024, 6, 15}
		o.state.shortcuts.consumed_keys = {}
		o.w_ctx.keys[int(sdl.Scancode.SPACE)] = {
			down    = true,
			pressed = true,
		}
		Calendar(props)
		testing.expect_value(t, calendar_test_select_count, 1)
		testing.expect(t, Calendar_Date_Equal(calendar_test_last_selection.single, {2024, 6, 15}))
	})
}

@(private)
calendar_test_nav_bounds_child :: proc(state: Calendar_State) {
	calendar_test_last_state = state
	Calendar_Month({config = {id = "calendar-test/month"}, month_index = 0})

	// Handlers must no-op while can_go_* is false (same path as disabled nav buttons).
	calendar_nav_prev({})
	calendar_nav_next({})
}

@(test)
calendar_start_end_date_disables_month_nav :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		calendar_test_reset()
		defer calendar_test_reset()
		calendar_test_last_state = {}

		widget_test_begin_layout()
		defer widget_test_end_frame()

		props := Calendar_Props {
			config = {id = "calendar-nav-bounds"},
			mode = .SINGLE,
			month = {2024, 6, 1},
			today = calendar_test_fixed_today(),
			start_date = {2024, 6, 10},
			end_date = {2024, 6, 20},
			on_month_change = calendar_test_on_month,
			child = calendar_test_nav_bounds_child,
		}
		Calendar(props)
		widget_test_finish_layout()
		widget_test_begin_draw()
		Calendar(props)

		testing.expect(t, !calendar_test_last_state.can_go_prev)
		testing.expect(t, !calendar_test_last_state.can_go_next)
		testing.expect_value(t, calendar_test_month_count, 0)
	})
}

@(test)
calendar_matchers :: proc(t: ^testing.T) {
	testing.expect(t, Calendar_Match_Before({2024, 6, 1}, {2024, 6, 2}))
	testing.expect(t, Calendar_Match_After({2024, 6, 3}, {2024, 6, 2}))
	testing.expect(t, Calendar_Match_Weekend({2024, 6, 15}))
	testing.expect(t, !Calendar_Match_Weekend({2024, 6, 14}))
	testing.expect(t, Calendar_Match_Date({2024, 6, 1}, {2024, 6, 1}))
}

@(test)
calendar_default_child_registers_months :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Calendar({
			config = {id = "calendar-default-child"},
			mode = .SINGLE,
			month = {2024, 6, 1},
			today = calendar_test_fixed_today(),
		})
		widget_test_finish_layout()

		expect_registered_id(t, "calendar-default-child/month_0/day-0-2024-06-01")
		expect_registered_id(t, "calendar-default-child/month_0/nav/prev")
		expect_registered_id(t, "calendar-default-child/month_0/nav/next")
	})
}

@(test)
calendar_part_config_ids :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Calendar({
			config = {id = "calendar-ids"},
			mode = .SINGLE,
			month = {2024, 6, 1},
			today = calendar_test_fixed_today(),
			child = proc(_: Calendar_State) {
				Calendar_Navigation({config = {id = "calendar-ids/custom-nav"}})
				Calendar_Grid({config = {id = "calendar-ids/custom-grid"}, month_index = 0})
			},
		})
		widget_test_finish_layout()

		expect_registered_id(t, "calendar-ids/custom-nav/prev")
		expect_registered_id(t, "calendar-ids/custom-nav/next")
		expect_registered_id(t, "calendar-ids/custom-grid/day-0-2024-06-01")
	})
}

@(private)
calendar_test_day_builder_calls: int

@(private)
calendar_test_custom_day :: proc(state: Calendar_Day_State) {
	calendar_test_day_builder_calls += 1
	Calendar_Day(
		{
			config = {id = state.id},
			month_index = state.month_index,
			day_index = state.day_index,
		},
	)
}

@(test)
calendar_day_slot_replaces_grid_cells :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		calendar_test_reset()
		calendar_test_day_builder_calls = 0
		defer calendar_test_reset()

		widget_test_begin_layout()
		defer widget_test_end_frame()

		Calendar(
			{
				config = {id = "calendar-day-slot"},
				mode = .SINGLE,
				month = {2024, 6, 1},
				today = calendar_test_fixed_today(),
				hide_outside_days = true,
				day = calendar_test_custom_day,
				child = calendar_test_month_child,
			},
		)
		widget_test_finish_layout()

		testing.expect(t, calendar_test_day_builder_calls == 30)
		expect_registered_id(t, "calendar-test/month/day-0-2024-06-01")
	})
}

@(private)
calendar_test_disabled_child :: proc(state: Calendar_State) {
	calendar_test_last_state = state
	Calendar_Month({config = {id = "calendar-config-disabled/month"}, month_index = 0})
}

@(test)
calendar_config_disabled_blocks_interaction :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			calendar_test_reset()
			defer calendar_test_reset()
			calendar_test_last_state = {}

			widget_test_begin_layout()
			defer widget_test_end_frame()

			props := Calendar_Props {
				config = {id = "calendar-config-disabled", disabled = set.Disabled(true)},
				mode = .SINGLE,
				month = {2024, 6, 1},
				today = calendar_test_fixed_today(),
				on_select = calendar_test_on_select,
				on_month_change = calendar_test_on_month,
				on_day_click = calendar_test_on_day_click,
				child = calendar_test_disabled_child,
			}
			Calendar(props)
			expect_in_tab_order(t, "calendar-config-disabled", false)
			testing.expect(t, calendar_test_last_state.is_disabled)
			testing.expect(t, !calendar_test_last_state.can_go_prev)
			testing.expect(t, !calendar_test_last_state.can_go_next)
			widget_test_finish_layout()

			month_rect, month_ok := calendar_test_first_child_rect("calendar-config-disabled")
			testing.expect(t, month_ok && month_rect.w > 0 && month_rect.h > 0)
			day_rect := calendar_test_day_rect_in_month(month_rect, 20, false)
			next_r := calendar_test_nav_next_rect(month_rect)

			widget_test_begin_draw()

			o.widget_set_focused_id("calendar-config-disabled")
			o.w_ctx.keys[int(sdl.Scancode.SPACE)] = {
				down    = true,
				pressed = true,
			}
			Calendar(props)
			testing.expect_value(t, calendar_test_select_count, 0)
			testing.expect_value(t, calendar_test_day_click_count, 0)

			o.state.shortcuts.consumed_keys = {}
			o.w_ctx.keys[int(sdl.Scancode.SPACE)] = {}
			o.w_ctx.mouse_x = day_rect.x + day_rect.w * 0.5
			o.w_ctx.mouse_y = day_rect.y + day_rect.h * 0.5
			o.w_ctx.pointer_hit_valid = false
			o.w_ctx.left_mouse = {
				pressed = true,
				down    = true,
			}
			Calendar(props)
			o.w_ctx.left_mouse = {
				pressed  = false,
				down     = false,
				released = true,
			}
			Calendar(props)
			testing.expect_value(t, calendar_test_select_count, 0)
			testing.expect_value(t, calendar_test_day_click_count, 0)

			o.w_ctx.mouse_x = next_r.x + next_r.w * 0.5
			o.w_ctx.mouse_y = next_r.y + next_r.h * 0.5
			o.w_ctx.pointer_hit_valid = false
			o.w_ctx.left_mouse = {
				pressed = true,
				down    = true,
			}
			Calendar(props)
			o.w_ctx.left_mouse = {
				pressed  = false,
				down     = false,
				released = true,
			}
			Calendar(props)
			testing.expect_value(t, calendar_test_month_count, 0)
			testing.expect(t, calendar_test_last_state.is_disabled)
			testing.expect(t, !calendar_test_last_state.can_go_prev)
			testing.expect(t, !calendar_test_last_state.can_go_next)
		},
	)
}

@(test)
calendar_today_ring_matches_selection_focus_ring_width :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Rectangle(
			{
				config = {
					id = "cal-ring-host",
					width = set.Width(40),
					height = set.Height(40),
				},
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()

		layout_id := o.ui_id("cal-ring-host")
		frame := Calendar_State {
			is_focused = true,
		}
		event := widget_event(frame)
		rect := o.Rect {
			w = 36,
			h = 36,
		}

		clear(&o.batch_current().vertices)
		calendar_draw_day_cell(
			layout_id,
			rect,
			{today = true},
			&frame,
			event,
			{},
			false,
		)
		testing.expect(t, len(o.batch_current().vertices) >= 4)

		if len(o.batch_current().vertices) < 4 {
			return
		}

		today_border := o.batch_current().vertices[0].border
		expect_close(t, today_border[0], CALENDAR_DAY_RING_WIDTH)
		expect_close(t, today_border[1], CALENDAR_DAY_RING_WIDTH)
		expect_close(t, today_border[2], CALENDAR_DAY_RING_WIDTH)
		expect_close(t, today_border[3], CALENDAR_DAY_RING_WIDTH)

		clear(&o.batch_current().vertices)
		calendar_draw_day_cell(
			layout_id,
			rect,
			{selected = true, focused = true},
			&frame,
			event,
			{},
			false,
		)
		testing.expect(t, len(o.batch_current().vertices) >= 4)

		if len(o.batch_current().vertices) < 4 {
			return
		}

		// Selected fill is first; focus ring follows with the shared border width.
		focus_border := o.batch_current().vertices[4].border
		expect_close(t, focus_border[0], CALENDAR_DAY_RING_WIDTH)
		expect_close(t, focus_border[1], CALENDAR_DAY_RING_WIDTH)
		expect_close(t, focus_border[2], CALENDAR_DAY_RING_WIDTH)
		expect_close(t, focus_border[3], CALENDAR_DAY_RING_WIDTH)
		testing.expect_value(t, focus_border, today_border)
	})
}

@(test)
calendar_disabled_theme_keeps_neutral_border :: proc(t: ^testing.T) {
	focused := Calendar_State {
		is_focused = true,
	}
	focused_base := calendar_theme_base(&focused)
	testing.expect(t, o.cfg_style_bool(focused_base.tabbable))
	testing.expect(t, focused_base.border_color.mode == .Value)
	testing.expect(t, focused_base.border_color.value == o.Colors(o.Color.RING))

	disabled := Calendar_State {
		is_disabled = true,
		is_focused  = true,
	}
	disabled_base := calendar_theme_base(&disabled)
	testing.expect(t, !o.cfg_style_bool(disabled_base.tabbable))
	testing.expect(t, disabled_base.border_color.mode == .Value)
	testing.expect(t, disabled_base.border_color.value == o.Colors(o.Color.BORDER))
}

@(test)
calendar_disabled_day_chrome_skips_hover_and_rings :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Rectangle(
			{
				config = {
					id = "cal-disabled-chrome",
					width = set.Width(40),
					height = set.Height(40),
				},
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()

		layout_id := o.ui_id("cal-disabled-chrome")
		frame := Calendar_State {
			is_disabled = true,
			is_focused  = true,
		}
		event := widget_event(frame)
		rect := o.Rect {
			w = 36,
			h = 36,
		}

		clear(&o.batch_current().vertices)
		calendar_draw_day_cell(
			layout_id,
			rect,
			{today = true, focused = true},
			&frame,
			event,
			{},
			true,
		)
		testing.expect_value(t, len(o.batch_current().vertices), 0)

		clear(&o.batch_current().vertices)
		calendar_draw_day_cell(
			layout_id,
			rect,
			{selected = true, focused = true},
			&frame,
			event,
			{},
			true,
		)
		// Selection fill remains; no hover/focus/today rings.
		testing.expect(t, len(o.batch_current().vertices) >= 4)
		testing.expect(t, len(o.batch_current().vertices) < 8)
	})
}
