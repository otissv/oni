package oni_widgets

import o ".."
import set "../set"
import "core:fmt"

Calendar_Month_Part_Config :: o.Widget_Config

/*
Index of the visible month relative to the root `month` (0 = first month).
*/
Calendar_Month_Part_Props :: struct {
	config:      Calendar_Month_Part_Config,
	month_index: int,
}

Calendar_Navigation_Config :: o.Widget_Config
Calendar_Navigation_Props :: struct {
	config: Calendar_Navigation_Config,
}

Calendar_Caption_Config :: o.Widget_Config
Calendar_Caption_Props :: struct {
	config:      Calendar_Caption_Config,
	month_index: int,
}

Calendar_Weekdays_Config :: o.Widget_Config
Calendar_Weekdays_Props :: struct {
	config:      Calendar_Weekdays_Config,
	month_index: int,
}

Calendar_Week_Numbers_Config :: o.Widget_Config
Calendar_Week_Numbers_Props :: struct {
	config:      Calendar_Week_Numbers_Config,
	month_index: int,
}

Calendar_Grid_Config :: o.Widget_Config
Calendar_Grid_Props :: struct {
	config:      Calendar_Grid_Config,
	month_index: int,
}

@(private)
calendar_part_month_index_ok :: proc(month_index: int) -> bool {
	if !calendar_ctx_ok() {
		return false
	}

	ctx := calendar_ctx_top()

	return month_index >= 0 && month_index < ctx.number_of_months
}

@(private)
calendar_part_month_origin :: proc(month_index: int) -> (origin: o.Vec2, ok: bool) {
	if !calendar_part_month_index_ok(month_index) {
		return {}, false
	}

	ctx := calendar_ctx_top()

	if chrome := o.layout_calendar_result(ctx.layout_id); chrome != nil {
		if month_index >= 0 && month_index < len(chrome.months) {
			return chrome.months[month_index].origin, true
		}

		return {}, false
	}

	// Provisional placement is layout-only; draw must use finalized chrome.
	if o.ui_pass() != .Layout {
		return {}, false
	}

	root := o.Rect{}
	origin = calendar_month_origin(
		root,
		month_index,
		ctx.number_of_months,
		ctx.day_size,
		ctx.gap,
		ctx.show_week_numbers,
	)

	return origin, true
}

@(private)
calendar_part_month_chrome :: proc(month_index: int) -> (^o.Layout_Calendar_Month, bool) {
	if !calendar_part_month_index_ok(month_index) {
		return nil, false
	}

	ctx := calendar_ctx_top()
	chrome := o.layout_calendar_result(ctx.layout_id)

	if chrome == nil || month_index < 0 || month_index >= len(chrome.months) {
		return nil, false
	}

	return &chrome.months[month_index], true
}

@(private)
calendar_part_selected_matcher :: proc(date: Calendar_Date) -> bool {
	ctx := calendar_ctx_top()

	if !ctx.active {
		return false
	}

	return calendar_day_is_selected(ctx.selection, date)
}

@(private)
calendar_nav_prev_label_child :: proc(_: Button_State) {
	ctx := calendar_ctx_top()

	if !ctx.active {
		return
	}

	Text(
		{
			config = {
				id = fmt.tprintf("%s/prev-label", ctx.key),
				text = "<",
				font_size = set.F32(16),
				tabbable = set.Tabbable(false),
			},
		},
	)
}

@(private)
calendar_nav_next_label_child :: proc(_: Button_State) {
	ctx := calendar_ctx_top()

	if !ctx.active {
		return
	}

	Text(
		{
			config = {
				id = fmt.tprintf("%s/next-label", ctx.key),
				text = ">",
				font_size = set.F32(16),
				tabbable = set.Tabbable(false),
			},
		},
	)
}

/*
Previous / next month controls for the first visible month.
*/
Calendar_Navigation :: proc(props: Calendar_Navigation_Props) {
	if !calendar_ctx_ok() {
		return
	}

	ctx := calendar_ctx_top()
	origin, ok := calendar_part_month_origin(0)

	if !ok {
		return
	}

	prev_r, next_r: o.Rect

	if month_chrome, has_chrome := calendar_part_month_chrome(0); has_chrome {
		prev_r = month_chrome.prev
		next_r = month_chrome.next
	} else {
		month_w := calendar_month_width(ctx.day_size, ctx.gap, ctx.show_week_numbers)
		prev_r, _, next_r = calendar_nav_rects(origin, month_w)
	}

	_ = props.config

	Button({
		config = {
			id = fmt.tprintf("%s/prev", ctx.key),
			position = set.Position(.ABSOLUTE),
			x = set.F32(prev_r.x),
			y = set.F32(prev_r.y),
			width = set.Width(prev_r.w),
			height = set.Height(prev_r.h),
			tabbable = set.Tabbable(false),
			disabled = set.Disabled(!ctx.can_go_prev || ctx.widget_disabled),
			justify = set.Justify(o.Justify_Align.CENTER),
			background = set.Background(o.Color.TRANSPARENT),
			border_color = set.Border_color(o.Color.TRANSPARENT),
		},
		on_click = calendar_nav_prev,
		child = calendar_nav_prev_label_child,
	})

	Button({
		config = {
			id = fmt.tprintf("%s/next", ctx.key),
			position = set.Position(.ABSOLUTE),
			x = set.F32(next_r.x),
			y = set.F32(next_r.y),
			width = set.Width(next_r.w),
			height = set.Height(next_r.h),
			tabbable = set.Tabbable(false),
			disabled = set.Disabled(!ctx.can_go_next || ctx.widget_disabled),
			justify = set.Justify(o.Justify_Align.CENTER),
			background = set.Background(o.Color.TRANSPARENT),
			border_color = set.Border_color(o.Color.TRANSPARENT),
		},
		on_click = calendar_nav_next,
		child = calendar_nav_next_label_child,
	})
}

/*
Month title for one visible month column.
*/
Calendar_Caption :: proc(props: Calendar_Caption_Props) {
	if !calendar_part_month_index_ok(props.month_index) {
		return
	}

	ctx := calendar_ctx_top()
	origin, ok := calendar_part_month_origin(props.month_index)

	if !ok {
		return
	}

	label_r: o.Rect

	if month_chrome, has_chrome := calendar_part_month_chrome(props.month_index); has_chrome {
		label_r = month_chrome.label
	} else {
		month_w := calendar_month_width(ctx.day_size, ctx.gap, ctx.show_week_numbers)
		_, label_r, _ = calendar_nav_rects(origin, month_w)
	}

	month := Calendar_Date_Add_Months(ctx.month, props.month_index)
	_ = props.config

	Text(
		{
			config = {
				id = fmt.tprintf("%s/month-label-%d", ctx.key, props.month_index),
				text = calendar_format_month_label(month),
				position = set.Position(.ABSOLUTE),
				x = set.F32(label_r.x),
				y = set.F32(label_r.y + 8),
				width = set.Width(label_r.w),
				height = set.Height(label_r.h),
				font_size = set.F32(14),
				justify = set.Justify(o.Justify_Align.CENTER),
				tabbable = set.Tabbable(false),
			},
		},
	)
}

/*
Weekday header row for one month column.
*/
Calendar_Weekdays :: proc(props: Calendar_Weekdays_Props) {
	if !calendar_part_month_index_ok(props.month_index) {
		return
	}

	ctx := calendar_ctx_top()
	origin, ok := calendar_part_month_origin(props.month_index)

	if !ok {
		return
	}

	_ = props.config
	month_chrome, has_chrome := calendar_part_month_chrome(props.month_index)

	for col in 0 ..< CALENDAR_WEEK_DAYS {
		weekday := Calendar_Weekday((int(ctx.week_starts_on) + col) % CALENDAR_WEEK_DAYS)
		rect: o.Rect

		if has_chrome {
			rect = month_chrome.weekdays[col]
		} else {
			rect = calendar_weekday_rect(
				origin,
				col,
				ctx.day_size,
				ctx.gap,
				ctx.show_week_numbers,
			)
		}

		Text(
			{
				config = {
					id = fmt.tprintf("%s/wd-%d-%d", ctx.key, props.month_index, col),
					text = calendar_format_weekday_label(weekday),
					position = set.Position(.ABSOLUTE),
					x = set.F32(rect.x),
					y = set.F32(rect.y + 4),
					width = set.Width(rect.w),
					height = set.Height(rect.h),
					font_size = set.F32(12),
					color = set.Colors(o.Color.MUTED_FOREGROUND),
					justify = set.Justify(o.Justify_Align.CENTER),
					tabbable = set.Tabbable(false),
				},
			},
		)
	}
}

/*
ISO week numbers for one month column when `show_week_numbers` is enabled on the root.
*/
Calendar_Week_Numbers :: proc(props: Calendar_Week_Numbers_Props) {
	if !calendar_part_month_index_ok(props.month_index) {
		return
	}

	ctx := calendar_ctx_top()

	if !ctx.show_week_numbers {
		return
	}

	origin, ok := calendar_part_month_origin(props.month_index)

	if !ok {
		return
	}

	month := Calendar_Date_Add_Months(ctx.month, props.month_index)
	cells, grid_ok := Calendar_Build_Month_Grid(
		month,
		ctx.week_starts_on,
		ctx.today,
		ctx.show_outside_days,
		ctx.hidden_matcher,
		calendar_grid_disabled_matcher,
		calendar_part_selected_matcher,
		ctx.selection.mode == .RANGE ? ctx.selection.range : {},
		ctx.focused_day,
	)

	if !grid_ok {
		return
	}

	_ = props.config

	month_chrome, has_chrome := calendar_part_month_chrome(props.month_index)

	for row in 0 ..< CALENDAR_WEEK_ROWS {
		cell := cells[row * CALENDAR_WEEK_DAYS]
		week, week_ok := Calendar_Week_Number(cell.date)
		label := week_ok ? fmt.tprintf("%d", week) : ""
		rect: o.Rect

		if has_chrome {
			rect = month_chrome.week_nums[row]
		} else {
			rect = calendar_week_num_rect(origin, row, ctx.day_size, ctx.gap)
		}

		Text(
			{
				config = {
					id = fmt.tprintf("%s/wn-%d-%d", ctx.key, props.month_index, row),
					text = label,
					position = set.Position(.ABSOLUTE),
					x = set.F32(rect.x),
					y = set.F32(rect.y + 8),
					width = set.Width(rect.w),
					height = set.Height(rect.h),
					font_size = set.F32(11),
					color = set.Colors(o.Color.MUTED_FOREGROUND),
					justify = set.Justify(o.Justify_Align.CENTER),
					tabbable = set.Tabbable(false),
				},
			},
		)
	}
}

/*
Day labels for one month column. Cell chrome is painted by the root draw pass.
*/
Calendar_Grid :: proc(props: Calendar_Grid_Props) {
	if !calendar_part_month_index_ok(props.month_index) {
		return
	}

	ctx := calendar_ctx_top()
	origin, ok := calendar_part_month_origin(props.month_index)

	if !ok {
		return
	}

	month := Calendar_Date_Add_Months(ctx.month, props.month_index)
	cells, grid_ok := Calendar_Build_Month_Grid(
		month,
		ctx.week_starts_on,
		ctx.today,
		ctx.show_outside_days,
		ctx.hidden_matcher,
		calendar_grid_disabled_matcher,
		calendar_part_selected_matcher,
		ctx.selection.mode == .RANGE ? ctx.selection.range : {},
		ctx.focused_day,
	)

	if !grid_ok {
		return
	}

	_ = props.config

	month_chrome, has_chrome := calendar_part_month_chrome(props.month_index)

	for i in 0 ..< CALENDAR_GRID_DAYS {
		cell := cells[i]

		if cell.hidden {
			continue
		}

		rect: o.Rect

		if has_chrome {
			rect = month_chrome.days[i]
		} else {
			rect = calendar_day_rect(origin, i, ctx.day_size, ctx.gap, ctx.show_week_numbers)
		}

		color := o.Colors(o.Color.FOREGROUND)

		if cell.disabled {
			color = o.Color.MUTED_FOREGROUND
		} else if cell.selected || cell.range_start || cell.range_end {
			color = o.Color.PRIMARY_FOREGROUND
		} else if cell.outside {
			color = o.Color.MUTED_FOREGROUND
		}

		Text(
			{
				config = {
					id = fmt.tprintf(
						"%s/day-%d-%04d-%02d-%02d",
						ctx.key,
						props.month_index,
						cell.date.year,
						int(cell.date.month),
						int(cell.date.day),
					),
					text = calendar_format_day_label(cell.date),
					position = set.Position(.ABSOLUTE),
					x = set.F32(rect.x),
					y = set.F32(rect.y + 8),
					width = set.Width(rect.w),
					height = set.Height(rect.h),
					font_size = set.F32(13),
					color = set.Colors(color),
					justify = set.Justify(o.Justify_Align.CENTER),
					tabbable = set.Tabbable(false),
					opacity = set.F32(cell.disabled ? 0.45 : 1),
				},
			},
		)
	}
}

/*
Full month column: navigation (first month only), caption, weekdays, optional week numbers, grid.
*/
Calendar_Month :: proc(props: Calendar_Month_Part_Props) {
	if !calendar_part_month_index_ok(props.month_index) {
		return
	}

	_ = props.config

	if props.month_index == 0 {
		Calendar_Navigation({config = {}})
	}

	Calendar_Caption({config = {}, month_index = props.month_index})
	Calendar_Weekdays({config = {}, month_index = props.month_index})
	Calendar_Week_Numbers({config = {}, month_index = props.month_index})
	Calendar_Grid({config = {}, month_index = props.month_index})
}
