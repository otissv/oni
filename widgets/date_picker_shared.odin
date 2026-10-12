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
Cross-frame date picker runtime for input draft text while editing.
*/
@(private)
Date_Picker_Runtime :: struct {
	input_text:    string,
	input_editing: bool,
}

/*
Live compound context pushed by `Date_Picker` for Trigger / Value / Input / content.
*/
@(private)
Date_Picker_Ctx :: struct {
	picker_key:           string,
	mode:                 Calendar_Mode,
	open:                 bool,
	disabled:             bool,
	required:             bool,
	keep_open:            bool,
	selected:             Calendar_Date,
	has_selected:         bool,
	selected_dates:       []Calendar_Date,
	selected_range:       Calendar_Range,
	month:                Calendar_Date,
	on_month_change:      proc(month: Calendar_Date),
	on_select:            proc(selection: Calendar_Selection),
	on_day_click:         proc(date: Calendar_Date),
	on_open_change:       proc(open: bool),
	min:                  int,
	max:                  int,
	start_month:          Calendar_Date,
	end_month:            Calendar_Date,
	start_date:           Calendar_Date,
	end_date:             Calendar_Date,
	disabled_matcher:     proc(date: Calendar_Date) -> bool,
	hidden_matcher:       proc(date: Calendar_Date) -> bool,
	hide_outside_days:    bool,
	show_week_numbers:    bool,
	week_starts_on:       Calendar_Weekday,
	number_of_months:     int,
	today:                Calendar_Date,
	calendar_style:       Calendar_Style,
	format_month:         proc(date: Calendar_Date) -> string,
	format_weekday:       proc(weekday: Calendar_Weekday) -> string,
	format_day:           proc(date: Calendar_Date) -> string,
	format_value:         proc(selection: Calendar_Selection) -> string,
	trigger_key:          string,
	trigger_layout_id:    o.UI_Id,
	trigger_rect:         o.Rect,
	has_trigger:          bool,
	pointer_owned:        bool,
	user_child:           proc(frame_state: Date_Picker_State),
	user_content:         proc(frame_state: Date_Picker_State),
	content_frame:        Date_Picker_State,
	trigger_user_click:   proc(event: Date_Picker_Trigger_Event),
	value_child:          proc(frame_state: Date_Picker_Value_State),
	input_user_change:    proc(event: Date_Picker_Input_Event, text: string),
	input_user_submit:    proc(event: Date_Picker_Input_Event),
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

	if ctx.on_open_change != nil {
		ctx.on_open_change(open)
	}
}

@(private)
date_picker_toggle_open :: proc() {
	if !date_picker_ctx_ok() {
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
			label = Calendar_Format_ISO(sel.single, context.temp_allocator)
		} else if date_picker_selection_has_value(sel) {
			label = date_picker_format_selection_default(sel, context.temp_allocator)
		}

		date_picker_runtime_set_string(&rt.input_text, label)

		if mode == .SINGLE && rt.input_editing && rt.input_text == label {
			rt.input_editing = false
		}
	}

	if date_picker_should_close_after_select(ctx, sel) {
		date_picker_set_open(false)
	}
}

@(private)
date_picker_on_calendar_select :: proc(selection: Calendar_Selection) {
	date_picker_apply_selection(selection)
}

@(private)
date_picker_note_pointer :: proc() {
	if !date_picker_ctx_ok() {
		return
	}

	date_picker_ctx_top().pointer_owned = true
}

@(private)
date_picker_set_trigger :: proc(key: string, layout_id: o.UI_Id, rect: o.Rect) {
	if !date_picker_ctx_ok() {
		return
	}

	ctx := date_picker_ctx_top()
	ctx.trigger_key = key
	ctx.trigger_layout_id = layout_id
	ctx.trigger_rect = rect
	ctx.has_trigger = true
}

@(private)
fmt_date_picker_content_id :: proc(picker_key: string) -> string {
	return fmt.tprintf("%s/__date_picker_content", picker_key)
}

@(private)
fmt_date_picker_calendar_id :: proc(picker_key: string) -> string {
	return fmt.tprintf("%s/calendar", picker_key)
}

@(private)
date_picker_content_theme_config :: proc(trigger_rect: o.Rect) -> o.Widget_Config {
	return o.Widget_Config {
		kind = .RECT,
		space = set.Space(.POPOVER),
		position = set.Position(.ABSOLUTE),
		x = set.F32(trigger_rect.x),
		y = set.F32(trigger_rect.y + trigger_rect.h + DATE_PICKER_POPOVER_GAP_PX),
		overflow_y = set.Overflow_Y(.HIDDEN),
		direction = set.Direction(.VERTICAL),
		padding = set.Padding(f32(0)),
		background = set.Background(o.Color.BACKGROUND),
		border = set.Border(f32(1)),
		border_color = set.Border_color(o.Color.BORDER),
		radius = set.Radius(f32(8)),
		z_index = set.Z_Index(f32(50)),
	}
}

@(private)
date_picker_default_calendar_months :: proc(_: Calendar_State) {
	ctx := date_picker_ctx_top()
	count := ctx.number_of_months

	if count < 1 {
		count = 1
	}

	if count > CALENDAR_MAX_MONTHS {
		count = CALENDAR_MAX_MONTHS
	}

	for i in 0 ..< count {
		month_id := fmt.tprintf("%s/calendar/month_%d", ctx.picker_key, i)
		Calendar_Month({config = {id = month_id}, month_index = i})
	}
}

@(private)
date_picker_default_content :: proc(fs: Date_Picker_State) {
	_ = fs
	ctx := date_picker_ctx_top()
	mode := date_picker_effective_mode(ctx.mode)
	cal_id := fmt_date_picker_calendar_id(ctx.picker_key)

	Calendar(
		{
			config = {
				id = cal_id,
				width = set.Width(DATE_PICKER_DEFAULT_CALENDAR_WIDTH),
			},
			mode = mode,
			selected = ctx.selected,
			has_selected = ctx.has_selected,
			selected_dates = ctx.selected_dates,
			selected_range = ctx.selected_range,
			month = ctx.month,
			on_month_change = ctx.on_month_change,
			on_select = date_picker_on_calendar_select,
			on_day_click = ctx.on_day_click,
			required = ctx.required,
			min = ctx.min,
			max = ctx.max,
			start_month = ctx.start_month,
			end_month = ctx.end_month,
			start_date = ctx.start_date,
			end_date = ctx.end_date,
			disabled_matcher = ctx.disabled_matcher,
			hidden_matcher = ctx.hidden_matcher,
			hide_outside_days = ctx.hide_outside_days,
			show_week_numbers = ctx.show_week_numbers,
			week_starts_on = ctx.week_starts_on,
			number_of_months = ctx.number_of_months,
			today = ctx.today,
			disabled = ctx.disabled,
			style = ctx.calendar_style,
			format_month = ctx.format_month,
			format_weekday = ctx.format_weekday,
			format_day = ctx.format_day,
			child = date_picker_default_calendar_months,
		},
	)
}

@(private)
date_picker_popover_child :: proc(_: Popover_State) {
	ctx := date_picker_ctx_top()

	if ctx.user_content != nil {
		ctx.user_content(ctx.content_frame)
	} else {
		date_picker_default_content(ctx.content_frame)
	}
}

@(private)
date_picker_popover_mouse_enter :: proc(_: Popover_Event) {
	date_picker_note_pointer()
}

@(private)
date_picker_render_content :: proc(frame_state: Date_Picker_State) {
	ctx := date_picker_ctx_top()

	if !ctx.open {
		return
	}

	trigger_rect := ctx.trigger_rect

	if !ctx.has_trigger {
		trigger_rect = {}
	}

	cfg := date_picker_content_theme_config(trigger_rect)
	content_id := ctx.picker_key != "" ? fmt_date_picker_content_id(ctx.picker_key) : ""

	if content_id != "" {
		cfg.id = content_id
	}

	ctx.content_frame = frame_state

	Popover(
		{
			config = cfg,
			child = date_picker_popover_child,
			on_mouse_enter = date_picker_popover_mouse_enter,
		},
	)

	if o.ui_pass() == .Layout && ctx.trigger_key != "" {
		content_layout_id := o.ui_id(content_id)
		o.layout_anchor_popup(
			ctx.trigger_layout_id,
			content_layout_id,
			DATE_PICKER_POPOVER_GAP_PX,
			DATE_PICKER_POPOVER_VIEWPORT_MARGIN_PX,
		)
	}

	if o.ui_pass() == .Draw {
		content_layout_id := o.ui_id(content_id != "" ? content_id : o.element_key(cfg.id))
		content_rect := o.ui_layout_rect(content_layout_id)

		if o.pointer_hits(content_layout_id, content_rect, .POPOVER) {
			date_picker_note_pointer()
		}
	}
}

@(private)
date_picker_compound_child :: proc(fs: Date_Picker_State) {
	ctx := date_picker_ctx_top()

	if ctx.user_child != nil {
		ctx.user_child(fs)
	}

	date_picker_render_content(fs)
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
