package oni_widgets

import o ".."
import set "../set"

/*
Progress label configuration.

`text` is the default label content when `child` is nil.
*/
Progress_Label_Config :: struct {
	using _: o.Widget_Config,
	text:    string,
}

/*
Progress label per-frame state with resolved display text.
*/
Progress_Label_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	text:              string,
}

/*
Progress label event snapshot.
*/
Progress_Label_Event :: o.Widget_Event(Progress_Label_State)

/*
Progress label props: accessible label for the parent `Progress`.

When `child` is set it replaces the default `config.text` Text run.
*/
Progress_Label_Props :: struct {
	config:                       Progress_Label_Config,
	child:                        proc(frame_state: Progress_Label_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Progress_Label_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Progress_Label_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Progress_Label_Event),
	on_blur:                      proc(event: Progress_Label_Event),
	on_mouse_enter:               proc(event: Progress_Label_Event),
	on_mouse_leave:               proc(event: Progress_Label_Event),
	on_mouse_pressed:             proc(event: Progress_Label_Event),
	on_mouse_down:                proc(event: Progress_Label_Event),
	on_mouse_released:            proc(event: Progress_Label_Event),
	on_mouse_move:                proc(event: Progress_Label_Event),
	on_click:                     proc(event: Progress_Label_Event),
	on_contextmenu:               proc(event: Progress_Label_Event),
	on_key_pressed:               proc(event: Progress_Label_Event),
	on_key_down:                  proc(event: Progress_Label_Event),
	on_key_released:              proc(event: Progress_Label_Event),
}

@(private)
progress_label_theme_base :: proc(frame_state: ^Progress_Label_State) -> Progress_Label_Config {
	_ = frame_state

	return Progress_Label_Config {
		kind = .PROGRESS_LABEL,
		line_height = set.F32(1),
		tabbable = set.Tabbable(false),
		pointer_events = set.Pointer_Events(.NONE),
		color = set.Colors(o.Color.FOREGROUND),
	}
}

@(private)
progress_label_refresh_merged :: proc(
	props: Progress_Label_Props,
	frame_state: ^Progress_Label_State,
) -> Progress_Label_Event {
	event := widget_event(frame_state^)
	base := progress_label_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
progress_label_text_child :: proc(fs: Progress_Label_State) {
	Text({config = {text = fs.text, color = set.Colors(o.Color.FOREGROUND)}})
}

/*
Renders a label for the parent `Progress`.

Must be used inside `Progress`.
*/
Progress_Label :: proc(props: Progress_Label_Props) {
	if !progress_ctx_ok() {
		return
	}

	ctx := progress_ctx_top()
	cfg := props.config

	if cfg.id == "" {
		cfg.id = progress_part_id(ctx.parent_key, "label")
	}

	if ctx.disabled {
		cfg.disabled = set.Disabled(true)
	}

	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	disabled := o.cfg_style_bool(cfg.disabled) || ctx.disabled

	frame_state := Progress_Label_State {
		is_disabled = disabled,
		is_focused  = was_focused,
		text        = cfg.text,
	}

	props_resolved := props
	props_resolved.config = cfg

	event := progress_label_refresh_merged(props_resolved, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props_resolved, Progress_Label_State)
	should_auto_focus := widget_should_auto_focus(config, key)
	child := props.child

	if child == nil {
		child = progress_label_text_child
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
			event = progress_label_refresh_merged(props_resolved, &frame_state)
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
				child,
				layout_id,
				config,
				frame_state,
				key,
				props_resolved.config,
				props.on_scroll,
				frame_state.is_hovered,
			)
		}

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) do return

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)

	widget_handle_interaction(
		props_resolved,
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

	fp := widget_style_interaction_fp(&frame_state)

	if fp != style_fp {
		event = progress_label_refresh_merged(props_resolved, &frame_state)
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
		child,
		layout_id,
		config,
		frame_state,
		key,
		props_resolved.config,
		props.on_scroll,
		frame_state.is_hovered,
	)

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	widget_dispatch_events(props_resolved, &frame_state, handlers, event, key, was_focused)
}
