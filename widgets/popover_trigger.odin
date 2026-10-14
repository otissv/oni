package oni_widgets

import o ".."
import set "../set"

/*
Popover trigger configuration.
*/
Popover_Trigger_Config :: o.Widget_Config

/*
Popover trigger per-frame state.
*/
Popover_Trigger_State :: o.Widget_Merged_State(o.Widget_Frame_State, o.Resolved_Widget_Config)

/*
Popover trigger event snapshot.
*/
Popover_Trigger_Event :: o.Widget_Event(Popover_Trigger_State)

/*
Popover trigger props: toggles the parent `Popover` open state.
*/
Popover_Trigger_Props :: struct {
	config:                       Popover_Trigger_Config,
	child:                        proc(frame_state: Popover_Trigger_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Popover_Trigger_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Popover_Trigger_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Popover_Trigger_Event),
	on_blur:                      proc(event: Popover_Trigger_Event),
	on_mouse_enter:               proc(event: Popover_Trigger_Event),
	on_mouse_leave:               proc(event: Popover_Trigger_Event),
	on_mouse_pressed:             proc(event: Popover_Trigger_Event),
	on_mouse_down:                proc(event: Popover_Trigger_Event),
	on_mouse_released:            proc(event: Popover_Trigger_Event),
	on_mouse_move:                proc(event: Popover_Trigger_Event),
	on_click:                     proc(event: Popover_Trigger_Event),
	on_contextmenu:               proc(event: Popover_Trigger_Event),
	on_key_pressed:               proc(event: Popover_Trigger_Event),
	on_key_down:                  proc(event: Popover_Trigger_Event),
	on_key_released:              proc(event: Popover_Trigger_Event),
}

@(private)
popover_trigger_theme_base :: proc(frame_state: ^Popover_Trigger_State) -> Popover_Trigger_Config {
	_ = frame_state

	return Popover_Trigger_Config{kind = .POPOVER_TRIGGER, tabbable = set.Tabbable(true)}
}

@(private)
popover_trigger_on_click :: proc(ev: Popover_Trigger_Event) {
	popover_toggle_open()

	if popover_ctx_ok() {
		user := popover_ctx_top().trigger_user_click

		if user != nil {
			user(ev)
		}
	}
}

/*
Renders the control that toggles the parent `Popover`.

Must be used inside `Popover`. Click and keyboard activation toggle open state.
*/
Popover_Trigger :: proc(props: Popover_Trigger_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	disabled := o.cfg_style_bool(cfg.disabled)

	if popover_ctx_ok() && popover_ctx_top().disabled {
		disabled = true
	}

	frame_state := Popover_Trigger_State {
		is_disabled = disabled,
		is_focused  = was_focused,
	}

	event := widget_refresh_merged(props, &frame_state, popover_trigger_theme_base)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	child := props.child
	handlers := widget_lifecycle_handlers(props, Popover_Trigger_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	props_with_toggle := props
	props_with_toggle.on_click = popover_trigger_on_click

	if popover_ctx_ok() {
		popover_ctx_top().trigger_user_click = props.on_click
	}

	if o.ui_pass() == .Layout {
		popover_set_trigger(key, layout_id, {})

		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = widget_refresh_merged(props, &frame_state, popover_trigger_theme_base)
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
				props.config,
				props.on_scroll,
				frame_state.is_hovered,
			)
		}

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) do return

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)
	popover_set_trigger(key, layout_id, rect)

	widget_handle_interaction(
		props_with_toggle,
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
		popover_note_pointer()
	}

	widget_handle_scroll_wheel(layout_id, config, frame_state.is_hovered, key, props.on_scroll)
	scroll := o.widget_scroll_get(key)
	config.scroll_x = scroll.x
	config.scroll_y = scroll.y
	frame_state.config = config

	event, _ = widget_refresh_merged_if_interaction_changed(
		props,
		&frame_state,
		popover_trigger_theme_base,
		style_fp,
	)
	config = frame_state.config

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
		props.config,
		props.on_scroll,
		frame_state.is_hovered,
	)

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	widget_dispatch_events(props_with_toggle, &frame_state, handlers, event, key, was_focused)
}
