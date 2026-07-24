package oni_widgets

import o ".."


Text_Widget_Input :: struct {
	kind:            o.Widget_Kind,
	measure_text:    string,
	layout_runs:     []o.Layout_Text_Run,
	rich:            bool,
	tag_diagnostics: bool,
}

/*
Shared layout, interaction, and draw implementation for Text and RichText widgets.
*/
text_widget_core :: proc(
	props: $P,
	frame_state: ^$S,
	prepare_input: proc(props: P, frame_state: ^S) -> Text_Widget_Input,
	refresh_merged: proc(props: P, frame_state: ^S) -> o.Widget_Event(S),
	refresh_if_changed: proc(props: P, frame_state: ^S, prev_fp: u8) -> (
		o.Widget_Event(S),
		u8,
	),
	edit_opts: Text_Edit_Widget_Opts = {},
) -> o.Vec2 {
	config := props.config
	key := o.element_key(config.id)
	layout_label := config.id != "" ? config.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)

	event := refresh_merged(props, frame_state)
	style_fp := widget_style_interaction_fp(frame_state)
	style := frame_state.style
	handlers := widget_lifecycle_handlers(props, S)
	should_auto_focus := widget_should_auto_focus(style, key)

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			config.id != "",
			frame_state,
			style.visibility,
		)

		if ran_unmount {
			event = refresh_merged(props, frame_state)
			style = frame_state.style
			should_auto_focus = widget_should_auto_focus(style, key)
		}

		if skip_layout do return {}

		can_interact := widget_can_interact(handlers, frame_state)

		if can_interact && should_auto_focus {
			widget_apply_auto_focus(key, true)
			frame_state.is_focused = true
		}

		widget_register_tab_order(key, style.tabbable, can_interact)

		input := prepare_input(props, frame_state)
		node := o.layout_push_node(layout_id, style)

		if input.rich {
			o.layout_set_measure_rich_text(
				node,
				input.measure_text,
				input.layout_runs,
				style.max_w,
				input.tag_diagnostics,
			)
		} else {
			o.layout_set_measure_text(node, input.measure_text, style.max_w)
		}

		o.layout_pop_node()

		return {}
	}

	if !widget_prepare_draw(handlers, layout_id, frame_state) do return {}

	frame_state.is_focused = widget_is_focused(key)

	layout_rect := o.ui_layout_rect(layout_id)

	widget_handle_interaction(
		props,
		frame_state,
		handlers,
		key,
		was_focused,
		style.tabbable,
		layout_id,
		layout_rect,
		style,
	)

	event, _ = refresh_if_changed(props, frame_state, style_fp)
	style = frame_state.style

	if widget_can_interact(handlers, frame_state) {
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
	   widget_can_interact(handlers, frame_state) {
		props.on_focus(event)
	}

	widget_dispatch_events(props, frame_state, handlers, event, key, was_focused)

	scroll_entry := o.widget_scroll_ensure(key)

	rgbaColor, color_ok := o.style_color_rgba(style, frame_state, event)
	if !color_ok do return {}

	if o.ui_layout_paint_skip(layout_id) do return {}

	laid := o.layout_text_result(layout_id)
	if laid == nil do return {}

	plain := ""

	if geo := o.layout_text_edit_geometry(layout_id); geo != nil {
		plain = geo.plain
	}

	if edit_opts.selectable || edit_opts.editable {
		can_edit := widget_can_interact(handlers, frame_state)
		opts := edit_opts
		opts.draw_space = style.space
		text_edit_widget_handle_pointer(
			key,
			layout_id,
			layout_rect,
			scroll_entry,
			plain,
			can_edit,
			style,
			opts,
		)

		if opts.selectable && !opts.editable {
			text_edit_widget_handle_selectable(key, plain)
		}

		if opts.editable && frame_state.is_focused {
			updated, _ := text_edit_widget_handle_keys(
				key,
				layout_id,
				layout_rect,
				scroll_entry,
				plain,
				style,
				opts,
			)
			plain = updated
			updated_cmd, _ := text_edit_widget_consume_commands(
				key,
				layout_id,
				layout_rect,
				scroll_entry,
				plain,
				style,
				opts,
			)
			plain = updated_cmd
		}

		opts.has_caret_color = true
		opts.caret_color = rgbaColor
		opts.has_selection_color = true
		opts.selection_color = o.css_color_to_rgba(o.Color.SELECTION)

		text_edit_widget_draw_selection(opts, key, layout_id, layout_rect, plain)

		deco_color := rgbaColor
		#partial switch c in style.text_decoration_color {
		case o.Color:
			if c != .INHERIT {
				if resolved, ok := o.style_text_decoration_color_rgba(style, frame_state, event); ok {
					deco_color = resolved
				}
			}
		case:
			if resolved, ok := o.style_text_decoration_color_rgba(style, frame_state, event); ok {
				deco_color = resolved
			}
		}

		run_colors: []o.RGBA

		if laid.rich && len(laid.runs) > 0 {
			run_colors = make([]o.RGBA, len(laid.runs), context.temp_allocator)

			for run, i in laid.runs {
				run_colors[i], _ = o.text_run_resolve_color(run, rgbaColor, color_ok)
				opacity := o.text_run_resolve_opacity(run, style.opacity)
				run_colors[i].a = u8(clamp(f32(run_colors[i].a) * opacity, 0, 255))
			}
		}

		o.Draw_Push_Opacity(style.opacity)
		defer o.Draw_Pop_Opacity()

		size := o.font_draw_layout_text(laid, rgbaColor, deco_color, run_colors)
		text_edit_widget_draw_caret(opts, key, layout_id, layout_rect, plain, frame_state.is_focused)

		return size
	}

	deco_color := rgbaColor
	#partial switch c in style.text_decoration_color {
	case o.Color:
		if c != .INHERIT {
			if resolved, ok := o.style_text_decoration_color_rgba(style, frame_state, event); ok {
				deco_color = resolved
			}
		}
	case:
		if resolved, ok := o.style_text_decoration_color_rgba(style, frame_state, event); ok {
			deco_color = resolved
		}
	}

	run_colors: []o.RGBA

	if laid.rich && len(laid.runs) > 0 {
		run_colors = make([]o.RGBA, len(laid.runs), context.temp_allocator)

		for run, i in laid.runs {
			run_colors[i], _ = o.text_run_resolve_color(run, rgbaColor, color_ok)
			opacity := o.text_run_resolve_opacity(run, style.opacity)
			run_colors[i].a = u8(clamp(f32(run_colors[i].a) * opacity, 0, 255))
		}
	}

	o.Draw_Push_Opacity(style.opacity)
	defer o.Draw_Pop_Opacity()

	return o.font_draw_layout_text(laid, rgbaColor, deco_color, run_colors)
}
