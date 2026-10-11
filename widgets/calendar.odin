package oni_widgets

import o ".."
import set "../set"
import "core:strings"

CALENDAR_DEFAULT_DAY_SIZE :: f32(36)
CALENDAR_DEFAULT_GAP :: f32(4)
CALENDAR_NAV_HEIGHT :: f32(36)
CALENDAR_WEEKDAY_HEIGHT :: f32(28)
CALENDAR_WEEK_NUM_WIDTH :: f32(28)
CALENDAR_PAD :: f32(12)

/*
Author-time style overrides for calendar chrome and day cells.
*/
Calendar_Style :: struct {
	day_size:     o.Cfg(o.Style_F32),
	gap:          o.Cfg(o.Style_F32),
	selected:     o.Cfg(o.Colors),
	selected_fg:  o.Cfg(o.Colors),
	today:        o.Cfg(o.Colors),
	outside:      o.Cfg(o.Colors),
	range_middle: o.Cfg(o.Colors),
	day_hover:    o.Cfg(o.Colors),
	nav_button:   o.Cfg(o.Colors),
	radius:       o.Cfg(o.Radius),
}

Calendar_Config :: o.Widget_Config

/*
Per-frame calendar state exposed to handlers and composable part builders.
*/
Calendar_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	mode:              Calendar_Mode,
	month:             Calendar_Date,
	focused_day:       Calendar_Date,
	selection:         Calendar_Selection,
	number_of_months:  int,
	week_starts_on:    Calendar_Weekday,
	show_outside_days: bool,
	show_week_numbers: bool,
	can_go_prev:       bool,
	can_go_next:       bool,
	content_width:     f32,
	content_height:    f32,
}

Calendar_Event :: o.Widget_Event(Calendar_State)

/*
Calendar root props (composable / DayPicker-style).

Compose with `Calendar_Month` or finer parts (`Calendar_Navigation`, `Calendar_Caption`,
`Calendar_Weekdays`, `Calendar_Week_Numbers`, `Calendar_Grid`) inside `child`.

Selection is caller-owned for `SINGLE` / `MULTIPLE` / `RANGE`: pass the current
selection every frame and update it from `on_select`. The widget never mutates
caller slices or dates.

Month navigation is uncontrolled by default (runtime owns the displayed month
from `default_month` or today). Pass `on_month_change` to control the month via
`month` each frame.

`disabled_matcher` / `hidden_matcher` return true when a day cannot be selected
or should not be shown. `start_date` / `end_date` disable days outside an
inclusive selectable window. `today` overrides the system date when non-zero
(tests). Outside-month days show by default; set `hide_outside_days` to hide them.
*/
Calendar_Props :: struct {
	config:                       Calendar_Config,
	mode:                         Calendar_Mode,
	selected:                     Calendar_Date,
	has_selected:                 bool,
	selected_dates:               []Calendar_Date,
	selected_range:               Calendar_Range,
	month:                        Calendar_Date,
	default_month:                Calendar_Date,
	on_month_change:              proc(month: Calendar_Date),
	on_select:                    proc(selection: Calendar_Selection),
	on_day_click:                 proc(date: Calendar_Date),
	required:                     bool,
	min:                          int,
	max:                          int,
	start_month:                  Calendar_Date,
	end_month:                    Calendar_Date,
	start_date:                   Calendar_Date,
	end_date:                     Calendar_Date,
	disabled_matcher:             proc(date: Calendar_Date) -> bool,
	hidden_matcher:               proc(date: Calendar_Date) -> bool,
	hide_outside_days:            bool,
	show_week_numbers:            bool,
	week_starts_on:               Calendar_Weekday,
	number_of_months:             int,
	today:                        Calendar_Date,
	disabled:                     bool,
	style:                        Calendar_Style,
	format_month:                 proc(date: Calendar_Date) -> string,
	format_weekday:               proc(weekday: Calendar_Weekday) -> string,
	format_day:                   proc(date: Calendar_Date) -> string,
	child:                        proc(frame_state: Calendar_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Calendar_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Calendar_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	scroll_bar:                   Scroll_Bar_Style,
	on_focus:                     proc(event: Calendar_Event),
	on_blur:                      proc(event: Calendar_Event),
	on_mouse_enter:               proc(event: Calendar_Event),
	on_mouse_leave:               proc(event: Calendar_Event),
	on_mouse_pressed:             proc(event: Calendar_Event),
	on_mouse_down:                proc(event: Calendar_Event),
	on_mouse_released:            proc(event: Calendar_Event),
	on_mouse_move:                proc(event: Calendar_Event),
	on_click:                     proc(event: Calendar_Event),
	on_contextmenu:               proc(event: Calendar_Event),
	on_key_pressed:               proc(event: Calendar_Event),
	on_key_down:                  proc(event: Calendar_Event),
	on_key_released:              proc(event: Calendar_Event),
}

@(private)
Calendar_Runtime :: struct {
	month:       Calendar_Date,
	focused_day: Calendar_Date,
	initialized: bool,
	month_set:   bool,
	focus_set:   bool,
}

@(private)
Calendar_Ctx :: struct {
	active:            bool,
	key:               string,
	layout_id:         o.UI_Id,
	runtime:           ^Calendar_Runtime,
	mode:              Calendar_Mode,
	month:             Calendar_Date,
	focused_day:       Calendar_Date,
	selection:         Calendar_Selection,
	required:          bool,
	min:               int,
	max:               int,
	start_month:       Calendar_Date,
	end_month:         Calendar_Date,
	start_date:        Calendar_Date,
	end_date:          Calendar_Date,
	number_of_months:  int,
	week_starts_on:    Calendar_Weekday,
	show_outside_days: bool,
	show_week_numbers: bool,
	today:             Calendar_Date,
	day_size:          f32,
	gap:               f32,
	month_controlled:  bool,
	disabled_matcher:  proc(date: Calendar_Date) -> bool,
	hidden_matcher:    proc(date: Calendar_Date) -> bool,
	on_month_change:   proc(month: Calendar_Date),
	on_select:         proc(selection: Calendar_Selection),
	on_day_click:      proc(date: Calendar_Date),
	format_month:      proc(date: Calendar_Date) -> string,
	format_weekday:    proc(weekday: Calendar_Weekday) -> string,
	format_day:        proc(date: Calendar_Date) -> string,
	on_key_down:       proc(event: Calendar_Event),
	on_key_pressed:    proc(event: Calendar_Event),
	on_key_released:   proc(event: Calendar_Event),
	hover_day:         Calendar_Date,
	has_hover_day:     bool,
	widget_disabled:   bool,
	can_go_prev:       bool,
	can_go_next:       bool,
}

@(private)
CALENDAR_CTX_MAX :: 8

@(private)
calendar_ctx_stack: [CALENDAR_CTX_MAX]Calendar_Ctx

@(private)
calendar_ctx_depth: int

@(private)
calendar_ctx_dummy: Calendar_Ctx

@(private)
calendar_stack_warned: bool

@(private)
calendar_runtimes: map[string]Calendar_Runtime

@(private)
calendar_ctx_top :: proc() -> ^Calendar_Ctx {
	if calendar_ctx_depth <= 0 {
		return &calendar_ctx_dummy
	}

	return &calendar_ctx_stack[calendar_ctx_depth - 1]
}

@(private)
calendar_ctx_ok :: proc() -> bool {
	ctx := calendar_ctx_top()

	return calendar_ctx_depth > 0 && ctx.active
}

@(private)
calendar_ctx_push :: proc(ctx: Calendar_Ctx) -> bool {
	if calendar_ctx_depth >= CALENDAR_CTX_MAX {
		if !calendar_stack_warned {
			calendar_stack_warned = true
			o.Log_Warn("calendar context stack overflow")
		}

		return false
	}

	calendar_ctx_stack[calendar_ctx_depth] = ctx
	calendar_ctx_depth += 1

	return true
}

@(private)
calendar_ctx_pop :: proc() {
	if calendar_ctx_depth <= 0 {
		return
	}

	calendar_ctx_depth -= 1
	calendar_ctx_stack[calendar_ctx_depth] = {}
}

/*
Releases heap-owned calendar runtime maps.

Called from widget `Shutdown`.
*/
calendar_shutdown :: proc() {
	calendar_ctx_depth = 0
	calendar_ctx_stack = {}
	calendar_ctx_dummy = {}
	calendar_stack_warned = false

	if calendar_runtimes == nil {
		return
	}

	for key in calendar_runtimes {
		delete(key)
	}

	delete(calendar_runtimes)
	calendar_runtimes = nil
}

@(private)
calendar_runtime_ensure :: proc(key: string) -> ^Calendar_Runtime {
	if key == "" {
		return nil
	}

	if calendar_runtimes == nil {
		calendar_runtimes = make(map[string]Calendar_Runtime)
	}

	if _, ok := calendar_runtimes[key]; !ok {
		calendar_runtimes[strings.clone(key)] = {}
	}

	return &calendar_runtimes[key]
}

@(private)
calendar_runtime_clear :: proc(key: string) {
	if calendar_runtimes == nil || key == "" {
		return
	}

	if _, ok := calendar_runtimes[key]; !ok {
		return
	}

	for k in calendar_runtimes {
		if k == key {
			delete_key(&calendar_runtimes, k)
			delete(k)
			break
		}
	}
}

@(private)
calendar_style_f32 :: proc(cfg: o.Cfg(o.Style_F32), fallback: f32) -> f32 {
	return o.cfg_style_f32(cfg, fallback)
}

@(private)
calendar_style_color :: proc(cfg: o.Cfg(o.Colors), fallback: o.Colors) -> o.Colors {
	if cfg.mode == .Value {
		return cfg.value
	}

	return fallback
}

@(private)
calendar_resolve_months :: proc(count: int) -> int {
	if count <= 0 {
		return 1
	}

	return min(count, CALENDAR_MAX_MONTHS)
}

@(private)
calendar_resolve_show_outside :: proc(props: Calendar_Props) -> bool {
	// DayPicker defaults to showing outside-month days.
	return !props.hide_outside_days
}

@(private)
calendar_resolve_today :: proc(props: Calendar_Props) -> Calendar_Date {
	if Calendar_Date_Valid(props.today) {
		return props.today
	}

	return Calendar_Today()
}

@(private)
calendar_selection_from_props :: proc(props: Calendar_Props) -> Calendar_Selection {
	sel := Calendar_Selection {
		mode = props.mode,
	}

	switch props.mode {
	case .NONE:
	case .SINGLE:
		sel.has_single = props.has_selected && Calendar_Date_Valid(props.selected)
		sel.single = props.selected
	case .MULTIPLE:
		sel.multiple = props.selected_dates
	case .RANGE:
		sel.range = Calendar_Range_Normalize(props.selected_range)
	}

	return sel
}

@(private)
calendar_day_is_selected :: proc(sel: Calendar_Selection, date: Calendar_Date) -> bool {
	switch sel.mode {
	case .NONE:
		return false
	case .SINGLE:
		return sel.has_single && Calendar_Date_Equal(sel.single, date)
	case .MULTIPLE:
		return Calendar_Dates_Contains(sel.multiple, date)
	case .RANGE:
		return Calendar_Range_Contains(sel.range, date)
	}

	return false
}

@(private)
calendar_emit_select :: proc(ctx: ^Calendar_Ctx, sel: Calendar_Selection) {
	if ctx == nil {
		return
	}

	ctx.selection = sel

	if ctx.on_select != nil {
		ctx.on_select(sel)
	}
}

@(private)
calendar_set_month :: proc(ctx: ^Calendar_Ctx, month: Calendar_Date) {
	if ctx == nil {
		return
	}

	next := Calendar_Clamp_Month(Calendar_Start_Of_Month(month), ctx.start_month, ctx.end_month)

	if next.year == 0 {
		return
	}

	if Calendar_Date_Equal(Calendar_Start_Of_Month(ctx.month), next) {
		return
	}

	ctx.month = next

	if ctx.runtime != nil {
		ctx.runtime.month = next
		ctx.runtime.month_set = true
	}

	if ctx.on_month_change != nil {
		ctx.on_month_change(next)
	}

	// Keep focus inside the visible month span when possible.
	if Calendar_Date_Valid(ctx.focused_day) {
		focus_month := Calendar_Start_Of_Month(ctx.focused_day)
		last := Calendar_Date_Add_Months(next, ctx.number_of_months - 1)

		if Calendar_Date_Before(focus_month, next) || Calendar_Date_After(focus_month, last) {
			calendar_set_focused_day(
				ctx,
				Calendar_Date_Clamp_Day(next.year, next.month, ctx.focused_day.day),
			)
		}
	}
}

@(private)
calendar_set_focused_day :: proc(ctx: ^Calendar_Ctx, day: Calendar_Date) {
	if ctx == nil || !Calendar_Date_Valid(day) {
		return
	}

	ctx.focused_day = day

	if ctx.runtime != nil {
		ctx.runtime.focused_day = day
		ctx.runtime.focus_set = true
	}

	focus_month := Calendar_Start_Of_Month(day)
	first := Calendar_Start_Of_Month(ctx.month)
	last := Calendar_Date_Add_Months(first, ctx.number_of_months - 1)

	if Calendar_Date_Before(focus_month, first) || Calendar_Date_After(focus_month, last) {
		calendar_set_month(ctx, focus_month)
	}
}

@(private)
calendar_day_out_of_bounds :: proc(ctx: ^Calendar_Ctx, date: Calendar_Date) -> bool {
	if ctx == nil || !Calendar_Date_Valid(date) {
		return true
	}

	if Calendar_Date_Valid(ctx.start_date) && Calendar_Date_Before(date, ctx.start_date) {
		return true
	}

	if Calendar_Date_Valid(ctx.end_date) && Calendar_Date_After(date, ctx.end_date) {
		return true
	}

	return false
}

@(private)
calendar_day_disabled :: proc(ctx: ^Calendar_Ctx, date: Calendar_Date) -> bool {
	if calendar_day_out_of_bounds(ctx, date) {
		return true
	}

	if ctx != nil && ctx.disabled_matcher != nil && ctx.disabled_matcher(date) {
		return true
	}

	return false
}

@(private)
calendar_day_interactive :: proc(ctx: ^Calendar_Ctx, date: Calendar_Date) -> bool {
	if ctx == nil || !Calendar_Date_Valid(date) {
		return false
	}

	if ctx.hidden_matcher != nil && ctx.hidden_matcher(date) {
		return false
	}

	if calendar_day_disabled(ctx, date) {
		return false
	}

	return true
}

@(private)
calendar_grid_disabled_matcher :: proc(date: Calendar_Date) -> bool {
	return calendar_day_disabled(calendar_ctx_top(), date)
}

@(private)
calendar_select_day :: proc(ctx: ^Calendar_Ctx, date: Calendar_Date) {
	if ctx == nil || !calendar_day_interactive(ctx, date) {
		return
	}

	if ctx.on_day_click != nil {
		ctx.on_day_click(date)
	}

	calendar_set_focused_day(ctx, date)

	switch ctx.mode {
	case .NONE:
		return
	case .SINGLE:
		next, has_next, changed := Calendar_Apply_Single_Click(
			ctx.selection.single,
			ctx.selection.has_single,
			date,
			ctx.required,
		)

		if !changed {
			return
		}

		calendar_emit_select(ctx, {mode = .SINGLE, single = next, has_single = has_next})
	case .MULTIPLE:
		next, changed := Calendar_Toggle_Multiple(
			ctx.selection.multiple,
			date,
			ctx.min,
			ctx.max,
			context.temp_allocator,
		)

		if !changed {
			return
		}

		calendar_emit_select(ctx, {mode = .MULTIPLE, multiple = next})
	case .RANGE:
		next, changed := Calendar_Apply_Range_Click(ctx.selection.range, date, ctx.min, ctx.max)

		if !changed {
			return
		}

		calendar_emit_select(ctx, {mode = .RANGE, range = next})
	}
}

@(private)
calendar_measure :: proc(
	number_of_months: int,
	day_size, gap: f32,
	show_week_numbers: bool,
) -> (
	w, h: f32,
) {
	months := f32(max(1, number_of_months))
	week_w := show_week_numbers ? CALENDAR_WEEK_NUM_WIDTH + gap : 0
	month_w := week_w + f32(CALENDAR_WEEK_DAYS) * day_size + f32(CALENDAR_WEEK_DAYS - 1) * gap
	content_w := months * month_w + (months - 1) * (gap * 3) + CALENDAR_PAD * 2
	grid_h :=
		CALENDAR_NAV_HEIGHT +
		gap +
		CALENDAR_WEEKDAY_HEIGHT +
		gap +
		f32(CALENDAR_WEEK_ROWS) * day_size +
		f32(CALENDAR_WEEK_ROWS - 1) * gap
	content_h := grid_h + CALENDAR_PAD * 2

	return content_w, content_h
}

@(private)
calendar_month_origin :: proc(
	root: o.Rect,
	month_index: int,
	number_of_months: int,
	day_size, gap: f32,
	show_week_numbers: bool,
) -> o.Vec2 {
	week_w := show_week_numbers ? CALENDAR_WEEK_NUM_WIDTH + gap : 0
	month_w := week_w + f32(CALENDAR_WEEK_DAYS) * day_size + f32(CALENDAR_WEEK_DAYS - 1) * gap
	x := root.x + CALENDAR_PAD + f32(month_index) * (month_w + gap * 3)
	y := root.y + CALENDAR_PAD

	return {x, y}
}

@(private)
calendar_nav_rects :: proc(origin: o.Vec2, month_w: f32) -> (prev, label, next: o.Rect) {
	prev = {
		x = origin.x,
		y = origin.y,
		w = CALENDAR_NAV_HEIGHT,
		h = CALENDAR_NAV_HEIGHT,
	}
	next = {
		x = origin.x + month_w - CALENDAR_NAV_HEIGHT,
		y = origin.y,
		w = CALENDAR_NAV_HEIGHT,
		h = CALENDAR_NAV_HEIGHT,
	}
	label = {
		x = prev.x + prev.w + 4,
		y = origin.y,
		w = max(f32(0), next.x - (prev.x + prev.w) - 8),
		h = CALENDAR_NAV_HEIGHT,
	}

	return
}

@(private)
calendar_weekday_rect :: proc(
	origin: o.Vec2,
	col: int,
	day_size, gap: f32,
	show_week_numbers: bool,
) -> o.Rect {
	week_w := show_week_numbers ? CALENDAR_WEEK_NUM_WIDTH + gap : 0
	x := origin.x + week_w + f32(col) * (day_size + gap)
	y := origin.y + CALENDAR_NAV_HEIGHT + gap

	return {x = x, y = y, w = day_size, h = CALENDAR_WEEKDAY_HEIGHT}
}

@(private)
calendar_day_rect :: proc(
	origin: o.Vec2,
	index: int,
	day_size, gap: f32,
	show_week_numbers: bool,
) -> o.Rect {
	row := index / CALENDAR_WEEK_DAYS
	col := index % CALENDAR_WEEK_DAYS
	week_w := show_week_numbers ? CALENDAR_WEEK_NUM_WIDTH + gap : 0
	x := origin.x + week_w + f32(col) * (day_size + gap)
	y :=
		origin.y +
		CALENDAR_NAV_HEIGHT +
		gap +
		CALENDAR_WEEKDAY_HEIGHT +
		gap +
		f32(row) * (day_size + gap)

	return {x = x, y = y, w = day_size, h = day_size}
}

@(private)
calendar_week_num_rect :: proc(origin: o.Vec2, row: int, day_size, gap: f32) -> o.Rect {
	y :=
		origin.y +
		CALENDAR_NAV_HEIGHT +
		gap +
		CALENDAR_WEEKDAY_HEIGHT +
		gap +
		f32(row) * (day_size + gap)

	return {x = origin.x, y = y, w = CALENDAR_WEEK_NUM_WIDTH, h = day_size}
}

@(private)
calendar_month_width :: proc(day_size, gap: f32, show_week_numbers: bool) -> f32 {
	week_w := show_week_numbers ? CALENDAR_WEEK_NUM_WIDTH + gap : 0

	return week_w + f32(CALENDAR_WEEK_DAYS) * day_size + f32(CALENDAR_WEEK_DAYS - 1) * gap
}

@(private)
calendar_point_in_rect :: proc(p: o.Vec2, r: o.Rect) -> bool {
	return p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h
}

@(private)
calendar_bind_layout_chrome :: proc(layout_id: o.UI_Id, ctx: ^Calendar_Ctx) {
	if ctx == nil || !ctx.active {
		return
	}

	node, ok := o.layout_node_by_id(layout_id)

	if !ok {
		return
	}

	o.layout_set_calendar(
		node,
		{
			number_of_months = ctx.number_of_months,
			day_size = ctx.day_size,
			gap = ctx.gap,
			pad = CALENDAR_PAD,
			month_gap = ctx.gap * 3,
			show_week_numbers = ctx.show_week_numbers,
			nav_height = CALENDAR_NAV_HEIGHT,
			weekday_height = CALENDAR_WEEKDAY_HEIGHT,
			week_num_width = CALENDAR_WEEK_NUM_WIDTH,
			active = true,
		},
	)
}

@(private)
calendar_hit_test :: proc(
	ctx: ^Calendar_Ctx,
	mouse: o.Vec2,
) -> (
	date: Calendar_Date,
	nav: int,
	ok: bool, // -1 prev, +1 next, 0 none
) {
	if ctx == nil {
		return {}, 0, false
	}

	chrome := o.layout_calendar_result(ctx.layout_id)

	if chrome == nil {
		return {}, 0, false
	}

	for mi in 0 ..< len(chrome.months) {
		month_chrome := chrome.months[mi]

		if mi == 0 && calendar_point_in_rect(mouse, month_chrome.prev) {
			return {}, -1, true
		}

		if mi == 0 && calendar_point_in_rect(mouse, month_chrome.next) {
			return {}, 1, true
		}

		month := Calendar_Date_Add_Months(ctx.month, mi)
		cells, grid_ok := Calendar_Build_Month_Grid(
			month,
			ctx.week_starts_on,
			ctx.today,
			ctx.show_outside_days,
			ctx.hidden_matcher,
			calendar_grid_disabled_matcher,
			proc(date: Calendar_Date) -> bool {
				return calendar_day_is_selected(calendar_ctx_top().selection, date)
			},
			ctx.selection.mode == .RANGE ? ctx.selection.range : {},
			ctx.focused_day,
		)

		if !grid_ok {
			continue
		}

		for i in 0 ..< CALENDAR_GRID_DAYS {
			cell := cells[i]

			if cell.hidden {
				continue
			}

			if calendar_point_in_rect(mouse, month_chrome.days[i]) {
				return cell.date, 0, true
			}
		}
	}

	return {}, 0, false
}

@(private)
calendar_handle_pointer :: proc(frame_state: ^Calendar_State, hovered: bool, interactive: bool) {
	ctx := calendar_ctx_top()

	if !ctx.active || frame_state == nil || !interactive || frame_state.is_disabled {
		return
	}

	mouse := o.Vec2{o.w_ctx.mouse_x, o.w_ctx.mouse_y}
	date, nav, hit := calendar_hit_test(ctx, mouse)

	if hit && nav == 0 && Calendar_Date_Valid(date) {
		ctx.hover_day = date
		ctx.has_hover_day = true
	} else {
		ctx.has_hover_day = false
	}

	if !(o.w_ctx.left_mouse.pressed && hovered) {
		return
	}

	if !hit {
		return
	}

	// Prev/next are real Buttons (`Calendar_Navigation` on_click). Navigating here
	// on press double-advances on release and mutates the month mid-draw against
	// stale layout chrome (partial day clear).
	if nav != 0 {
		return
	}

	if Calendar_Date_Valid(date) {
		calendar_select_day(ctx, date)
		o.Stop_Propagation()
	}
}

@(private)
calendar_key_edge :: proc(code: o.Scancode) -> bool {
	if o.w_ctx == nil || o.shortcut_key_consumed(code) {
		return false
	}

	idx := int(code)

	if idx < 0 || idx >= len(o.w_ctx.keys) {
		return false
	}

	key := o.w_ctx.keys[idx]

	return key.pressed || key.repeat
}

@(private)
calendar_consume_key :: proc(code: o.Scancode) {
	o.shortcut_consume_key(code)
}

@(private)
calendar_move_focus :: proc(ctx: ^Calendar_Ctx, delta_days: i64) {
	if ctx == nil {
		return
	}

	base := ctx.focused_day

	if !Calendar_Date_Valid(base) {
		base = Calendar_Date_Valid(ctx.selection.single) ? ctx.selection.single : ctx.today

		if !Calendar_Date_Valid(base) {
			base = Calendar_Start_Of_Month(ctx.month)
		}
	}

	next := Calendar_Date_Add_Days(base, delta_days)

	for _ in 0 ..< 366 {
		if !Calendar_Date_Valid(next) {
			return
		}

		if calendar_day_interactive(ctx, next) {
			calendar_set_focused_day(ctx, next)

			return
		}

		step: i64 = delta_days < 0 ? -1 : 1
		next = Calendar_Date_Add_Days(next, step)
	}
}

@(private)
calendar_handle_keys :: proc(event: Calendar_Event) {
	ctx := calendar_ctx_top()

	if !ctx.active {
		return
	}

	// Only act on the scancode for this callback — `on_key_down` fires per held key.
	code := event.key

	if !calendar_key_edge(code) {
		if ctx.on_key_down != nil {
			ctx.on_key_down(event)
		}

		return
	}

	shift := o.state != nil && o.state.input.modifiers.shift
	handled := false

	#partial switch code {
	case .LEFT:
		calendar_consume_key(.LEFT)

		if shift {
			if Calendar_Can_Navigate(ctx.month, -1, ctx.start_month, ctx.end_month) {
				calendar_set_month(ctx, Calendar_Date_Add_Months(ctx.month, -1))
			}
		} else {
			calendar_move_focus(ctx, -1)
		}

		handled = true
	case .RIGHT:
		calendar_consume_key(.RIGHT)

		if shift {
			if Calendar_Can_Navigate(ctx.month, 1, ctx.start_month, ctx.end_month) {
				calendar_set_month(ctx, Calendar_Date_Add_Months(ctx.month, 1))
			}
		} else {
			calendar_move_focus(ctx, 1)
		}

		handled = true
	case .UP:
		calendar_consume_key(.UP)

		if shift {
			if Calendar_Can_Navigate(ctx.month, -12, ctx.start_month, ctx.end_month) {
				calendar_set_month(ctx, Calendar_Date_Add_Months(ctx.month, -12))
			}
		} else {
			calendar_move_focus(ctx, -CALENDAR_WEEK_DAYS)
		}

		handled = true
	case .DOWN:
		calendar_consume_key(.DOWN)

		if shift {
			if Calendar_Can_Navigate(ctx.month, 12, ctx.start_month, ctx.end_month) {
				calendar_set_month(ctx, Calendar_Date_Add_Months(ctx.month, 12))
			}
		} else {
			calendar_move_focus(ctx, CALENDAR_WEEK_DAYS)
		}

		handled = true
	case .PAGEUP:
		calendar_consume_key(.PAGEUP)
		delta := shift ? -12 : -1

		if Calendar_Can_Navigate(ctx.month, delta, ctx.start_month, ctx.end_month) {
			calendar_set_month(ctx, Calendar_Date_Add_Months(ctx.month, delta))
		}

		handled = true
	case .PAGEDOWN:
		calendar_consume_key(.PAGEDOWN)
		delta := shift ? 12 : 1

		if Calendar_Can_Navigate(ctx.month, delta, ctx.start_month, ctx.end_month) {
			calendar_set_month(ctx, Calendar_Date_Add_Months(ctx.month, delta))
		}

		handled = true
	case .HOME:
		calendar_consume_key(.HOME)
		base := ctx.focused_day

		if !Calendar_Date_Valid(base) {
			base = Calendar_Start_Of_Month(ctx.month)
		}

		weekday, ok := Calendar_Date_Weekday(base)

		if ok {
			delta :=
				(int(weekday) - int(ctx.week_starts_on) + CALENDAR_WEEK_DAYS) % CALENDAR_WEEK_DAYS
			calendar_move_focus(ctx, -i64(delta))
		}

		handled = true
	case .END:
		calendar_consume_key(.END)
		base := ctx.focused_day

		if !Calendar_Date_Valid(base) {
			base = Calendar_Start_Of_Month(ctx.month)
		}

		weekday, ok := Calendar_Date_Weekday(base)

		if ok {
			delta :=
				(int(ctx.week_starts_on) +
					CALENDAR_WEEK_DAYS -
					1 -
					int(weekday) +
					CALENDAR_WEEK_DAYS) %
				CALENDAR_WEEK_DAYS
			calendar_move_focus(ctx, i64(delta))
		}

		handled = true
	case .SPACE, .RETURN:
		calendar_consume_key(code)

		if Calendar_Date_Valid(ctx.focused_day) {
			calendar_select_day(ctx, ctx.focused_day)
		}

		handled = true
	case:
	}

	if handled {
		o.Stop_Propagation()
	}

	if ctx.on_key_down != nil {
		ctx.on_key_down(event)
	}
}

@(private)
calendar_on_key_down :: proc(event: Calendar_Event) {
	calendar_handle_keys(event)
}

@(private)
calendar_on_key_pressed :: proc(event: Calendar_Event) {
	ctx := calendar_ctx_top()

	if ctx.active && ctx.on_key_pressed != nil {
		ctx.on_key_pressed(event)
	}
}

@(private)
calendar_on_key_released :: proc(event: Calendar_Event) {
	ctx := calendar_ctx_top()

	if ctx.active && ctx.on_key_released != nil {
		ctx.on_key_released(event)
	}
}

@(private)
calendar_theme_base :: proc(frame_state: ^Calendar_State) -> Calendar_Config {
	opacity := f32(1)

	if frame_state.is_disabled {
		opacity = 0.5
	}

	border := o.Colors(o.Color.BORDER)

	if frame_state.is_focused {
		border = o.Color.RING
	}

	w := frame_state.content_width

	if w <= 0 {
		w = f32(280)
	}

	h := frame_state.content_height

	if h <= 0 {
		h = f32(320)
	}

	return Calendar_Config {
		kind = .CALENDAR,
		tabbable = set.Tabbable(true),
		direction = set.Direction(o.Direction_Layout.VERTICAL),
		width = set.Width(w),
		height = set.Height(h),
		padding = set.Padding(o.Pd_struct{x = 0, y = 0}),
		border = set.Border(f32(1)),
		border_color = set.Border_color(border),
		radius = set.Radius(f32(8)),
		background = set.Background(o.Color.CARD),
		color = set.Colors(o.Color.FOREGROUND),
		opacity = set.F32(opacity),
		overflow_x = set.Overflow_X(.HIDDEN),
		overflow_y = set.Overflow_Y(.HIDDEN),
	}
}

@(private)
calendar_refresh_merged :: proc(
	props: Calendar_Props,
	frame_state: ^Calendar_State,
) -> Calendar_Event {
	event := widget_event(frame_state^)
	base := calendar_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
calendar_resolve_color :: proc(
	colors: o.Colors,
	frame_state: ^Calendar_State,
	event: Calendar_Event,
	fallback: o.RGBA,
) -> o.RGBA {
	if rgba, ok := o.to_rgba(colors, frame_state, event); ok {
		return rgba
	}

	return fallback
}

@(private)
calendar_draw_day_cell :: proc(
	layout_id: o.UI_Id,
	rect: o.Rect,
	cell: Calendar_Day_Cell,
	frame_state: ^Calendar_State,
	event: Calendar_Event,
	style: Calendar_Style,
	hovered: bool,
) {
	if o.ui_layout_paint_skip(layout_id) || rect.w <= 0 || rect.h <= 0 || cell.hidden {
		return
	}

	radius: o.Radius_px = {
		tl = 6,
		tr = 6,
		br = 6,
		bl = 6,
	}

	if style.radius.mode != .UNSET {
		if resolved, ok := o.resolve_radius(style.radius.value, frame_state, event); ok {
			radius = resolved
		}
	}

	bg := o.RGBA{}
	draw_bg := false

	if cell.range_middle {
		bg = calendar_resolve_color(
			calendar_style_color(style.range_middle, o.Color.ACCENT),
			frame_state,
			event,
			{59, 130, 246, 40},
		)
		draw_bg = true
		radius = {
			tl = 0,
			tr = 0,
			br = 0,
			bl = 0,
		}
	}

	if cell.selected || cell.range_start || cell.range_end {
		bg = calendar_resolve_color(
			calendar_style_color(style.selected, o.Color.PRIMARY),
			frame_state,
			event,
			{59, 130, 246, 255},
		)
		draw_bg = true
	} else if hovered {
		bg = calendar_resolve_color(
			calendar_style_color(style.day_hover, o.Color.ACCENT),
			frame_state,
			event,
			{0, 0, 0, 20},
		)
		draw_bg = true
	}

	if draw_bg {
		o.Draw_Rectangle(rect, bg, radius)
	}

	if cell.today && !cell.selected {
		ring := calendar_resolve_color(
			calendar_style_color(style.today, o.Color.RING),
			frame_state,
			event,
			{59, 130, 246, 255},
		)
		inset := f32(1)
		inner := o.Rect {
			x = rect.x + inset,
			y = rect.y + inset,
			w = max(f32(0), rect.w - inset * 2),
			h = max(f32(0), rect.h - inset * 2),
		}
		o.Draw_Rectangle(rect, ring, radius)
		card := calendar_resolve_color(o.Color.CARD, frame_state, event, {255, 255, 255, 255})
		o.Draw_Rectangle(inner, card, radius)
	}

	if cell.focused && frame_state.is_focused {
		ring := calendar_resolve_color(o.Color.RING, frame_state, event, {59, 130, 246, 255})
		o.Draw_Rectangle({x = rect.x, y = rect.y, w = rect.w, h = f32(2)}, ring, {})
		o.Draw_Rectangle({x = rect.x, y = rect.y + rect.h - 2, w = rect.w, h = f32(2)}, ring, {})
		o.Draw_Rectangle({x = rect.x, y = rect.y, w = f32(2), h = rect.h}, ring, {})
		o.Draw_Rectangle({x = rect.x + rect.w - 2, y = rect.y, w = f32(2), h = rect.h}, ring, {})
	}
}

@(private)
calendar_draw_chrome :: proc(
	layout_id: o.UI_Id,
	frame_state: ^Calendar_State,
	event: Calendar_Event,
	style: Calendar_Style,
) {
	ctx := calendar_ctx_top()

	if !ctx.active || o.ui_layout_paint_skip(layout_id) {
		return
	}

	chrome := o.layout_calendar_result(layout_id)

	if chrome == nil {
		return
	}

	for mi in 0 ..< len(chrome.months) {
		month_chrome := chrome.months[mi]
		month := Calendar_Date_Add_Months(ctx.month, mi)
		cells, ok := Calendar_Build_Month_Grid(
			month,
			ctx.week_starts_on,
			ctx.today,
			ctx.show_outside_days,
			ctx.hidden_matcher,
			calendar_grid_disabled_matcher,
			proc(date: Calendar_Date) -> bool {
				return calendar_day_is_selected(calendar_ctx_top().selection, date)
			},
			ctx.selection.mode == .RANGE ? ctx.selection.range : {},
			ctx.focused_day,
		)

		if !ok {
			continue
		}

		for i in 0 ..< CALENDAR_GRID_DAYS {
			cell := cells[i]
			rect := month_chrome.days[i]
			hovered :=
				ctx.has_hover_day &&
				Calendar_Date_Equal(ctx.hover_day, cell.date) &&
				!cell.disabled &&
				!cell.hidden
			calendar_draw_day_cell(layout_id, rect, cell, frame_state, event, style, hovered)
		}
	}
}

@(private)
calendar_format_month_label :: proc(date: Calendar_Date) -> string {
	ctx := calendar_ctx_top()

	if ctx.active && ctx.format_month != nil {
		return ctx.format_month(date)
	}

	return Calendar_Format_Month(date)
}

@(private)
calendar_format_weekday_label :: proc(weekday: Calendar_Weekday) -> string {
	ctx := calendar_ctx_top()

	if ctx.active && ctx.format_weekday != nil {
		return ctx.format_weekday(weekday)
	}

	return Calendar_Format_Weekday(weekday)
}

@(private)
calendar_format_day_label :: proc(date: Calendar_Date) -> string {
	ctx := calendar_ctx_top()

	if ctx.active && ctx.format_day != nil {
		return ctx.format_day(date)
	}

	return Calendar_Format_Day(date)
}

@(private)
calendar_nav_prev :: proc(_: Button_Event) {
	ctx := calendar_ctx_top()

	if !ctx.active {
		return
	}

	if Calendar_Can_Navigate(ctx.month, -1, ctx.start_month, ctx.end_month) {
		calendar_set_month(ctx, Calendar_Date_Add_Months(ctx.month, -1))
	}
}

@(private)
calendar_nav_next :: proc(_: Button_Event) {
	ctx := calendar_ctx_top()

	if !ctx.active {
		return
	}

	if Calendar_Can_Navigate(ctx.month, 1, ctx.start_month, ctx.end_month) {
		calendar_set_month(ctx, Calendar_Date_Add_Months(ctx.month, 1))
	}
}

/*
Renders the calendar root. Compose month chrome with `Calendar_Month` or finer
parts inside `child`.

One tab stop owns keyboard navigation (arrows, Page Up/Down, Home/End, Space /
Enter). Month buttons own pointer navigation; day cells select according to `mode`.
*/
Calendar :: proc(props: Calendar_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	disabled := props.disabled || o.cfg_style_bool(cfg.disabled)
	rt := calendar_runtime_ensure(key)
	month_controlled := props.on_month_change != nil
	number_of_months := calendar_resolve_months(props.number_of_months)
	show_outside := calendar_resolve_show_outside(props)
	today := calendar_resolve_today(props)
	selection := calendar_selection_from_props(props)
	day_size := calendar_style_f32(props.style.day_size, CALENDAR_DEFAULT_DAY_SIZE)
	gap := calendar_style_f32(props.style.gap, CALENDAR_DEFAULT_GAP)

	month := Calendar_Start_Of_Month(props.default_month)

	if month.year == 0 {
		month = Calendar_Start_Of_Month(today)
	}

	if month_controlled {
		month = Calendar_Start_Of_Month(props.month)

		if month.year == 0 {
			month = Calendar_Start_Of_Month(today)
		}
	} else if rt != nil {
		if !rt.initialized {
			rt.month = month
			rt.initialized = true
			rt.month_set = true
		}

		if rt.month_set {
			month = rt.month
		}
	}

	month = Calendar_Clamp_Month(month, props.start_month, props.end_month)

	focused_day := Calendar_Date{}

	if rt != nil && rt.focus_set {
		focused_day = rt.focused_day
	}

	if !Calendar_Date_Valid(focused_day) {
		if selection.mode == .SINGLE && selection.has_single {
			focused_day = selection.single
		} else if selection.mode == .RANGE && selection.range.has_from {
			focused_day = selection.range.from
		} else if selection.mode == .MULTIPLE && len(selection.multiple) > 0 {
			focused_day = selection.multiple[0]
		} else {
			focused_day = today
		}
	}

	if !Calendar_Date_Valid(focused_day) {
		focused_day = Calendar_Date_Clamp_Day(month.year, month.month, 1)
	}

	if rt != nil && !rt.focus_set {
		rt.focused_day = focused_day
		rt.focus_set = true
	}

	content_w, content_h := calendar_measure(
		number_of_months,
		day_size,
		gap,
		props.show_week_numbers,
	)

	frame_state := Calendar_State {
		is_disabled       = disabled,
		is_focused        = was_focused,
		mode              = props.mode,
		month             = month,
		focused_day       = focused_day,
		selection         = selection,
		number_of_months  = number_of_months,
		week_starts_on    = props.week_starts_on,
		show_outside_days = show_outside,
		show_week_numbers = props.show_week_numbers,
		can_go_prev       = Calendar_Can_Navigate(month, -1, props.start_month, props.end_month),
		can_go_next       = Calendar_Can_Navigate(month, 1, props.start_month, props.end_month),
		content_width     = content_w,
		content_height    = content_h,
	}

	if disabled {
		cfg.disabled = set.Disabled(true)
	}

	resolved_props := props
	resolved_props.config = cfg

	event := calendar_refresh_merged(resolved_props, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(resolved_props, Calendar_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	pushed := calendar_ctx_push(
		{
			active = true,
			key = key,
			layout_id = layout_id,
			runtime = rt,
			mode = props.mode,
			month = month,
			focused_day = focused_day,
			selection = selection,
			required = props.required,
			min = props.min,
			max = props.max,
			start_month = props.start_month,
			end_month = props.end_month,
			start_date = props.start_date,
			end_date = props.end_date,
			number_of_months = number_of_months,
			week_starts_on = props.week_starts_on,
			show_outside_days = show_outside,
			show_week_numbers = props.show_week_numbers,
			today = today,
			day_size = day_size,
			gap = gap,
			month_controlled = month_controlled,
			disabled_matcher = props.disabled_matcher,
			hidden_matcher = props.hidden_matcher,
			on_month_change = props.on_month_change,
			on_select = props.on_select,
			on_day_click = props.on_day_click,
			format_month = props.format_month,
			format_weekday = props.format_weekday,
			format_day = props.format_day,
			on_key_down = props.on_key_down,
			on_key_pressed = props.on_key_pressed,
			on_key_released = props.on_key_released,
			widget_disabled = disabled,
			can_go_prev = frame_state.can_go_prev,
			can_go_next = frame_state.can_go_next,
		},
	)

	defer {
		if pushed {
			calendar_ctx_pop()
		}
	}

	props_with_keys := resolved_props
	props_with_keys.on_key_down = calendar_on_key_down
	props_with_keys.on_key_pressed = calendar_on_key_pressed
	props_with_keys.on_key_released = calendar_on_key_released

	child_proc := props.child

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = calendar_refresh_merged(resolved_props, &frame_state)
			config = frame_state.config
			should_auto_focus = widget_should_auto_focus(config, key)
		}

		if skip_layout {
			calendar_runtime_clear(key)

			return
		}

		can_interact := widget_can_interact(handlers, &frame_state)

		if can_interact && should_auto_focus {
			widget_apply_auto_focus(key, true)
			frame_state.is_focused = true
		}

		widget_register_tab_order(key, config.tabbable, can_interact)

		widget_children(
			child_proc,
			layout_id,
			config,
			frame_state,
			key,
			cfg,
			props.on_scroll,
			props.scroll_bar,
			frame_state.is_hovered,
		)
		calendar_bind_layout_chrome(layout_id, calendar_ctx_top())

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) {
		return
	}

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)

	widget_handle_interaction(
		props_with_keys,
		&frame_state,
		handlers,
		key,
		was_focused,
		config.tabbable,
		layout_id,
		rect,
		config,
	)
	widget_handle_scroll_wheel(layout_id, config, frame_state.is_hovered, key, props.on_scroll)
	scroll := o.widget_scroll_get(key)
	config.scroll_x = scroll.x
	config.scroll_y = scroll.y
	frame_state.config = config

	if widget_style_interaction_fp(&frame_state) != style_fp {
		event = calendar_refresh_merged(resolved_props, &frame_state)
		config = frame_state.config
	}

	interactive := widget_can_interact(handlers, &frame_state)
	calendar_handle_pointer(&frame_state, frame_state.is_hovered, interactive)

	if pushed {
		ctx := calendar_ctx_top()
		frame_state.month = ctx.month
		frame_state.focused_day = ctx.focused_day
		frame_state.selection = ctx.selection
		frame_state.can_go_prev = Calendar_Can_Navigate(
			frame_state.month,
			-1,
			props.start_month,
			props.end_month,
		)
		frame_state.can_go_next = Calendar_Can_Navigate(
			frame_state.month,
			1,
			props.start_month,
			props.end_month,
		)
		ctx.can_go_prev = frame_state.can_go_prev
		ctx.can_go_next = frame_state.can_go_next
	}

	if interactive {
		if widget_got_tab_focus(key) && props.on_focus != nil {
			props.on_focus(event)
		}

		if widget_lost_tab_focus(key) && props.on_blur != nil {
			props.on_blur(event)
		}
	}

	if should_auto_focus && !was_focused && props.on_focus != nil && interactive {
		props.on_focus(event)
	}

	background: o.RGBA

	if resolved_background, ok := o.style_background_rgba(config, &frame_state, event); ok {
		background = resolved_background
	}

	border: o.Bd_px

	if resolved_border, ok := o.resolve_border(config.border, &frame_state, event); ok {
		border = resolved_border
	}

	border_color: o.RGBA

	if resolved_border_color, ok := o.style_border_color_rgba(config, &frame_state, event); ok {
		border_color = resolved_border_color
	}

	radius: o.Radius_px

	if resolved_radius, ok := o.resolve_radius(config.radius, &frame_state, event); ok {
		radius = resolved_radius
	}

	o.Draw_Push_Opacity(config.opacity)
	defer o.Draw_Pop_Opacity()

	widget_draw_box_background(layout_id, rect, background, radius)
	calendar_draw_chrome(layout_id, &frame_state, event, props.style)

	if child_proc != nil {
		widget_children(
			child_proc,
			layout_id,
			config,
			frame_state,
			key,
			cfg,
			props.on_scroll,
			props.scroll_bar,
			frame_state.is_hovered,
		)
	}

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	widget_dispatch_events(props_with_keys, &frame_state, handlers, event, key, was_focused)
}
