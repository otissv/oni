package oni_widgets

import "core:strings"
import o ".."
import set "../set"

Rich_Text_Input_Config :: struct {
	using _:     o.Widget_Config,
	text:        string,
	placeholder: string,
	multiline:   bool,
	max_length:  int,
}

Rich_Text_Input_State :: o.Widget_Merged_State(o.Widget_Frame_State, o.Resolved_Widget_Config)

Rich_Text_Input_Event :: o.Widget_Event(Rich_Text_Input_State)

Rich_Text_Input_Props :: struct {
	config:                       Rich_Text_Input_Config,
	on_change:                    proc(event: Rich_Text_Input_Event, tagged: string),
	on_submit:                    proc(event: Rich_Text_Input_Event),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Rich_Text_Input_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Rich_Text_Input_State) -> o.Mount,
	on_focus:                     proc(event: Rich_Text_Input_Event),
	on_blur:                      proc(event: Rich_Text_Input_Event),
	on_mouse_enter:               proc(event: Rich_Text_Input_Event),
	on_mouse_leave:               proc(event: Rich_Text_Input_Event),
	on_mouse_pressed:             proc(event: Rich_Text_Input_Event),
	on_mouse_down:                proc(event: Rich_Text_Input_Event),
	on_mouse_released:            proc(event: Rich_Text_Input_Event),
	on_mouse_move:                proc(event: Rich_Text_Input_Event),
	on_click:                     proc(event: Rich_Text_Input_Event),
	on_contextmenu:               proc(event: Rich_Text_Input_Event),
	on_key_pressed:               proc(event: Rich_Text_Input_Event),
	on_key_down:                  proc(event: Rich_Text_Input_Event),
	on_key_released:               proc(event: Rich_Text_Input_Event),
}

@(private)
rich_text_input_theme_base :: proc(frame_state: ^Rich_Text_Input_State) -> Rich_Text_Input_Config {
	_ = frame_state

	return Rich_Text_Input_Config {
		kind = .RICH_TEXT_INPUT,
		line_height = set.F32(1.2),
		padding = set.Padding(o.Pd_struct{x = 8, y = 6}),
		border = set.Border(1),
		border_color = set.Border_color(o.Color.BORDER),
		tabbable = set.Tabbable(true),
		accepts_text_input = set.Accepts_Text_Input(),
	}
}

@(private)
rich_text_input_refresh_merged :: proc(
	props: Rich_Text_Input_Props,
	frame_state: ^Rich_Text_Input_State,
) -> Rich_Text_Input_Event {
	event := widget_event(frame_state^)
	base := rich_text_input_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
rich_text_input_report_tag_diagnostics :: proc(id_label: string, diagnostics: []o.Text_Tag_Diagnostic) {
	for diagnostic in diagnostics {
		o.error_reportf("RichTextInput %q: %s", id_label, diagnostic.message)
	}
}

@(private)
rich_text_input_prepare_layout :: proc(
	props: Rich_Text_Input_Props,
	caret: int,
) -> Text_Widget_Input {
	override := props.config
	allocator := o.layout_frame_allocator()
	parsed := o.text_tags_parse(override.text, allocator)
	plain := parsed.plain

	if len(plain) == 0 && len(override.placeholder) > 0 {
		plain = override.placeholder
	} else {
		plain = o.input_ime_preview(plain, caret, o.state.input.ime_text)
	}

	id_label := override.id != "" ? override.id : "RichTextInput"
	rich_text_input_report_tag_diagnostics(id_label, parsed.diagnostics)

	return {
		kind = .RICH_TEXT_INPUT,
		measure_text = plain,
		layout_runs = parsed.layout_runs,
		rich = len(parsed.layout_runs) > 0,
		tag_diagnostics = len(parsed.diagnostics) > 0,
	}
}

@(private)
rich_text_input_plain :: proc(tagged: string) -> string {
	parsed := o.text_tags_parse(tagged, context.temp_allocator)

	return parsed.plain
}

Rich_Text_Input :: proc(props: Rich_Text_Input_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)

	frame_state := Rich_Text_Input_State {
		is_disabled = o.cfg_style_bool(cfg.disabled),
		is_focused  = was_focused,
	}

	event := rich_text_input_refresh_merged(props, &frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props, Rich_Text_Input_State)
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
			event = rich_text_input_refresh_merged(props, &frame_state)
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

		input := rich_text_input_prepare_layout(props, caret)
		node := o.layout_push_node(layout_id, config)

		if input.rich {
			o.layout_set_measure_rich_text(
				node,
				input.measure_text,
				input.layout_runs,
				config.max_w,
				input.tag_diagnostics,
			)
		} else {
			o.layout_set_measure_text(node, input.measure_text, config.max_w)
		}

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
	plain := rich_text_input_plain(cfg.text)
	can_interact := widget_can_interact(handlers, &frame_state)
	text_edit_widget_handle_pointer(key, layout_id, rect, scroll, plain, can_interact)

	edit_opts := Text_Edit_Widget_Opts{selectable = true, editable = true}
	tagged := cfg.text

	if frame_state.is_focused {
		updated, changed := text_edit_widget_apply_document_keys(
			tagged,
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

		tagged = updated
		updated_cmd, cmd_changed := text_edit_widget_apply_document_plain(tagged, key, plain)

		if cmd_changed && props.on_change != nil {
			props.on_change(event, strings.clone(updated_cmd))
		}

		tagged = updated_cmd
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
