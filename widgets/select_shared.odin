package oni_widgets

import o ".."
import set "../set"
import "core:fmt"
import "core:strings"

@(private)
SELECT_CTX_STACK_MAX :: 16

@(private)
SELECT_OPTIONS_MAX :: 256

@(private)
SELECT_VALUES_MAX :: 64

@(private)
SELECT_OPTION_ROW_PX :: f32(32)

/*
Per-option registration collected while a Select content tree runs.
*/
@(private)
Select_Option_Entry :: struct {
	value:      string,
	text:       string,
	disabled:   bool,
	element_id: string,
}

/*
Cross-frame select runtime for uncontrolled open/value and cached value labels.
*/
@(private)
Select_Runtime :: struct {
	open:         bool,
	value:        string,
	value_label:  string,
	values:       [dynamic]string,
	value_labels: [dynamic]string,
	highlight:    int,
	value_set:    bool,
}

/*
Live compound context pushed by `Select` for Trigger / Value / Option parts.
*/
@(private)
Select_Ctx :: struct {
	select_key:           string,
	value:                string,
	value_label:          string,
	values:               [SELECT_VALUES_MAX]string,
	value_labels:         [SELECT_VALUES_MAX]string,
	value_count:          int,
	open:                 bool,
	disabled:             bool,
	required:             bool,
	multiple:             bool,
	size:                 u8,
	autocomplete:         string,
	listbox:              bool,
	name:                 string,
	on_value_change:      proc(value: string),
	on_values_change:     proc(values: []string),
	on_open_change:       proc(open: bool),
	options:              [SELECT_OPTIONS_MAX]Select_Option_Entry,
	option_count:         int,
	highlight:            int,
	trigger_key:          string,
	trigger_rect:         o.Rect,
	has_trigger:          bool,
	pointer_owned:        bool,
	value_controlled:     bool,
	open_controlled:      bool,
	user_child:           proc(frame_state: Select_State),
	user_content:         proc(frame_state: Select_State),
	content_frame:        Select_State,
	trigger_user_click:   proc(event: Select_Trigger_Event),
	value_child:          proc(frame_state: Select_Value_State),
	option_child:         proc(frame_state: Option_State),
	option_user_click:    proc(event: Option_Event),
}

@(private)
select_ctx_stack: [SELECT_CTX_STACK_MAX]Select_Ctx

@(private)
select_ctx_depth: int

@(private)
select_runtimes: map[string]Select_Runtime

/*
Releases heap-owned select runtime maps.

Called from widget `Shutdown`.
*/
select_shutdown :: proc() {
	if select_runtimes == nil do return

	for key, &rt in select_runtimes {
		if rt.value != "" {
			delete(rt.value)
		}

		if rt.value_label != "" {
			delete(rt.value_label)
		}

		for v in rt.values {
			if v != "" {
				delete(v)
			}
		}

		for lab in rt.value_labels {
			if lab != "" {
				delete(lab)
			}
		}

		delete(rt.values)
		delete(rt.value_labels)
		delete(key)
	}

	delete(select_runtimes)
	select_runtimes = nil
	select_ctx_depth = 0
	select_ctx_stack = {}
}

@(private)
select_runtime_ensure :: proc(key: string) -> ^Select_Runtime {
	if key == "" {
		return nil
	}

	if select_runtimes == nil {
		select_runtimes = make(map[string]Select_Runtime)
	}

	if _, ok := select_runtimes[key]; !ok {
		select_runtimes[strings.clone(key)] = {}
	}

	return &select_runtimes[key]
}

@(private)
select_runtime_set_string :: proc(dst: ^string, value: string) {
	if dst^ == value do return

	if dst^ != "" {
		delete(dst^)
	}

	dst^ = value != "" ? strings.clone(value) : ""
}

@(private)
select_ctx_push :: proc(ctx: Select_Ctx) {
	assert(select_ctx_depth < SELECT_CTX_STACK_MAX)
	select_ctx_stack[select_ctx_depth] = ctx
	select_ctx_depth += 1
}

@(private)
select_ctx_pop :: proc() {
	assert(select_ctx_depth > 0)
	select_ctx_depth -= 1
	select_ctx_stack[select_ctx_depth] = {}
}

@(private)
select_ctx_top :: proc() -> ^Select_Ctx {
	assert(select_ctx_depth > 0)
	return &select_ctx_stack[select_ctx_depth - 1]
}

@(private)
select_ctx_ok :: proc() -> bool {
	return select_ctx_depth > 0
}

/*
Returns whether the current Select compound is open.

Reads the live context so Trigger toggles are visible to later siblings in the
same draw pass. Listbox selects are always treated as open for content.
*/
Select_Is_Open :: proc() -> bool {
	if !select_ctx_ok() do return false

	ctx := select_ctx_top()

	return ctx.open || ctx.listbox
}

/*
Returns the current Select value, or "" when none / outside a Select.

In multiple mode this is the first selected value (use `Select_Get_Values`).
*/
Select_Get_Value :: proc() -> string {
	if !select_ctx_ok() do return ""

	ctx := select_ctx_top()

	if ctx.multiple {
		if ctx.value_count == 0 do return ""

		return ctx.values[0]
	}

	return ctx.value
}

/*
Returns a temp-allocator slice of selected values (multiple mode), or a
single-element slice when one value is selected.
*/
Select_Get_Values :: proc() -> []string {
	if !select_ctx_ok() do return {}

	ctx := select_ctx_top()

	if ctx.multiple {
		if ctx.value_count == 0 do return {}

		out := make([]string, ctx.value_count, context.temp_allocator)

		for i in 0 ..< ctx.value_count {
			out[i] = ctx.values[i]
		}

		return out
	}

	if ctx.value == "" do return {}

	out := make([]string, 1, context.temp_allocator)
	out[0] = ctx.value

	return out
}

@(private)
select_is_listbox :: proc(multiple: bool, size: u8) -> bool {
	return multiple || size > 1
}

@(private)
select_visible_rows :: proc(multiple: bool, size: u8) -> u8 {
	if size > 0 do return size

	if multiple do return 4

	return 1
}

@(private)
select_note_pointer :: proc() {
	if !select_ctx_ok() do return

	select_ctx_top().pointer_owned = true
}

@(private)
select_set_trigger :: proc(key: string, rect: o.Rect) {
	if !select_ctx_ok() do return

	ctx := select_ctx_top()
	ctx.trigger_key = key
	ctx.trigger_rect = rect
	ctx.has_trigger = true
}

@(private)
select_register_option :: proc(
	value, text, element_id: string,
	disabled: bool,
) -> int {
	if !select_ctx_ok() do return -1

	ctx := select_ctx_top()

	if ctx.option_count >= SELECT_OPTIONS_MAX do return -1

	idx := ctx.option_count
	ctx.options[idx] = {
		value      = value,
		text       = text,
		disabled   = disabled,
		element_id = element_id,
	}
	ctx.option_count += 1

	if select_ctx_has_value(ctx, value) {
		select_cache_value_label_for(ctx, value, text)
	}

	return idx
}

@(private)
select_ctx_has_value :: proc(ctx: ^Select_Ctx, value: string) -> bool {
	if value == "" do return false

	if ctx.multiple {
		for i in 0 ..< ctx.value_count {
			if ctx.values[i] == value do return true
		}

		return false
	}

	return ctx.value == value
}

@(private)
select_cache_value_label :: proc(ctx: ^Select_Ctx, text: string) {
	ctx.value_label = text
	rt := select_runtime_ensure(ctx.select_key)

	if rt == nil do return

	select_runtime_set_string(&rt.value_label, text)
}

@(private)
select_cache_value_label_for :: proc(ctx: ^Select_Ctx, value, text: string) {
	if !ctx.multiple {
		select_cache_value_label(ctx, text)

		return
	}

	for i in 0 ..< ctx.value_count {
		if ctx.values[i] != value do continue

		ctx.value_labels[i] = text
		rt := select_runtime_ensure(ctx.select_key)

		if rt == nil || i >= len(rt.value_labels) do return

		select_runtime_set_string(&rt.value_labels[i], text)

		return
	}
}

@(private)
select_resolve_value_label :: proc(ctx: ^Select_Ctx) -> string {
	if ctx.multiple {
		if ctx.value_count == 0 do return ""

		parts := make([]string, ctx.value_count, context.temp_allocator)

		for i in 0 ..< ctx.value_count {
			lab := ctx.value_labels[i]

			if lab == "" {
				lab = ctx.values[i]
			}

			parts[i] = lab
		}

		joined, _ := strings.join(parts, ", ", context.temp_allocator)

		return joined
	}

	if ctx.value == "" do return ""

	if ctx.value_label != "" do return ctx.value_label

	rt := select_runtime_ensure(ctx.select_key)

	if rt != nil && rt.value_label != "" {
		return rt.value_label
	}

	return ctx.value
}

@(private)
select_has_selection :: proc(ctx: ^Select_Ctx) -> bool {
	if ctx.multiple do return ctx.value_count > 0

	return ctx.value != ""
}

@(private)
select_copy_values_into_ctx :: proc(ctx: ^Select_Ctx, values: []string) {
	ctx.value_count = 0

	for v in values {
		if ctx.value_count >= SELECT_VALUES_MAX do break

		ctx.values[ctx.value_count] = v
		ctx.value_labels[ctx.value_count] = ""
		ctx.value_count += 1
	}
}

@(private)
select_load_runtime_values :: proc(ctx: ^Select_Ctx, rt: ^Select_Runtime) {
	ctx.value_count = 0

	if rt == nil do return

	for i in 0 ..< len(rt.values) {
		if ctx.value_count >= SELECT_VALUES_MAX do break

		ctx.values[ctx.value_count] = rt.values[i]
		lab := ""

		if i < len(rt.value_labels) {
			lab = rt.value_labels[i]
		}

		ctx.value_labels[ctx.value_count] = lab
		ctx.value_count += 1
	}
}

@(private)
select_notify_values_change :: proc(ctx: ^Select_Ctx) {
	if ctx.on_values_change == nil do return

	out := make([]string, ctx.value_count, context.temp_allocator)

	for i in 0 ..< ctx.value_count {
		out[i] = ctx.values[i]
	}

	ctx.on_values_change(out)
}

@(private)
select_runtime_replace_values :: proc(rt: ^Select_Runtime, values, labels: []string) {
	for v in rt.values {
		if v != "" {
			delete(v)
		}
	}

	for lab in rt.value_labels {
		if lab != "" {
			delete(lab)
		}
	}

	clear(&rt.values)
	clear(&rt.value_labels)

	for i in 0 ..< len(values) {
		append(&rt.values, strings.clone(values[i]))
		lab := ""

		if i < len(labels) {
			lab = labels[i]
		}

		if lab == "" {
			lab = values[i]
		}

		append(&rt.value_labels, strings.clone(lab))
	}

	rt.value_set = true
}

@(private)
select_set_open :: proc(open: bool) {
	if !select_ctx_ok() do return

	ctx := select_ctx_top()

	if ctx.disabled || ctx.listbox do return

	if ctx.open == open do return

	ctx.open = open

	if !open {
		ctx.highlight = -1
	} else if ctx.multiple {
		ctx.highlight = ctx.value_count > 0 ? select_index_for_value(ctx, ctx.values[0]) : -1
	} else {
		ctx.highlight = select_index_for_value(ctx, ctx.value)
	}

	if ctx.open_controlled {
		if ctx.on_open_change != nil {
			ctx.on_open_change(open)
		}
	} else {
		rt := select_runtime_ensure(ctx.select_key)

		if rt != nil {
			rt.open = open
			rt.highlight = ctx.highlight
		}

		if ctx.on_open_change != nil {
			ctx.on_open_change(open)
		}
	}
}

@(private)
select_toggle_open :: proc() {
	if !select_ctx_ok() do return

	ctx := select_ctx_top()

	if ctx.listbox do return

	select_set_open(!ctx.open)
}

@(private)
select_set_value :: proc(value, text: string) {
	if !select_ctx_ok() do return

	ctx := select_ctx_top()

	if ctx.disabled do return

	if ctx.multiple {
		select_toggle_value(value, text)

		return
	}

	label := text

	if label == "" {
		label = value
	}

	ctx.value = value
	select_cache_value_label(ctx, label)

	if ctx.value_controlled {
		if ctx.on_value_change != nil {
			ctx.on_value_change(value)
		}
	} else {
		rt := select_runtime_ensure(ctx.select_key)

		if rt != nil {
			select_runtime_set_string(&rt.value, value)
			select_runtime_set_string(&rt.value_label, label)
			rt.value_set = true
		}

		if ctx.on_value_change != nil {
			ctx.on_value_change(value)
		}
	}

	if !ctx.listbox {
		select_set_open(false)
	}
}

@(private)
select_toggle_value :: proc(value, text: string) {
	if !select_ctx_ok() do return

	ctx := select_ctx_top()

	if ctx.disabled || value == "" do return

	label := text

	if label == "" {
		label = value
	}

	found := -1

	for i in 0 ..< ctx.value_count {
		if ctx.values[i] == value {
			found = i

			break
		}
	}

	if found >= 0 {
		for i in found ..< ctx.value_count - 1 {
			ctx.values[i] = ctx.values[i + 1]
			ctx.value_labels[i] = ctx.value_labels[i + 1]
		}

		ctx.value_count -= 1
	} else if ctx.value_count < SELECT_VALUES_MAX {
		ctx.values[ctx.value_count] = value
		ctx.value_labels[ctx.value_count] = label
		ctx.value_count += 1
	}

	if ctx.value_controlled {
		select_notify_values_change(ctx)
	} else {
		rt := select_runtime_ensure(ctx.select_key)

		if rt != nil {
			vals := make([]string, ctx.value_count, context.temp_allocator)
			labs := make([]string, ctx.value_count, context.temp_allocator)

			for i in 0 ..< ctx.value_count {
				vals[i] = ctx.values[i]
				labs[i] = ctx.value_labels[i]
			}

			select_runtime_replace_values(rt, vals, labs)
		}

		select_notify_values_change(ctx)
	}
}

@(private)
select_index_for_value :: proc(ctx: ^Select_Ctx, value: string) -> int {
	if value == "" do return -1

	for i in 0 ..< ctx.option_count {
		if ctx.options[i].value == value {
			return i
		}
	}

	return -1
}

@(private)
select_content_is_active :: proc(ctx: ^Select_Ctx) -> bool {
	return ctx.listbox || ctx.open
}

@(private)
select_move_highlight :: proc(delta: int) {
	if !select_ctx_ok() do return

	ctx := select_ctx_top()

	if !select_content_is_active(ctx) || ctx.option_count == 0 do return

	start := ctx.highlight

	if start < 0 {
		start = delta > 0 ? -1 : ctx.option_count
	}

	idx := start

	for _ in 0 ..< ctx.option_count {
		idx += delta

		if idx < 0 {
			idx = ctx.option_count - 1
		} else if idx >= ctx.option_count {
			idx = 0
		}

		if !ctx.options[idx].disabled {
			ctx.highlight = idx
			rt := select_runtime_ensure(ctx.select_key)

			if rt != nil {
				rt.highlight = idx
			}

			return
		}
	}
}

@(private)
select_commit_highlight :: proc() {
	if !select_ctx_ok() do return

	ctx := select_ctx_top()

	if !select_content_is_active(ctx) do return

	if ctx.highlight < 0 || ctx.highlight >= ctx.option_count do return

	opt := ctx.options[ctx.highlight]

	if opt.disabled do return

	select_set_value(opt.value, opt.text)
}

@(private)
select_handle_typing_keys :: proc() {
	if !select_ctx_ok() do return

	ctx := select_ctx_top()

	if ctx.disabled do return

	active := select_content_is_active(ctx)
	esc := o.w_ctx.keys[int(o.Scancode.ESCAPE)]

	if active && !ctx.listbox && esc.pressed && !o.shortcut_key_consumed(.ESCAPE) {
		select_set_open(false)
		o.state.shortcuts.consumed_keys[int(o.Scancode.ESCAPE)] = true

		return
	}

	down := o.w_ctx.keys[int(o.Scancode.DOWN)]
	up := o.w_ctx.keys[int(o.Scancode.UP)]

	if down.pressed && !o.shortcut_key_consumed(.DOWN) {
		if !active {
			select_set_open(true)
		} else {
			select_move_highlight(1)
		}

		o.state.shortcuts.consumed_keys[int(o.Scancode.DOWN)] = true
	}

	if up.pressed && !o.shortcut_key_consumed(.UP) {
		if !active {
			select_set_open(true)
		} else {
			select_move_highlight(-1)
		}

		o.state.shortcuts.consumed_keys[int(o.Scancode.UP)] = true
	}

	if active {
		enter := o.w_ctx.keys[int(o.Scancode.RETURN)]

		if enter.pressed && !o.shortcut_key_consumed(.RETURN) {
			select_commit_highlight()
			o.state.shortcuts.consumed_keys[int(o.Scancode.RETURN)] = true
		}
	}
}

@(private)
select_content_theme_config :: proc(trigger_rect: o.Rect, listbox: bool, rows: u8) -> o.Widget_Config {
	height := f32(rows) * SELECT_OPTION_ROW_PX + 8

	if listbox {
		return o.Widget_Config {
			kind = .RECT,
			direction = set.Direction(.VERTICAL),
			gap_y = set.Gap_Y(u16(2)),
			padding = set.Padding(f32(4)),
			width = set.Width(max(trigger_rect.w, f32(240))),
			height = set.Height(height),
			overflow_y = set.Overflow_Y(.SCROLL),
			background = set.Background(o.Color.BACKGROUND),
			border = set.Border(f32(1)),
			border_color = set.Border_color(o.Color.BORDER),
			radius = set.Radius(f32(6)),
		}
	}

	return o.Widget_Config {
		kind = .RECT,
		space = set.Space(.POPOVER),
		position = set.Position(.ABSOLUTE),
		x = set.F32(trigger_rect.x),
		y = set.F32(trigger_rect.y + trigger_rect.h + 4),
		width = set.Width(max(trigger_rect.w, f32(120))),
		height = set.Height(height),
		overflow_y = set.Overflow_Y(.SCROLL),
		direction = set.Direction(.VERTICAL),
		gap_y = set.Gap_Y(u16(2)),
		padding = set.Padding(f32(4)),
		background = set.Background(o.Color.BACKGROUND),
		border = set.Border(f32(1)),
		border_color = set.Border_color(o.Color.BORDER),
		radius = set.Radius(f32(6)),
		z_index = set.Z_Index(f32(50)),
	}
}

@(private)
select_compound_child :: proc(fs: Select_State) {
	ctx := select_ctx_top()

	if ctx.user_child != nil {
		ctx.user_child(fs)
	}

	select_render_content(fs)
}

@(private)
select_popover_child :: proc(_: Popover_State) {
	ctx := select_ctx_top()

	if ctx.user_content != nil {
		ctx.user_content(ctx.content_frame)
	}
}

@(private)
select_popover_mouse_enter :: proc(_: Popover_Event) {
	select_note_pointer()
}

@(private)
select_listbox_child :: proc(_: Rectangle_State) {
	ctx := select_ctx_top()

	if ctx.user_content != nil {
		ctx.user_content(ctx.content_frame)
	}
}

@(private)
select_listbox_mouse_enter :: proc(_: Rectangle_Event) {
	select_note_pointer()
}

@(private)
select_render_content :: proc(frame_state: Select_State) {
	ctx := select_ctx_top()

	if ctx.user_content == nil do return

	if !select_content_is_active(ctx) do return

	trigger_rect := ctx.trigger_rect

	if !ctx.has_trigger {
		trigger_rect = {}
	}

	rows := select_visible_rows(ctx.multiple, ctx.size)
	cfg := select_content_theme_config(trigger_rect, ctx.listbox, rows)
	content_id := ctx.select_key != "" ? fmt_select_content_id(ctx.select_key) : ""

	if content_id != "" {
		cfg.id = content_id
	}

	ctx.content_frame = frame_state

	if ctx.listbox {
		Rectangle({
			config = cfg,
			child = select_listbox_child,
			on_mouse_enter = select_listbox_mouse_enter,
		})

		if o.ui_pass() == .Draw {
			content_layout_id := o.ui_id(content_id != "" ? content_id : o.element_key(cfg.id))
			content_rect := o.ui_layout_rect(content_layout_id)

			if o.pointer_hits(content_layout_id, content_rect, .SCREEN) {
				select_note_pointer()
			}
		}

		return
	}

	Popover({
		config = cfg,
		child = select_popover_child,
		on_mouse_enter = select_popover_mouse_enter,
	})

	if o.ui_pass() == .Draw {
		content_layout_id := o.ui_id(content_id != "" ? content_id : o.element_key(cfg.id))
		content_rect := o.ui_layout_rect(content_layout_id)

		if o.pointer_hits(content_layout_id, content_rect, .POPOVER) {
			select_note_pointer()
		}
	}
}

@(private)
fmt_select_content_id :: proc(select_key: string) -> string {
	return fmt.tprintf("%s/__select_content", select_key)
}

@(private)
select_trigger_on_click :: proc(ev: Select_Trigger_Event) {
	select_toggle_open()

	if select_ctx_ok() {
		user := select_ctx_top().trigger_user_click

		if user != nil {
			user(ev)
		}
	}
}

@(private)
select_value_label_child :: proc(fs: Select_Value_State) {
	ctx_child: proc(frame_state: Select_Value_State)

	if select_ctx_ok() {
		ctx_child = select_ctx_top().value_child
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
option_label_child :: proc(fs: Option_State) {
	if select_ctx_ok() {
		user := select_ctx_top().option_child

		if user != nil {
			user(fs)

			return
		}
	}

	Text({config = {text = fs.text}})
}

@(private)
option_on_click :: proc(ev: Option_Event) {
	select_set_value(ev.frame_state.value, ev.frame_state.text)

	if select_ctx_ok() {
		user := select_ctx_top().option_user_click

		if user != nil {
			user(ev)
		}
	}
}
