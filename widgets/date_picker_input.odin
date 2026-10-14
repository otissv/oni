package oni_widgets

import o ".."
import set "../set"
import "core:fmt"
import "core:strings"

/*
Date picker input configuration (editable ISO field + calendar trigger).
*/
Date_Picker_Input_Config :: o.Widget_Config

/*
Date picker input per-frame state with draft text.
*/
Date_Picker_Input_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	text:              string,
	placeholder:       string,
	has_value:         bool,
	field_id:          string,
}

/*
Date picker input event snapshot.
*/
Date_Picker_Input_Event :: o.Widget_Event(Date_Picker_Input_State)

/*
Date picker input props: text field for ISO dates that also opens the calendar.

Must be used inside `Date_Picker`. Acts as the popover anchor (like Trigger).
Typing a valid `YYYY-MM-DD` updates the selection via `on_select`. Focusing or
clicking opens the calendar popover.
*/
Date_Picker_Input_Props :: struct {
	config:                       Date_Picker_Input_Config,
	placeholder:                  string,
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Date_Picker_Input_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Date_Picker_Input_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_change:                    proc(event: Date_Picker_Input_Event, text: string),
	on_submit:                    proc(event: Date_Picker_Input_Event),
	on_focus:                     proc(event: Date_Picker_Input_Event),
	on_blur:                      proc(event: Date_Picker_Input_Event),
	on_mouse_enter:               proc(event: Date_Picker_Input_Event),
	on_mouse_leave:               proc(event: Date_Picker_Input_Event),
	on_mouse_pressed:             proc(event: Date_Picker_Input_Event),
	on_mouse_down:                proc(event: Date_Picker_Input_Event),
	on_mouse_released:            proc(event: Date_Picker_Input_Event),
	on_mouse_move:                proc(event: Date_Picker_Input_Event),
	on_click:                     proc(event: Date_Picker_Input_Event),
	on_contextmenu:               proc(event: Date_Picker_Input_Event),
	on_key_pressed:               proc(event: Date_Picker_Input_Event),
	on_key_down:                  proc(event: Date_Picker_Input_Event),
	on_key_released:              proc(event: Date_Picker_Input_Event),
}

@(private)
date_picker_input_theme_base :: proc(
	frame_state: ^Date_Picker_Input_State,
) -> Date_Picker_Input_Config {
	_ = frame_state

	return Date_Picker_Input_Config {
		kind = .DATE_PICKER_INPUT,
		direction = set.Direction(.HORIZONTAL),
		justify = set.Justify(o.Justify_Pos{x = .START, y = .CENTER}),
		min_w = set.F32(f32(200)),
		gap_x = set.Gap_X(u16(0)),
	}
}

@(private)
date_picker_input_refresh_merged :: proc(
	props: Date_Picker_Input_Props,
	frame_state: ^Date_Picker_Input_State,
) -> Date_Picker_Input_Event {
	event := widget_event(frame_state^)
	base := date_picker_input_theme_base(frame_state)
	override := props.config
	frame_state.config = o.resolve_widget_config(base, override, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
date_picker_input_resolve_text :: proc(
	props: Date_Picker_Input_Props,
	picker_key: string,
) -> (
	text: string,
	has_value: bool,
) {
	if !date_picker_ctx_ok() {
		return "", false
	}

	ctx := date_picker_ctx_top()
	sel := date_picker_selection_from_ctx(ctx)
	has_value = date_picker_selection_has_value(sel)
	rt := date_picker_runtime_ensure(picker_key)

	if rt != nil && rt.input_editing && rt.input_text != "" {
		return rt.input_text, has_value
	}

	if rt != nil && rt.input_editing {
		return rt.input_text, has_value
	}

	if !has_value {
		if rt != nil {
			date_picker_runtime_set_string(&rt.input_text, "")
		}

		return "", false
	}

	formatted: string

	switch date_picker_effective_mode(ctx.mode) {
	case .SINGLE:
		formatted = Calendar_Format_ISO(sel.single, context.temp_allocator)
	case .RANGE, .MULTIPLE, .NONE:
		formatted = Date_Picker_Format_Selection(sel, context.temp_allocator)
	}

	if rt != nil {
		date_picker_runtime_set_string(&rt.input_text, formatted)
	}

	return formatted, true
}

@(private)
date_picker_input_field_id :: proc(config_id, picker_key: string) -> string {
	if config_id != "" {
		return fmt.tprintf("%s/field", config_id)
	}

	if picker_key != "" {
		return fmt.tprintf("%s/__date_picker_input_field", picker_key)
	}

	return ""
}

@(private)
date_picker_input_commit_text :: proc(text: string) -> bool {
	if !date_picker_ctx_ok() {
		return false
	}

	ctx := date_picker_ctx_top()
	mode := date_picker_effective_mode(ctx.mode)

	if mode != .SINGLE {
		return false
	}

	trimmed := strings.trim_space(text)

	if trimmed == "" {
		if ctx.required {
			return false
		}

		date_picker_apply_selection({mode = .SINGLE, has_single = false})

		return true
	}

	date, ok := Calendar_Parse_ISO(trimmed)

	if !ok {
		return false
	}

	date_picker_apply_selection({mode = .SINGLE, single = date, has_single = true})

	return true
}

@(private)
date_picker_input_on_text_change :: proc(event: Text_Input_Event, text: string) {
	_ = event

	if !date_picker_ctx_ok() {
		return
	}

	ctx := date_picker_ctx_top()
	rt := date_picker_runtime_ensure(ctx.picker_key)

	if rt != nil {
		rt.input_editing = true
		date_picker_runtime_set_string(&rt.input_text, text)
	}

	if date_picker_effective_mode(ctx.mode) == .SINGLE {
		trimmed := strings.trim_space(text)

		if date, ok := Calendar_Parse_ISO(trimmed); ok {
			date_picker_apply_selection(
				{mode = .SINGLE, single = date, has_single = true},
			)

			if rt != nil {
				rt.input_editing = true
				date_picker_runtime_set_string(&rt.input_text, trimmed)
			}
		}
	}

	if ctx.input_user_change != nil {
		fs := Date_Picker_Input_State {
			text = text,
		}
		ctx.input_user_change(widget_event(fs), text)
	}
}

@(private)
date_picker_input_on_text_submit :: proc(event: Text_Input_Event) {
	_ = event

	if !date_picker_ctx_ok() {
		return
	}

	ctx := date_picker_ctx_top()
	rt := date_picker_runtime_ensure(ctx.picker_key)
	text := rt != nil ? rt.input_text : ""
	_ = date_picker_input_commit_text(text)

	if rt != nil {
		rt.input_editing = false
	}

	if ctx.input_user_submit != nil {
		fs := Date_Picker_Input_State {
			text = text,
		}
		ctx.input_user_submit(widget_event(fs))
	}
}

@(private)
date_picker_input_on_text_focus :: proc(event: Text_Input_Event) {
	_ = event

	if !date_picker_ctx_ok() {
		return
	}

	ctx := date_picker_ctx_top()
	rt := date_picker_runtime_ensure(ctx.picker_key)

	if rt != nil {
		rt.input_editing = true
	}

	date_picker_set_open(true)
}

@(private)
date_picker_input_on_text_blur :: proc(event: Text_Input_Event) {
	_ = event

	if !date_picker_ctx_ok() {
		return
	}

	ctx := date_picker_ctx_top()
	rt := date_picker_runtime_ensure(ctx.picker_key)
	text := rt != nil ? rt.input_text : ""

	if !date_picker_input_commit_text(text) && rt != nil {
		sel := date_picker_selection_from_ctx(ctx)

		if date_picker_selection_has_value(sel) &&
		   date_picker_effective_mode(ctx.mode) == .SINGLE {
			date_picker_runtime_set_string(
				&rt.input_text,
				Calendar_Format_ISO(sel.single, context.temp_allocator),
			)
		}
	}

	if rt != nil {
		rt.input_editing = false
	}
}

@(private)
date_picker_input_on_text_click :: proc(event: Text_Input_Event) {
	_ = event
	date_picker_note_pointer()
	date_picker_set_open(true)
}

@(private)
date_picker_input_on_text_mouse_enter :: proc(_: Text_Input_Event) {
	date_picker_note_pointer()
}

@(private)
date_picker_input_field_child :: proc(fs: Date_Picker_Input_State) {
	field_cfg := Text_Input_Config {
		id          = fs.field_id,
		text        = fs.text,
		placeholder = fs.placeholder,
		flex        = set.Flex(1),
		width       = set.Width(f32(0)),
	}

	if fs.is_disabled {
		field_cfg.disabled = set.Disabled(true)
	}

	Text_Input(
		{
			config = field_cfg,
			on_change = date_picker_input_on_text_change,
			on_submit = date_picker_input_on_text_submit,
			on_focus = date_picker_input_on_text_focus,
			on_blur = date_picker_input_on_text_blur,
			on_click = date_picker_input_on_text_click,
			on_mouse_enter = date_picker_input_on_text_mouse_enter,
		},
	)
}

/*
Renders an editable ISO date field that opens the parent Date_Picker calendar.

Must be used inside `Date_Picker`. Prefer this instead of Trigger when the control
should accept typed `YYYY-MM-DD` values.
*/
Date_Picker_Input :: proc(props: Date_Picker_Input_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	disabled := o.cfg_style_bool(cfg.disabled)
	picker_key := ""

	if date_picker_ctx_ok() {
		ctx := date_picker_ctx_top()
		picker_key = ctx.picker_key

		if ctx.disabled {
			disabled = true
		}

		ctx.input_user_change = props.on_change
		ctx.input_user_submit = props.on_submit
	}

	text, has_value := date_picker_input_resolve_text(props, picker_key)
	placeholder := props.placeholder

	if placeholder == "" {
		placeholder = "YYYY-MM-DD"
	}

	field_id := date_picker_input_field_id(cfg.id, picker_key)

	frame_state := Date_Picker_Input_State {
		is_disabled = disabled,
		is_focused  = was_focused,
		text        = text,
		placeholder = placeholder,
		has_value   = has_value,
		field_id    = field_id,
	}

	event := date_picker_input_refresh_merged(props, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props, Date_Picker_Input_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	if o.ui_pass() == .Layout {
		if popover_ctx_ok() {
			popover_set_trigger(key, layout_id, {})
		}

		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = date_picker_input_refresh_merged(props, &frame_state)
			config = frame_state.config
			should_auto_focus = widget_should_auto_focus(config, key)
		}

		if !skip_layout {
			can_interact := widget_can_interact(handlers, &frame_state)

			if can_interact && should_auto_focus {
				widget_apply_auto_focus(key, true)
				frame_state.is_focused = true
			}

			widget_register_tab_order(key, config.tabbable, can_interact)
			widget_children(
				date_picker_input_field_child,
				layout_id,
				config,
				frame_state,
				key,
				props.config,
				props.on_scroll,
				frame_state.is_hovered,
			)
		}

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) {
		return
	}

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)

	if popover_ctx_ok() {
		popover_set_trigger(key, layout_id, rect)
	}

	widget_handle_interaction(
		props,
		&frame_state,
		handlers,
		key,
		was_focused,
		config.tabbable,
		layout_id,
		rect,
		config,
	)

	if frame_state.is_hovered {
		date_picker_note_pointer()
	}

	widget_handle_scroll_wheel(layout_id, config, frame_state.is_hovered, key, props.on_scroll)
	scroll := o.widget_scroll_get(key)
	config.scroll_x = scroll.x
	config.scroll_y = scroll.y
	frame_state.config = config

	fp := widget_style_interaction_fp(&frame_state)

	if fp != style_fp {
		event = date_picker_input_refresh_merged(props, &frame_state)
		config = frame_state.config
	}

	if widget_can_interact(handlers, &frame_state) {
		if widget_got_tab_focus(key) && props.on_focus != nil {
			props.on_focus(event)
		}

		if widget_lost_tab_focus(key) && props.on_blur != nil {
			props.on_blur(event)
		}
	}

	if should_auto_focus &&
	   !was_focused &&
	   props.on_focus != nil &&
	   widget_can_interact(handlers, &frame_state) {
		props.on_focus(event)
	}

	background: o.RGBA

	if resolved_background, background_ok := o.style_background_rgba(config, &frame_state, event);
	   background_ok {
		background = resolved_background
	}

	border: o.Bd_px

	if resolved_border, border_ok := o.resolve_border(config.border, &frame_state, event);
	   border_ok {
		border = resolved_border
	}

	border_color: o.RGBA

	if resolved_border_color, border_color_ok := o.style_border_color_rgba(
		config,
		&frame_state,
		event,
	); border_color_ok {
		border_color = resolved_border_color
	}

	radius: o.Radius_px

	if resolved_radius, ok := o.resolve_radius(config.radius, &frame_state, event); ok {
		radius = resolved_radius
	}

	o.Draw_Push_Opacity(config.opacity)
	defer o.Draw_Pop_Opacity()

	widget_draw_box_background(layout_id, rect, background, radius)

	widget_children(
		date_picker_input_field_child,
		layout_id,
		config,
		frame_state,
		key,
		props.config,
		props.on_scroll,
		frame_state.is_hovered,
	)

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	widget_dispatch_events(props, &frame_state, handlers, event, key, was_focused)
}
