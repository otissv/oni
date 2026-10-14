package oni_widgets

import o ".."
import set "../set"

/*
Dialog trigger configuration.
*/
Dialog_Trigger_Config :: o.Widget_Config

/*
Dialog trigger per-frame state.
*/
Dialog_Trigger_State :: o.Widget_Merged_State(o.Widget_Frame_State, o.Resolved_Widget_Config)

/*
Dialog trigger event snapshot.
*/
Dialog_Trigger_Event :: o.Widget_Event(Dialog_Trigger_State)

/*
Dialog trigger props: toggles the parent `Dialog` open state.
*/
Dialog_Trigger_Props :: struct {
	config:                       Dialog_Trigger_Config,
	child:                        proc(frame_state: Dialog_Trigger_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Dialog_Trigger_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Dialog_Trigger_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Dialog_Trigger_Event),
	on_blur:                      proc(event: Dialog_Trigger_Event),
	on_mouse_enter:               proc(event: Dialog_Trigger_Event),
	on_mouse_leave:               proc(event: Dialog_Trigger_Event),
	on_mouse_pressed:             proc(event: Dialog_Trigger_Event),
	on_mouse_down:                proc(event: Dialog_Trigger_Event),
	on_mouse_released:            proc(event: Dialog_Trigger_Event),
	on_mouse_move:                proc(event: Dialog_Trigger_Event),
	on_click:                     proc(event: Dialog_Trigger_Event),
	on_contextmenu:               proc(event: Dialog_Trigger_Event),
	on_key_pressed:               proc(event: Dialog_Trigger_Event),
	on_key_down:                  proc(event: Dialog_Trigger_Event),
	on_key_released:              proc(event: Dialog_Trigger_Event),
}

@(private)
dialog_trigger_theme_base :: proc(frame_state: ^Dialog_Trigger_State) -> Dialog_Trigger_Config {
	_ = frame_state

	return Dialog_Trigger_Config{kind = .DIALOG_TRIGGER, tabbable = set.Tabbable(true)}
}

@(private)
dialog_trigger_toggle_open :: proc() {
	if !dialog_ctx_ok() {
		return
	}

	dialog_set_open(!dialog_ctx_top().open)
}

@(private)
dialog_trigger_set_trigger :: proc(key: string, layout_id: o.UI_Id, rect: o.Rect) {
	if !dialog_ctx_ok() {
		return
	}

	ctx := dialog_ctx_top()
	ctx.trigger_key = key
	ctx.trigger_layout_id = layout_id
	ctx.trigger_rect = rect
	ctx.has_trigger = true
}

@(private)
dialog_trigger_on_click :: proc(ev: Dialog_Trigger_Event) {
	dialog_trigger_toggle_open()

	if dialog_ctx_ok() {
		user := dialog_ctx_top().trigger_user_click

		if user != nil {
			user(ev)
		}
	}
}

/*
Renders the control that toggles the parent `Dialog`.

Must be used inside `Dialog`. Click and keyboard activation toggle open state.
*/
Dialog_Trigger :: proc(props: Dialog_Trigger_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	disabled := o.cfg_style_bool(cfg.disabled)

	if dialog_ctx_ok() && dialog_ctx_top().disabled {
		disabled = true
	}

	frame_state := Dialog_Trigger_State {
		is_disabled = disabled,
		is_focused  = was_focused,
	}

	event := widget_refresh_merged(props, &frame_state, dialog_trigger_theme_base)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	child := props.child
	handlers := widget_lifecycle_handlers(props, Dialog_Trigger_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	props_with_toggle := props
	props_with_toggle.on_click = dialog_trigger_on_click

	if dialog_ctx_ok() {
		dialog_ctx_top().trigger_user_click = props.on_click
	}

	if o.ui_pass() == .Layout {
		dialog_trigger_set_trigger(key, layout_id, {})

		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = widget_refresh_merged(props, &frame_state, dialog_trigger_theme_base)
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
	dialog_trigger_set_trigger(key, layout_id, rect)

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
		dialog_note_pointer()
	}

	widget_handle_scroll_wheel(layout_id, config, frame_state.is_hovered, key, props.on_scroll)
	scroll := o.widget_scroll_get(key)
	config.scroll_x = scroll.x
	config.scroll_y = scroll.y
	frame_state.config = config

	event, _ = widget_refresh_merged_if_interaction_changed(
		props,
		&frame_state,
		dialog_trigger_theme_base,
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
