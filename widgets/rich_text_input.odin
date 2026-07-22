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
rich_text_input_theme_base :: proc(frame_state: ^Rich_Text_Input_State) -> o.Widget_Config {
	_ = frame_state

	return o.Widget_Config {
		kind = .RICH_TEXT_INPUT,
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

@(private)
rich_text_input_sync_edit_state :: proc(key: string, tagged: string) {
	edit := o.widget_text_edit_get(key)
	if edit == nil do return

	plain := rich_text_input_plain(tagged)
	edit.caret = o.text_edit_clamp_offset(plain, edit.caret)
	edit.selection = o.text_edit_clamp_selection(plain, edit.selection)
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

	event := widget_refresh_merged(props, &frame_state, rich_text_input_theme_base)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props, Rich_Text_Input_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	edit_state := o.widget_text_edit_ensure(key)
	caret := 0

	if edit_state != nil {
		caret = edit_state.caret
	}

	rich_text_input_sync_edit_state(key, cfg.text)

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = widget_refresh_merged(props, &frame_state, rich_text_input_theme_base)
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

		layout_config := config

		if cfg.multiline {
			layout_config.style.wrap = o.Text_Wrap_Kind.BALANCE
		} else {
			layout_config.style.wrap = o.Text_Wrap_Kind.NONE
		}

		o.widget_scroll_apply(key, props.config, &layout_config)
		text_edit_widget_apply_layout_scroll_defaults(props.config, cfg.multiline, &layout_config)

		input := rich_text_input_prepare_layout(props, caret)
		node := o.layout_push_node(layout_id, layout_config)

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

		o.layout_set_edit_plain(node, rich_text_input_plain(cfg.text))
		o.layout_pop_node()

		scroll_frame := Widget_Scrollport_Frame {
			layout_id  = layout_id,
			element_id = key,
			parent_id  = layout_config.id != "" ? layout_config.id : key,
			config     = layout_config,
		}

		if widget_scrollport_frame_begin(scroll_frame) {
			widget_scrollport_frame_end(true, true)
		}

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

	scroll_entry := o.widget_scroll_ensure(key)
	scroll_before := scroll_entry^
	widget_handle_scroll_wheel(layout_id, config, frame_state.is_hovered, key)
	text_edit_widget_after_wheel_scroll(key, layout_id, scroll_entry, scroll_before)

	config.scroll_x = scroll_entry.x
	config.scroll_y = scroll_entry.y
	frame_state.config = config

	event, _ = widget_refresh_merged_if_interaction_changed(
		props,
		&frame_state,
		rich_text_input_theme_base,
		style_fp,
	)
	config = frame_state.config

	plain := rich_text_input_plain(cfg.text)
	can_interact := widget_can_interact(handlers, &frame_state)
	edit_opts := Text_Edit_Widget_Opts {
		selectable = true,
		editable   = true,
		multiline  = cfg.multiline,
		max_length = cfg.max_length,
		draw_space = config.space,
	}
	text_edit_widget_handle_pointer(key, layout_id, rect, scroll_entry, plain, can_interact, config, edit_opts)
	tagged := cfg.text

	if frame_state.is_focused {
		updated, changed := text_edit_widget_apply_document_keys(
			tagged,
			key,
			layout_id,
			rect,
			scroll_entry,
			plain,
			config,
			edit_opts,
		)

		if changed && props.on_change != nil {
			props.on_change(event, strings.clone(updated))
		}

		tagged = updated
		updated_cmd, cmd_changed := text_edit_widget_apply_document_plain(
			tagged,
			key,
			layout_id,
			rect,
			scroll_entry,
			plain,
			config,
			edit_opts,
		)

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

	scroll_frame := Widget_Scrollport_Frame {
		layout_id  = layout_id,
		element_id = key,
		parent_id  = config.id != "" ? config.id : key,
		config     = config,
		hovered    = frame_state.is_hovered,
	}
	scrollport_active := widget_scrollport_frame_begin(scroll_frame)
	clipped := false

	if scrollport_active && o.style_is_scrollport(config.overflow_x, config.overflow_y) {
		clipped = o.Draw_Push_Layout_Clip(layout_id)
	}

	laid := o.layout_text_result(layout_id)
	text_color, text_color_ok := o.style_color_rgba(config, &frame_state, event)

	if laid != nil && text_color_ok {
		o.font_draw_layout_text(laid, text_color, text_color, nil)
		edit_opts.has_caret_color = true
		edit_opts.caret_color = text_color
	}

	text_edit_widget_draw_overlay(edit_opts, key, layout_id, rect, scroll_entry^, frame_state.is_focused)

	if scrollport_active {
		widget_scrollport_frame_end(true, true)
	}

	if clipped {
		o.Draw_Pop_Clip()
	}

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
