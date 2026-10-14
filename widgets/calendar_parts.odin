package oni_widgets

import o ".."
import set "../set"
import "core:fmt"

Calendar_Month_Part_Config :: o.Widget_Config

/*
Index of the visible month relative to the root `month` (0 = first month).

`day` overrides the cell builder for this month's grid; nil falls back to the
root `Calendar.day`, then built-in `Calendar_Day`.
*/
Calendar_Month_Part_Props :: struct {
	config:      Calendar_Month_Part_Config,
	month_index: int,
	day:         proc(frame_state: Calendar_Day_State),
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

/*
Day-cell grid for one month column.

`day` builds each visible cell; nil falls back to the month/root `day`, then
built-in `Calendar_Day`. Pass a custom proc to replace day chrome entirely.
*/
Calendar_Grid_Props :: struct {
	config:      Calendar_Grid_Config,
	month_index: int,
	day:         proc(frame_state: Calendar_Day_State),
}

/*
Per-day cell part: paints selection chrome and owns the hit target.
*/
Calendar_Day_Config :: o.Widget_Config

/*
Per-frame day cell state passed to `Calendar.day` / `Calendar_Grid.day` / `child`.
*/
Calendar_Day_State :: struct {
	id:          string,
	date:        Calendar_Date,
	cell:        Calendar_Day_Cell,
	month_index: int,
	day_index:   int,
	disabled:    bool,
}

Calendar_Day_Props :: struct {
	config:      Calendar_Day_Config,
	month_index: int,
	day_index:   int,
	child:       proc(frame_state: Calendar_Day_State),
}

@(private)
calendar_part_id_prefix :: proc(config_id: string) -> string {
	if config_id != "" {
		return config_id
	}

	if calendar_ctx_ok() {
		return calendar_ctx_top().key
	}

	return ""
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
calendar_part_month_cells :: proc(
	month_index: int,
) -> (
	cells: [CALENDAR_GRID_DAYS]Calendar_Day_Cell,
	ok: bool,
) {
	if !calendar_part_month_index_ok(month_index) {
		return {}, false
	}

	ctx := calendar_ctx_top()
	month := Calendar_Date_Add_Months(ctx.month, month_index)

	return Calendar_Build_Month_Grid(
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
}

@(private)
calendar_part_day_rect :: proc(month_index: int, day_index: int) -> (rect: o.Rect, ok: bool) {
	if day_index < 0 || day_index >= CALENDAR_GRID_DAYS {
		return {}, false
	}

	origin, origin_ok := calendar_part_month_origin(month_index)

	if !origin_ok {
		return {}, false
	}

	ctx := calendar_ctx_top()

	if month_chrome, has_chrome := calendar_part_month_chrome(month_index); has_chrome {
		return month_chrome.days[day_index], true
	}

	return calendar_day_rect(origin, day_index, ctx.day_size, ctx.gap, ctx.show_week_numbers), true
}

@(private)
calendar_gap_u16 :: proc(gap: f32) -> u16 {
	if gap <= 0 {
		return 0
	}

	if gap >= 65535 {
		return 65535
	}

	return u16(gap)
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

@(private)
calendar_nav_build: struct {
	prefix: string,
	nav_bg: o.Colors,
}

@(private)
calendar_nav_child :: proc(_: Rectangle_State) {
	ctx := calendar_ctx_top()
	build := calendar_nav_build
	prev_disabled := !ctx.can_go_prev || ctx.widget_disabled
	next_disabled := !ctx.can_go_next || ctx.widget_disabled
	// Widget-level disable already fades via root opacity; only mute bound-clamped nav.
	prev_opacity := prev_disabled && !ctx.widget_disabled ? f32(0.45) : f32(1)
	next_opacity := next_disabled && !ctx.widget_disabled ? f32(0.45) : f32(1)

	Button(
		{
			config = {
				id = fmt.tprintf("%s/prev", build.prefix),
				width = set.Width(CALENDAR_NAV_HEIGHT),
				height = set.Height(CALENDAR_NAV_HEIGHT),
				tabbable = set.Tabbable(false),
				disabled = set.Disabled(prev_disabled),
				justify = set.Justify(o.Justify_Align.CENTER),
				background = set.Background(build.nav_bg),
				border_color = set.Border_color(o.Color.TRANSPARENT),
				opacity = set.F32(prev_opacity),
			},
			on_click = calendar_nav_prev,
			child = calendar_nav_prev_label_child,
		},
	)

	Rectangle(
		{
			config = {
				id = fmt.tprintf("%s/nav-spacer", build.prefix),
				width = set.Width(.GROW),
				height = set.Height(CALENDAR_NAV_HEIGHT),
			},
		},
	)

	Button(
		{
			config = {
				id = fmt.tprintf("%s/next", build.prefix),
				width = set.Width(CALENDAR_NAV_HEIGHT),
				height = set.Height(CALENDAR_NAV_HEIGHT),
				tabbable = set.Tabbable(false),
				disabled = set.Disabled(next_disabled),
				justify = set.Justify(o.Justify_Align.CENTER),
				background = set.Background(build.nav_bg),
				border_color = set.Border_color(o.Color.TRANSPARENT),
				opacity = set.F32(next_opacity),
			},
			on_click = calendar_nav_next,
			child = calendar_nav_next_label_child,
		},
	)
}

@(private)
calendar_day_on_click :: proc(_: Button_Event) {
	ctx := calendar_ctx_top()

	if !ctx.active || ctx.widget_disabled || !Calendar_Date_Valid(ctx.pending_day) {
		return
	}

	if !calendar_day_interactive(ctx, ctx.pending_day) {
		return
	}

	calendar_select_day(ctx, ctx.pending_day)
	o.Stop_Propagation()
}

@(private)
calendar_day_default_label :: proc(state: Calendar_Day_State) {
	ctx := calendar_ctx_top()

	if !ctx.active {
		return
	}

	color: o.Colors = o.Color.FOREGROUND

	if state.disabled || state.cell.disabled {
		color = o.Color.MUTED_FOREGROUND
	} else if state.cell.selected || state.cell.range_start || state.cell.range_end {
		color = o.Color.PRIMARY_FOREGROUND
	} else if state.cell.outside {
		color = o.Color.MUTED_FOREGROUND
	}

	Text(
		{
			config = {
				id = fmt.tprintf(
					"%s/day-label-%d-%04d-%02d-%02d",
					ctx.key,
					state.month_index,
					state.date.year,
					int(state.date.month),
					int(state.date.day),
				),
				text = calendar_format_day_label(state.date),
				align = set.Align(.CENTER),
				font_size = set.F32(13),
				color = set.Colors(color),
				justify = set.Justify(o.Justify_Align.CENTER),
				tabbable = set.Tabbable(false),
				opacity = set.F32(state.cell.disabled ? 0.45 : 1),
			},
		},
	)
}

@(private)
calendar_day_button_child :: proc(bs: Button_State) {
	_ = bs
	ctx := calendar_ctx_top()

	if !ctx.active {
		return
	}

	state := ctx.pending_day_state
	user := ctx.pending_day_child

	if user != nil {
		user(state)

		return
	}

	calendar_day_default_label(state)
}

/*
Previous / next month controls for the first visible month.
*/
Calendar_Navigation :: proc(props: Calendar_Navigation_Props) {
	if !calendar_ctx_ok() {
		return
	}

	prefix := calendar_part_id_prefix(props.config.id)
	nav_bg: o.Colors = o.Color.TRANSPARENT

	if props.config.background.mode != .UNSET {
		nav_bg = props.config.background.value
	}

	calendar_nav_build = {
		prefix = prefix,
		nav_bg = nav_bg,
	}

	ctx := calendar_ctx_top()
	cfg := o.merge_widget_config(
		Calendar_Navigation_Config {
			direction = set.Direction(.HORIZONTAL),
			width = set.Width(.GROW),
			height = set.Height(CALENDAR_NAV_HEIGHT),
			justify = set.Justify(o.Justify_Pos{x = .SPACE_BETWEEN, y = .CENTER}),
			disabled = set.Disabled(ctx.widget_disabled),
		},
		props.config,
	)
	cfg.id = fmt.tprintf("%s/nav-row", prefix)

	if ctx.widget_disabled {
		cfg.disabled = set.Disabled(true)
	}

	Rectangle({config = cfg, child = calendar_nav_child})
}

/*
Month title for one visible month column.
*/
Calendar_Caption :: proc(props: Calendar_Caption_Props) {
	if !calendar_part_month_index_ok(props.month_index) {
		return
	}

	ctx := calendar_ctx_top()
	month := Calendar_Date_Add_Months(ctx.month, props.month_index)
	prefix := calendar_part_id_prefix(props.config.id)

	cfg := o.merge_widget_config(
		Calendar_Caption_Config {
			align = set.Align(.CENTER),
			width = set.Width(.GROW),
			height = set.Height(CALENDAR_NAV_HEIGHT),
			font_size = set.F32(14),
			justify = set.Justify(o.Justify_Align.CENTER),
			tabbable = set.Tabbable(false),
		},
		props.config,
	)
	cfg.id = fmt.tprintf("%s/month-label-%d", prefix, props.month_index)

	Text(
		{
			config = {
				id = cfg.id,
				text = calendar_format_month_label(month),
				align = cfg.align,
				width = cfg.width,
				height = cfg.height,
				font_size = cfg.font_size,
				justify = cfg.justify,
				tabbable = cfg.tabbable,
				color = cfg.color,
				background = cfg.background,
			},
		},
	)
}

@(private)
calendar_weekdays_build: struct {
	prefix:      string,
	month_index: int,
}

@(private)
calendar_weekdays_child :: proc(_: Rectangle_State) {
	ctx := calendar_ctx_top()
	build := calendar_weekdays_build

	if ctx.show_week_numbers {
		Rectangle(
			{
				config = {
					id = fmt.tprintf("%s/wd-spacer-%d", build.prefix, build.month_index),
					width = set.Width(CALENDAR_WEEK_NUM_WIDTH),
					height = set.Height(CALENDAR_WEEKDAY_HEIGHT),
				},
			},
		)
	}

	for col in 0 ..< CALENDAR_WEEK_DAYS {
		weekday := Calendar_Weekday((int(ctx.week_starts_on) + col) % CALENDAR_WEEK_DAYS)

		Text(
			{
				config = {
					id = fmt.tprintf("%s/wd-%d-%d", build.prefix, build.month_index, col),
					text = calendar_format_weekday_label(weekday),
					align = set.Align(.CENTER),
					width = set.Width(ctx.day_size),
					height = set.Height(CALENDAR_WEEKDAY_HEIGHT),
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
Weekday header row for one month column.
*/
Calendar_Weekdays :: proc(props: Calendar_Weekdays_Props) {
	if !calendar_part_month_index_ok(props.month_index) {
		return
	}

	ctx := calendar_ctx_top()
	prefix := calendar_part_id_prefix(props.config.id)

	calendar_weekdays_build = {
		prefix      = prefix,
		month_index = props.month_index,
	}

	cfg := o.merge_widget_config(
		Calendar_Weekdays_Config {
			direction = set.Direction(.HORIZONTAL),
			width = set.Width(.FIT),
			height = set.Height(CALENDAR_WEEKDAY_HEIGHT),
			gap_x = set.Gap_X(calendar_gap_u16(ctx.gap)),
			justify = set.Justify(o.Justify_Pos{x = .START, y = .CENTER}),
		},
		props.config,
	)
	cfg.id = fmt.tprintf("%s/weekdays", prefix)

	Rectangle({config = cfg, child = calendar_weekdays_child})
}

@(private)
calendar_week_numbers_build: struct {
	prefix:      string,
	month_index: int,
	cells:       [CALENDAR_GRID_DAYS]Calendar_Day_Cell,
}

@(private)
calendar_week_numbers_child :: proc(_: Rectangle_State) {
	ctx := calendar_ctx_top()
	build := calendar_week_numbers_build

	for row in 0 ..< CALENDAR_WEEK_ROWS {
		cell := build.cells[row * CALENDAR_WEEK_DAYS]
		week, week_ok := Calendar_Week_Number(cell.date)
		label := week_ok ? fmt.tprintf("%d", week) : ""

		Text(
			{
				config = {
					id = fmt.tprintf("%s/wn-%d-%d", build.prefix, build.month_index, row),
					text = label,
					width = set.Width(CALENDAR_WEEK_NUM_WIDTH),
					height = set.Height(ctx.day_size),
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

	cells, grid_ok := calendar_part_month_cells(props.month_index)

	if !grid_ok {
		return
	}

	prefix := calendar_part_id_prefix(props.config.id)

	calendar_week_numbers_build = {
		prefix      = prefix,
		month_index = props.month_index,
		cells       = cells,
	}

	cfg := o.merge_widget_config(
		Calendar_Week_Numbers_Config {
			direction = set.Direction(.VERTICAL),
			width = set.Width(CALENDAR_WEEK_NUM_WIDTH),
			height = set.Height(.FIT),
			gap_y = set.Gap_Y(calendar_gap_u16(ctx.gap)),
		},
		props.config,
	)
	cfg.id = fmt.tprintf("%s/week_numbers", prefix)

	Rectangle({config = cfg, child = calendar_week_numbers_child})
}

/*
One interactive day cell: selection chrome, hover, today/focus rings, and label.
*/
Calendar_Day :: proc(props: Calendar_Day_Props) {
	if !calendar_part_month_index_ok(props.month_index) {
		return
	}

	if props.day_index < 0 || props.day_index >= CALENDAR_GRID_DAYS {
		return
	}

	ctx := calendar_ctx_top()
	cells, grid_ok := calendar_part_month_cells(props.month_index)

	if !grid_ok {
		return
	}

	cell := cells[props.day_index]

	if cell.hidden {
		return
	}

	day_id := props.config.id

	if day_id == "" {
		day_id = fmt.tprintf(
			"%s/day-%d-%04d-%02d-%02d",
			ctx.key,
			props.month_index,
			cell.date.year,
			int(cell.date.month),
			int(cell.date.day),
		)
	}

	state := Calendar_Day_State {
		id          = day_id,
		date        = cell.date,
		cell        = cell,
		month_index = props.month_index,
		day_index   = props.day_index,
		disabled    = cell.disabled || ctx.widget_disabled,
	}

	ctx.pending_day = cell.date
	ctx.pending_day_state = state
	ctx.pending_day_child = props.child

	cfg := o.merge_widget_config(
		Calendar_Day_Config {
			width = set.Width(ctx.day_size),
			height = set.Height(ctx.day_size),
			tabbable = set.Tabbable(false),
			disabled = set.Disabled(state.disabled),
			justify = set.Justify(o.Justify_Align.CENTER),
			radius = set.Radius(f32(0)),
			background = set.Background(o.Color.TRANSPARENT),
			border_color = set.Border_color(o.Color.TRANSPARENT),
			// Per-day matcher/bounds mute; widget-level disable uses root opacity.
			opacity = set.F32(cell.disabled ? 0.45 : 1),
		},
		props.config,
	)
	// Day cell chrome is drawn square; do not inherit caller radius onto the hit target.
	cfg.radius = set.Radius(f32(0))
	cfg.id = day_id

	if state.disabled {
		cfg.disabled = set.Disabled(true)
	}

	if o.ui_pass() == .Draw {
		rect := o.ui_layout_rect(o.ui_id(day_id))
		mouse := o.Vec2{o.w_ctx.mouse_x, o.w_ctx.mouse_y}
		interactive := !state.disabled && !ctx.widget_disabled
		hovered := interactive && calendar_point_in_rect(mouse, rect)
		frame := Calendar_State {
			is_focused  = interactive && ctx.root_focused,
			is_disabled = ctx.widget_disabled || state.disabled,
		}
		event := widget_event(frame)
		calendar_draw_day_cell(ctx.layout_id, rect, cell, &frame, event, props.config, hovered)
	}

	Button({config = cfg, on_click = calendar_day_on_click, child = calendar_day_button_child})
}

@(private)
calendar_grid_build: struct {
	prefix:      string,
	month_index: int,
	day:         proc(frame_state: Calendar_Day_State),
	cells:       [CALENDAR_GRID_DAYS]Calendar_Day_Cell,
	day_size:    f32,
}

@(private)
calendar_grid_child :: proc(_: Rectangle_State) {
	ctx := calendar_ctx_top()
	build := calendar_grid_build
	day_fn := build.day

	for i in 0 ..< CALENDAR_GRID_DAYS {
		cell := build.cells[i]

		if cell.hidden {
			Rectangle(
				{
					config = {
						id = fmt.tprintf("%s/day-slot-%d-%d", build.prefix, build.month_index, i),
						width = set.Width(build.day_size),
						height = set.Height(build.day_size),
					},
				},
			)

			continue
		}

		day_id := fmt.tprintf(
			"%s/day-%d-%04d-%02d-%02d",
			build.prefix,
			build.month_index,
			cell.date.year,
			int(cell.date.month),
			int(cell.date.day),
		)

		state := Calendar_Day_State {
			id          = day_id,
			date        = cell.date,
			cell        = cell,
			month_index = build.month_index,
			day_index   = i,
			disabled    = cell.disabled || ctx.widget_disabled,
		}

		if day_fn != nil {
			day_fn(state)

			continue
		}

		Calendar_Day(
			{config = {id = day_id}, month_index = build.month_index, day_index = i},
		)
	}
}

/*
Day cells for one month column.

Calls `day` (or root/month fallback) per visible cell. Nil uses `Calendar_Day`.
Hidden cells keep a sized spacer so the 7-column wrap stays aligned.
*/
Calendar_Grid :: proc(props: Calendar_Grid_Props) {
	if !calendar_part_month_index_ok(props.month_index) {
		return
	}

	cells, grid_ok := calendar_part_month_cells(props.month_index)

	if !grid_ok {
		return
	}

	ctx := calendar_ctx_top()
	prefix := calendar_part_id_prefix(props.config.id)
	day_fn := props.day

	if day_fn == nil {
		day_fn = ctx.day
	}

	calendar_grid_build = {
		prefix      = prefix,
		month_index = props.month_index,
		day         = day_fn,
		cells       = cells,
		day_size    = ctx.day_size,
	}

	gap := calendar_gap_u16(ctx.gap)
	grid_w :=
		f32(CALENDAR_WEEK_DAYS) * ctx.day_size + f32(CALENDAR_WEEK_DAYS - 1) * ctx.gap
	grid_h :=
		f32(CALENDAR_WEEK_ROWS) * ctx.day_size + f32(CALENDAR_WEEK_ROWS - 1) * ctx.gap
	cfg := o.merge_widget_config(
		Calendar_Grid_Config {
			direction = set.Direction(.HORIZONTAL_WRAP),
			width = set.Width(grid_w),
			height = set.Height(grid_h),
			gap_x = set.Gap_X(gap),
			gap_y = set.Gap_Y(gap),
			justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
			disabled = set.Disabled(ctx.widget_disabled),
		},
		props.config,
	)
	cfg.id = fmt.tprintf("%s/grid", prefix)

	if ctx.widget_disabled {
		cfg.disabled = set.Disabled(true)
	}

	Rectangle({config = cfg, child = calendar_grid_child})
}

@(private)
calendar_month_build: struct {
	prefix:      string,
	month_index: int,
	day:         proc(frame_state: Calendar_Day_State),
}

@(private)
calendar_month_body_child :: proc(_: Rectangle_State) {
	build := calendar_month_build

	Calendar_Week_Numbers(
		{
			config = {id = fmt.tprintf("%s/week_numbers", build.prefix)},
			month_index = build.month_index,
		},
	)
	Calendar_Grid(
		{
			config = {id = build.prefix},
			month_index = build.month_index,
			day = build.day,
		},
	)
}

@(private)
calendar_month_header_child :: proc(_: Rectangle_State) {
	build := calendar_month_build
	ctx := calendar_ctx_top()
	nav_prefix := fmt.tprintf("%s/nav", build.prefix)

	prev_disabled := !ctx.can_go_prev || ctx.widget_disabled
	next_disabled := !ctx.can_go_next || ctx.widget_disabled
	prev_opacity := prev_disabled && !ctx.widget_disabled ? f32(0.45) : f32(1)
	next_opacity := next_disabled && !ctx.widget_disabled ? f32(0.45) : f32(1)

	if build.month_index == 0 {
		Button(
			{
				config = {
					id = fmt.tprintf("%s/prev", nav_prefix),
					width = set.Width(CALENDAR_NAV_HEIGHT),
					height = set.Height(CALENDAR_NAV_HEIGHT),
					tabbable = set.Tabbable(false),
					disabled = set.Disabled(prev_disabled),
					justify = set.Justify(o.Justify_Align.CENTER),
					background = set.Background(o.Color.TRANSPARENT),
					border_color = set.Border_color(o.Color.TRANSPARENT),
					opacity = set.F32(prev_opacity),
				},
				on_click = calendar_nav_prev,
				child = calendar_nav_prev_label_child,
			},
		)
	}

	Calendar_Caption(
		{
			config = {id = fmt.tprintf("%s/caption", build.prefix)},
			month_index = build.month_index,
		},
	)

	if build.month_index == 0 {
		Button(
			{
				config = {
					id = fmt.tprintf("%s/next", nav_prefix),
					width = set.Width(CALENDAR_NAV_HEIGHT),
					height = set.Height(CALENDAR_NAV_HEIGHT),
					tabbable = set.Tabbable(false),
					disabled = set.Disabled(next_disabled),
					justify = set.Justify(o.Justify_Align.CENTER),
					background = set.Background(o.Color.TRANSPARENT),
					border_color = set.Border_color(o.Color.TRANSPARENT),
					opacity = set.F32(next_opacity),
				},
				on_click = calendar_nav_next,
				child = calendar_nav_next_label_child,
			},
		)
	}
}

@(private)
calendar_month_child :: proc(_: Rectangle_State) {
	build := calendar_month_build
	ctx := calendar_ctx_top()

	Rectangle(
		{
			config = {
				id = fmt.tprintf("%s/header", build.prefix),
				direction = set.Direction(.HORIZONTAL),
				width = set.Width(.GROW),
				height = set.Height(CALENDAR_NAV_HEIGHT),
				justify = set.Justify(o.Justify_Pos{x = .SPACE_BETWEEN, y = .CENTER}),
			},
			child = calendar_month_header_child,
		},
	)
	Calendar_Weekdays(
		{
			config = {id = fmt.tprintf("%s/weekdays", build.prefix)},
			month_index = build.month_index,
		},
	)

	if ctx.show_week_numbers {
		Rectangle(
			{
				config = {
					id = fmt.tprintf("%s/body", build.prefix),
					direction = set.Direction(.HORIZONTAL),
					width = set.Width(.FIT),
					height = set.Height(.FIT),
					gap_x = set.Gap_X(calendar_gap_u16(ctx.gap)),
					justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
				},
				child = calendar_month_body_child,
			},
		)
	} else {
		Calendar_Grid(
			{
				config = {id = build.prefix},
				month_index = build.month_index,
				day = build.day,
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

	ctx := calendar_ctx_top()
	prefix := calendar_part_id_prefix(props.config.id)

	if props.config.id == "" {
		prefix = fmt.tprintf("%s/month_%d", ctx.key, props.month_index)
	}

	calendar_month_build = {
		prefix      = prefix,
		month_index = props.month_index,
		day         = props.day,
	}

	month_w := calendar_month_width(ctx.day_size, ctx.gap, ctx.show_week_numbers)
	month_h :=
		CALENDAR_NAV_HEIGHT +
		ctx.gap +
		CALENDAR_WEEKDAY_HEIGHT +
		ctx.gap +
		f32(CALENDAR_WEEK_ROWS) * ctx.day_size +
		f32(CALENDAR_WEEK_ROWS - 1) * ctx.gap
	cfg := o.merge_widget_config(
		Calendar_Month_Part_Config {
			direction = set.Direction(.VERTICAL),
			width = set.Width(month_w),
			height = set.Height(month_h),
			gap_y = set.Gap_Y(calendar_gap_u16(ctx.gap)),
			justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .START}),
			disabled = set.Disabled(ctx.widget_disabled),
		},
		props.config,
	)
	cfg.id = prefix

	if ctx.widget_disabled {
		cfg.disabled = set.Disabled(true)
	}

	Rectangle({config = cfg, child = calendar_month_child})
}

@(private)
calendar_default_months_count: int

@(private)
calendar_default_months_child :: proc(_: Rectangle_State) {
	ctx := calendar_ctx_top()
	count := calendar_default_months_count

	for i in 0 ..< count {
		Calendar_Month({config = {id = fmt.tprintf("%s/month_%d", ctx.key, i)}, month_index = i})
	}
}

/*
Default calendar UI: one `Calendar_Month` per visible month.

Used when `Calendar` `child` is nil, and by Date_Picker's default panel.
*/
Calendar_Default_Months :: proc(state: Calendar_State) {
	if !calendar_ctx_ok() {
		return
	}

	ctx := calendar_ctx_top()
	count := state.number_of_months

	if count < 1 {
		count = 1
	}

	if count > CALENDAR_MAX_MONTHS {
		count = CALENDAR_MAX_MONTHS
	}

	calendar_default_months_count = count

	months_w, months_h := calendar_measure(
		count,
		ctx.day_size,
		ctx.gap,
		ctx.show_week_numbers,
	)

	Rectangle(
		{
			config = {
				id = fmt.tprintf("%s/months", ctx.key),
				direction = set.Direction(.HORIZONTAL),
				width = set.Width(months_w),
				height = set.Height(months_h),
				gap_x = set.Gap_X(calendar_gap_u16(ctx.gap * 3)),
				padding = set.Padding(CALENDAR_PAD),
				justify = set.Justify(o.Justify_Pos{x = .CENTER, y = .START}),
			},
			child = calendar_default_months_child,
		},
	)
}
