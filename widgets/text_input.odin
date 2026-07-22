package oni_widgets

import o ".."
import set "../set"
import "core:strings"

Text_Input_Config :: struct {
	using _:     o.Widget_Config,
	text:        string,
	placeholder: string,
	multiline:   bool,
	max_length:  int,
	password:    bool,
}

Text_Input_State :: o.Widget_Merged_State(o.Widget_Frame_State, o.Resolved_Widget_Config)

Text_Input_Event :: o.Widget_Event(Text_Input_State)

Text_Input_Props :: struct {
	config:                       Text_Input_Config,
	on_change:                    proc(event: Text_Input_Event, text: string),
	on_submit:                    proc(event: Text_Input_Event),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Text_Input_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Text_Input_State) -> o.Mount,
	on_focus:                     proc(event: Text_Input_Event),
	on_blur:                      proc(event: Text_Input_Event),
	on_mouse_enter:               proc(event: Text_Input_Event),
	on_mouse_leave:               proc(event: Text_Input_Event),
	on_mouse_pressed:             proc(event: Text_Input_Event),
	on_mouse_down:                proc(event: Text_Input_Event),
	on_mouse_released:            proc(event: Text_Input_Event),
	on_mouse_move:                proc(event: Text_Input_Event),
	on_click:                     proc(event: Text_Input_Event),
	on_contextmenu:               proc(event: Text_Input_Event),
	on_key_pressed:               proc(event: Text_Input_Event),
	on_key_down:                  proc(event: Text_Input_Event),
	on_key_released:              proc(event: Text_Input_Event),
}

@(private)
text_input_theme_base :: proc(frame_state: ^Text_Input_State) -> Text_Input_Config {
	_ = frame_state

	return Text_Input_Config {
		kind = .TEXT_INPUT,
		line_height = set.F32(1.2),
		padding = set.Padding(o.Pd_struct{x = 8, y = 6}),
		border = set.Border(1),
		border_color = set.Border_color(o.Color.BORDER),
		background = set.Background(o.Color.BACKGROUND),
		color = set.Colors(o.Color.FOREGROUND),
		tabbable = set.Tabbable(true),
		accepts_text_input = set.Accepts_Text_Input(),
	}
}

@(private)
text_input_refresh_merged :: proc(
	props: Text_Input_Props,
	frame_state: ^Text_Input_State,
) -> Text_Input_Event {
	event := widget_event(frame_state^)
	base := text_input_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
text_input_display_text :: proc(
	text: string,
	password: bool,
	placeholder: string,
	caret: int,
) -> string {
	display := text

	if password {
		b := strings.builder_make(context.temp_allocator)

		for _ in 0 ..< len(text) {
			strings.write_rune(&b, '•')
		}

		display = strings.to_string(b)
	}

	if len(display) == 0 && len(placeholder) > 0 {
		return placeholder
	}

	return o.input_ime_preview(display, caret, o.state.input.ime_text)
}

Text_Input :: proc(props: Text_Input_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)

	frame_state := Text_Input_State {
		is_disabled = o.cfg_style_bool(cfg.disabled),
		is_focused  = was_focused,
	}

	event := text_input_refresh_merged(props, &frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props, Text_Input_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	edit_state := o.widget_text_edit_ensure(key)
	caret := 0

	if edit_state != nil {
		caret = edit_state.caret
	}

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = text_input_refresh_merged(props, &frame_state)
			config = frame_state.config
			should_auto_focus = widget_should_auto_focus(config, key)
		}

		if skip_layout do return

		can_interact := widget_can_interact(handlers, &frame_state)

		if can_interact && should_auto_focus {
			widget_apply_auto_focus(key, true)
			frame_state.is_focused = true
		}

		widget_register_tab_order(key, config.tabbable, can_interact)

		display := text_input_display_text(cfg.text, cfg.password, cfg.placeholder, caret)
		node := o.layout_push_node(layout_id, config)
		o.layout_set_measure_text(node, display, config.max_w)
		o.layout_pop_node()

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) do return

	frame_state.is_focused = widget_is_focused(key)

	rect := o.ui_layout_rect(layout_id)

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

	scroll := o.widget_scroll_get(key)
	config.scroll_x = scroll.x
	config.scroll_y = scroll.y
	frame_state.config = config

	plain := cfg.text
	can_interact := widget_can_interact(handlers, &frame_state)
	text_edit_widget_handle_pointer(key, layout_id, rect, scroll, plain, can_interact)

	edit_opts := Text_Edit_Widget_Opts {
		selectable = true,
		editable   = true,
	}

	if frame_state.is_focused {
		updated, changed := text_edit_widget_handle_keys(
			key,
			layout_id,
			rect,
			scroll,
			plain,
			edit_opts,
		)

		if changed && props.on_change != nil {
			props.on_change(event, strings.clone(updated))
		}

		plain = updated
		updated_cmd, cmd_changed := text_edit_widget_consume_commands(key, plain)

		if cmd_changed && props.on_change != nil {
			props.on_change(event, strings.clone(updated_cmd))
		}

		plain = updated_cmd
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

	if !o.ui_layout_paint_skip(layout_id) {
		o.Draw_Rectangle(rect, background, radius, border, border_color)
	}

	laid := o.layout_text_result(layout_id)
	text_color, text_color_ok := o.style_color_rgba(config, &frame_state, event)

	if laid != nil && text_color_ok {
		o.font_draw_layout_text(laid, text_color, text_color, nil)
		edit_opts.has_caret_color = true
		edit_opts.caret_color = text_color
	}

	text_edit_widget_draw_overlay(edit_opts, key, layout_id, rect, scroll, frame_state.is_focused)

	if widget_can_interact(handlers, &frame_state) {
		if widget_got_tab_focus(key) && props.on_focus != nil {
			props.on_focus(event)
		}

		if widget_lost_tab_focus(key) && props.on_blur != nil {
			props.on_blur(event)
		}
	}

	widget_dispatch_events(props, &frame_state, handlers, event, key, was_focused)
}
