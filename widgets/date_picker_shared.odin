package oni_widgets

import o ".."
import set "../set"
import "core:fmt"
import "core:strings"

@(private)
DATE_PICKER_CTX_STACK_MAX :: 16

@(private)
DATE_PICKER_POPOVER_GAP_PX :: f32(4)

@(private)
DATE_PICKER_POPOVER_VIEWPORT_MARGIN_PX :: f32(8)

@(private)
DATE_PICKER_DEFAULT_CALENDAR_WIDTH :: f32(320)

/*
Default calendar panel width for the composed Date_Picker content.

Uses calendar measure for `number_of_months` so multi-month range pickers get a
panel wide enough for every month column. Single-month keeps at least
`DATE_PICKER_DEFAULT_CALENDAR_WIDTH`.
*/
@(private)
date_picker_default_calendar_width :: proc(
	number_of_months: int,
	day_size_cfg: o.Cfg(o.Style_F32),
	gap_cfg: o.Cfg(o.Style_F32),
	show_week_numbers: bool,
) -> f32 {
	day_size := calendar_cfg_f32(day_size_cfg, CALENDAR_DEFAULT_DAY_SIZE)
	gap := calendar_cfg_f32(gap_cfg, CALENDAR_DEFAULT_GAP)
	months := calendar_resolve_months(number_of_months)
	content_w, _ := calendar_measure(months, day_size, gap, show_week_numbers)

	if content_w < DATE_PICKER_DEFAULT_CALENDAR_WIDTH {
		return DATE_PICKER_DEFAULT_CALENDAR_WIDTH
	}

	return content_w
}

/*
Cross-frame date picker runtime for input draft text while editing.
*/
@(private)
Date_Picker_Runtime :: struct {
	input_text:    string,
	input_format:  string,
	input_editing: bool,
}

/*
Live compound context pushed by `Date_Picker` for Trigger / Value / Input / content.
*/
@(private)
Date_Picker_Ctx :: struct {
	picker_key:         string,
	mode:               Calendar_Mode,
	open:               bool,
	disabled:           bool,
	required:           bool,
	keep_open:          bool,
	selected:           Calendar_Date,
	has_selected:       bool,
	selected_dates:     []Calendar_Date,
	selected_range:     Calendar_Range,
	month:              Calendar_Date,
	on_month_change:    proc(month: Calendar_Date),
	on_select:          proc(selection: Calendar_Selection),
	on_day_click:       proc(date: Calendar_Date),
	on_open_change:     proc(open: bool),
	min:                int,
	max:                int,
	start_month:        Calendar_Date,
	end_month:          Calendar_Date,
	start_date:         Calendar_Date,
	end_date:           Calendar_Date,
	disabled_matcher:   proc(date: Calendar_Date) -> bool,
	hidden_matcher:     proc(date: Calendar_Date) -> bool,
	hide_outside_days:  bool,
	show_week_numbers:  bool,
	week_starts_on:     Calendar_Weekday,
	number_of_months:   int,
	today:              Calendar_Date,
	day_size:           o.Cfg(o.Style_F32),
	gap:                o.Cfg(o.Style_F32),
	day:                proc(frame_state: Calendar_Day_State),
	format_month:       proc(date: Calendar_Date) -> string,
	format_weekday:     proc(weekday: Calendar_Weekday) -> string,
	format_day:         proc(date: Calendar_Date) -> string,
	format_value:       proc(selection: Calendar_Selection) -> string,
	user_child:         proc(frame_state: Date_Picker_State),
	user_content:       proc(frame_state: Date_Picker_State),
	content_frame:      Date_Picker_State,
	trigger_user_click: proc(event: Date_Picker_Trigger_Event),
	value_child:        proc(frame_state: Date_Picker_Value_State),
}

@(private)
date_picker_ctx_stack: [DATE_PICKER_CTX_STACK_MAX]Date_Picker_Ctx

@(private)
date_picker_ctx_depth: int

@(private)
date_picker_runtimes: map[string]Date_Picker_Runtime

/*
Releases heap-owned date picker runtime maps.

Called from widget `Shutdown`.
*/
date_picker_shutdown :: proc() {
	if date_picker_runtimes == nil {
		date_picker_ctx_depth = 0
		date_picker_ctx_stack = {}

		return
	}

	for key, &rt in date_picker_runtimes {
		if rt.input_text != "" {
			delete(rt.input_text)
		}

		if rt.input_format != "" {
			delete(rt.input_format)
		}

		delete(key)
	}

	delete(date_picker_runtimes)
	date_picker_runtimes = nil
	date_picker_ctx_depth = 0
	date_picker_ctx_stack = {}
}

@(private)
date_picker_runtime_ensure :: proc(key: string) -> ^Date_Picker_Runtime {
	if key == "" {
		return nil
	}

	if date_picker_runtimes == nil {
		date_picker_runtimes = make(map[string]Date_Picker_Runtime)
	}

	if _, ok := date_picker_runtimes[key]; !ok {
		date_picker_runtimes[strings.clone(key)] = {}
	}

	return &date_picker_runtimes[key]
}

@(private)
date_picker_runtime_clear :: proc(key: string) {
	if date_picker_runtimes == nil || key == "" {
		return
	}

	rt, ok := date_picker_runtimes[key]

	if !ok {
		return
	}

	if rt.input_text != "" {
		delete(rt.input_text)
	}

	if rt.input_format != "" {
		delete(rt.input_format)
	}

	for k in date_picker_runtimes {
		if k == key {
			delete_key(&date_picker_runtimes, k)
			delete(k)

			break
		}
	}
}

@(private)
date_picker_runtime_set_string :: proc(dst: ^string, value: string) {
	if dst^ == value {
		return
	}

	replacement := value != "" ? strings.clone(value) : ""

	if dst^ != "" {
		delete(dst^)
	}

	dst^ = replacement
}

@(private)
date_picker_ctx_push :: proc(ctx: Date_Picker_Ctx) {
	assert(date_picker_ctx_depth < DATE_PICKER_CTX_STACK_MAX)
	date_picker_ctx_stack[date_picker_ctx_depth] = ctx
	date_picker_ctx_depth += 1
}

@(private)
date_picker_ctx_pop :: proc() {
	assert(date_picker_ctx_depth > 0)
	date_picker_ctx_depth -= 1
	date_picker_ctx_stack[date_picker_ctx_depth] = {}
}

@(private)
date_picker_ctx_top :: proc() -> ^Date_Picker_Ctx {
	assert(date_picker_ctx_depth > 0)

	return &date_picker_ctx_stack[date_picker_ctx_depth - 1]
}

@(private)
date_picker_ctx_ok :: proc() -> bool {
	return date_picker_ctx_depth > 0
}

/*
Returns whether the current Date_Picker compound is open.
*/
Date_Picker_Is_Open :: proc() -> bool {
	if !date_picker_ctx_ok() {
		return false
	}

	return date_picker_ctx_top().open
}

/*
Returns the current selection snapshot from the active Date_Picker context.
*/
Date_Picker_Get_Selection :: proc() -> Calendar_Selection {
	if !date_picker_ctx_ok() {
		return {}
	}

	ctx := date_picker_ctx_top()

	return date_picker_selection_from_ctx(ctx)
}

/*
Applies a selection through the active Date_Picker (caller callbacks + close policy).
*/
Date_Picker_Notify_Select :: proc(selection: Calendar_Selection) {
	if !date_picker_ctx_ok() {
		return
	}

	date_picker_apply_selection(selection)
}

/*
Opens or closes the active Date_Picker popover.
*/
Date_Picker_Set_Open :: proc(open: bool) {
	if !date_picker_ctx_ok() {
		return
	}

	date_picker_set_open(open)
}

/*
Formats a selection for trigger/value display.

Single → long date; range → medium `from - to`; multiple → ISO list or count.
Uses `format_value` from the active picker when set.
*/
Date_Picker_Format_Selection :: proc(
	selection: Calendar_Selection,
	allocator := context.temp_allocator,
) -> string {
	if date_picker_ctx_ok() {
		ctx := date_picker_ctx_top()

		if ctx.format_value != nil {
			return ctx.format_value(selection)
		}
	}

	return date_picker_format_selection_default(selection, allocator)
}

@(private)
date_picker_format_selection_default :: proc(
	selection: Calendar_Selection,
	allocator := context.temp_allocator,
) -> string {
	switch selection.mode {
	case .SINGLE:
		if !selection.has_single {
			return ""
		}

		return Calendar_Format_Long(selection.single, allocator)
	case .RANGE:
		if !selection.range.has_from {
			return ""
		}

		from := Calendar_Format_Medium(selection.range.from, context.temp_allocator)

		if !selection.range.has_to {
			return from
		}

		to := Calendar_Format_Medium(selection.range.to, context.temp_allocator)

		return fmt.aprintf("%s - %s", from, to, allocator = allocator)
	case .MULTIPLE:
		if len(selection.multiple) == 0 {
			return ""
		}

		if len(selection.multiple) == 1 {
			return Calendar_Format_Long(selection.multiple[0], allocator)
		}

		return fmt.aprintf("%d selected", len(selection.multiple), allocator = allocator)
	case .NONE:
		return ""
	}

	return ""
}

@(private)
date_picker_effective_mode :: proc(mode: Calendar_Mode) -> Calendar_Mode {
	if mode == .NONE {
		return .SINGLE
	}

	return mode
}

@(private)
date_picker_selection_from_ctx :: proc(ctx: ^Date_Picker_Ctx) -> Calendar_Selection {
	mode := date_picker_effective_mode(ctx.mode)

	sel := Calendar_Selection {
		mode = mode,
	}

	switch mode {
	case .SINGLE:
		sel.single = ctx.selected
		sel.has_single = ctx.has_selected
	case .MULTIPLE:
		sel.multiple = ctx.selected_dates
	case .RANGE:
		sel.range = ctx.selected_range
	case .NONE:
	}

	return sel
}

@(private)
date_picker_selection_has_value :: proc(sel: Calendar_Selection) -> bool {
	switch sel.mode {
	case .SINGLE:
		return sel.has_single
	case .RANGE:
		return sel.range.has_from
	case .MULTIPLE:
		return len(sel.multiple) > 0
	case .NONE:
		return false
	}

	return false
}

@(private)
date_picker_should_close_after_select :: proc(
	ctx: ^Date_Picker_Ctx,
	selection: Calendar_Selection,
) -> bool {
	if ctx.keep_open {
		return false
	}

	mode := date_picker_effective_mode(ctx.mode)

	switch mode {
	case .SINGLE:
		return true
	case .RANGE:
		return selection.range.has_from && selection.range.has_to
	case .MULTIPLE, .NONE:
		return false
	}

	return false
}

@(private)
date_picker_on_popover_open_change :: proc(open: bool) {
	if !date_picker_ctx_ok() {
		return
	}

	ctx := date_picker_ctx_top()

	if ctx.disabled {
		return
	}

	if ctx.open == open {
		return
	}

	ctx.open = open

	if ctx.on_open_change != nil {
		ctx.on_open_change(open)
	}
}

@(private)
date_picker_set_open :: proc(open: bool) {
	if !date_picker_ctx_ok() {
		return
	}

	ctx := date_picker_ctx_top()

	if ctx.disabled {
		return
	}

	if ctx.open == open {
		return
	}

	ctx.open = open

	if popover_ctx_ok() {
		pctx := popover_ctx_top()

		if pctx.open != open {
			pctx.open = open
		}
	}

	if ctx.on_open_change != nil {
		ctx.on_open_change(open)
	}
}

@(private)
date_picker_toggle_open :: proc() {
	if !date_picker_ctx_ok() {
		return
	}

	if popover_ctx_ok() {
		popover_toggle_open()

		return
	}

	ctx := date_picker_ctx_top()
	date_picker_set_open(!ctx.open)
}

@(private)
date_picker_apply_selection :: proc(selection: Calendar_Selection) {
	if !date_picker_ctx_ok() {
		return
	}

	ctx := date_picker_ctx_top()

	if ctx.disabled {
		return
	}

	mode := date_picker_effective_mode(ctx.mode)
	sel := selection
	sel.mode = mode

	switch mode {
	case .SINGLE:
		ctx.selected = sel.single
		ctx.has_selected = sel.has_single
	case .MULTIPLE:
		ctx.selected_dates = sel.multiple
	case .RANGE:
		ctx.selected_range = sel.range
	case .NONE:
	}

	if ctx.on_select != nil {
		ctx.on_select(sel)
	}

	rt := date_picker_runtime_ensure(ctx.picker_key)

	if rt != nil {
		label := ""

		if mode == .SINGLE && sel.has_single {
			format := date_picker_input_runtime_format(ctx.picker_key)
			label = date_picker_input_format_date(sel.single, format)
		} else if date_picker_selection_has_value(sel) {
			label = date_picker_format_selection_default(sel, context.temp_allocator)
		}

		date_picker_runtime_set_string(&rt.input_text, label)
		rt.input_editing = false
	}

	if date_picker_should_close_after_select(ctx, sel) {
		date_picker_set_open(false)
	}
}

@(private)
date_picker_on_calendar_select :: proc(selection: Calendar_Selection) {
	date_picker_apply_selection(selection)
}

/*
Marks the nested Popover pointer as owned so calendar / content hits do not dismiss.
*/
@(private)
date_picker_note_pointer :: proc() {
	if popover_ctx_ok() {
		popover_note_pointer()
	}
}

@(private)
fmt_date_picker_popover_id :: proc(picker_key: string) -> string {
	return fmt.tprintf("%s/__date_picker_popover", picker_key)
}

@(private)
fmt_date_picker_calendar_id :: proc(picker_key: string) -> string {
	return fmt.tprintf("%s/calendar", picker_key)
}

@(private)
date_picker_popover_content_config :: proc() -> Popover_Content_Props_Config {
	return Popover_Content_Props_Config {
		// Must be sized (FIT or explicit). Unset width stretches to the viewport
		// as a POPOVER layer root; layout_resolve_anchors then clamps x off-screen.
		width                = set.Width(.FIT),
		height               = set.Height(.FIT),
		overflow_y           = set.Overflow_Y(.HIDDEN),
		direction            = set.Direction(.VERTICAL),
		padding              = set.Padding(f32(0)),
		background           = set.Background(o.Color.BACKGROUND),
		radius               = set.Radius(f32(8)),
		anchor_align         = .START,
		match_trigger_width  = false,
		anchor_gap           = DATE_PICKER_POPOVER_GAP_PX,
		viewport_margin      = DATE_PICKER_POPOVER_VIEWPORT_MARGIN_PX,
	}
}

@(private)
date_picker_default_content :: proc(fs: Date_Picker_State) {
	_ = fs
	ctx := date_picker_ctx_top()
	mode := date_picker_effective_mode(ctx.mode)
	cal_id := fmt_date_picker_calendar_id(ctx.picker_key)
	cal_w := date_picker_default_calendar_width(
		ctx.number_of_months,
		ctx.day_size,
		ctx.gap,
		ctx.show_week_numbers,
	)

	Calendar(
		{
			config = {
				id = cal_id,
				width = set.Width(cal_w),
				border = set.Border(f32(1)),
				mode = mode,
				selected = ctx.selected,
				has_selected = ctx.has_selected,
				selected_dates = ctx.selected_dates,
				selected_range = ctx.selected_range,
				month = ctx.month,
				required = ctx.required,
				min = ctx.min,
				max = ctx.max,
				start_month = ctx.start_month,
				end_month = ctx.end_month,
				start_date = ctx.start_date,
				end_date = ctx.end_date,
				hide_outside_days = ctx.hide_outside_days,
				show_week_numbers = ctx.show_week_numbers,
				week_starts_on = ctx.week_starts_on,
				number_of_months = ctx.number_of_months,
				today = ctx.today,
				disabled = set.Disabled(ctx.disabled),
				day_size = ctx.day_size,
				gap = ctx.gap,
			},
			on_month_change = ctx.on_month_change,
			on_select = date_picker_on_calendar_select,
			on_day_click = ctx.on_day_click,
			disabled_matcher = ctx.disabled_matcher,
			hidden_matcher = ctx.hidden_matcher,
			day = ctx.day,
			format_month = ctx.format_month,
			format_weekday = ctx.format_weekday,
			format_day = ctx.format_day,
			child = Calendar_Default_Months,
		},
	)
}

@(private)
date_picker_compound_child :: proc(fs: Date_Picker_State) {
	ctx := date_picker_ctx_top()
	ctx.content_frame = fs
	popover_id := ctx.picker_key != "" ? fmt_date_picker_popover_id(ctx.picker_key) : ""

	popover_cfg := Popover_Config {
		id = popover_id,
		direction = set.Direction(.VERTICAL),
		gap_y = set.Gap_Y(u16(0)),
		open = ctx.open,
	}

	if ctx.disabled {
		popover_cfg.disabled = set.Disabled(true)
	}

	Popover(
		{
			config = popover_cfg,
			on_open_change = date_picker_on_popover_open_change,
			child = date_picker_popover_child,
		},
	)
}

@(private)
date_picker_popover_child :: proc(_: Popover_State) {
	ctx := date_picker_ctx_top()

	if ctx.user_child != nil {
		ctx.user_child(ctx.content_frame)
	}

	Popover_Content(
		{
			config = date_picker_popover_content_config(),
			child = date_picker_popover_content_child,
		},
	)
}

@(private)
date_picker_popover_content_child :: proc(_: Popover_Content_Props_State) {
	ctx := date_picker_ctx_top()

	if ctx.user_content != nil {
		ctx.user_content(ctx.content_frame)
	} else {
		date_picker_default_content(ctx.content_frame)
	}
}

@(private)
date_picker_trigger_on_click :: proc(ev: Date_Picker_Trigger_Event) {
	date_picker_toggle_open()

	if date_picker_ctx_ok() {
		user := date_picker_ctx_top().trigger_user_click

		if user != nil {
			user(ev)
		}
	}
}

@(private)
date_picker_handle_keys :: proc() {
	if !date_picker_ctx_ok() {
		return
	}

	ctx := date_picker_ctx_top()

	if ctx.disabled {
		return
	}

	esc := o.w_ctx.keys[int(o.Scancode.ESCAPE)]

	if ctx.open && esc.pressed && !o.shortcut_key_consumed(.ESCAPE) {
		date_picker_set_open(false)
		o.state.shortcuts.consumed_keys[int(o.Scancode.ESCAPE)] = true

		return
	}

	down := o.w_ctx.keys[int(o.Scancode.DOWN)]

	if down.pressed && !o.shortcut_key_consumed(.DOWN) {
		if !ctx.open {
			date_picker_set_open(true)
			o.state.shortcuts.consumed_keys[int(o.Scancode.DOWN)] = true
		}
	}
}

@(private)
date_picker_value_label_child :: proc(fs: Date_Picker_Value_State) {
	ctx_child: proc(frame_state: Date_Picker_Value_State)

	if date_picker_ctx_ok() {
		ctx_child = date_picker_ctx_top().value_child
	}

	if ctx_child != nil {
		ctx_child(fs)

		return
	}

	text_cfg := Text_Config {
		text = fs.text,
	}

	if !fs.has_value {
		text_cfg.color = set.Color(.MUTED_FOREGROUND)
	}

	Text({config = text_cfg})
}

@(private)
date_picker_resolve_value_text :: proc(placeholder: string) -> (text: string, has_value: bool) {
	if !date_picker_ctx_ok() {
		return placeholder, false
	}

	ctx := date_picker_ctx_top()
	sel := date_picker_selection_from_ctx(ctx)

	if !date_picker_selection_has_value(sel) {
		return placeholder, false
	}

	return Date_Picker_Format_Selection(sel), true
}
