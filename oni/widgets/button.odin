package widgets

import o ".."
import set "../set"

/*
Button widget configuration extending Widget_Config.
*/
Button_Config :: o.Widget_Config

/*
Button widget per-frame frame_state merged with its fully resolved style config.
*/
Button_State :: o.Widget_Merged_State(o.Widget_Frame_State, o.Resolved_Widget_Config)

/*
Button widget event snapshot with frame_state and optional input metadata.
*/
Button_Event :: o.Widget_Event(Button_State)


/*
Button widget props: config overrides, child callback, and input event handlers.
*/
Button_Props :: struct {
	config:                       Button_Config,
	child:                        proc(frame_state: Button_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Button_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Button_State) -> o.Mount,
	on_focus:                     proc(event: Button_Event),
	on_blur:                      proc(event: Button_Event),
	on_mouse_enter:               proc(event: Button_Event),
	on_mouse_leave:               proc(event: Button_Event),
	on_mouse_pressed:             proc(event: Button_Event),
	on_mouse_down:                proc(event: Button_Event),
	on_mouse_released:            proc(event: Button_Event),
	on_mouse_move:                proc(event: Button_Event),
	on_click:                     proc(event: Button_Event),
	on_contextmenu:               proc(event: Button_Event),
	on_key_pressed:               proc(event: Button_Event),
	on_key_down:                  proc(event: Button_Event),
	on_key_released:              proc(event: Button_Event),
}

/*
Returns the default button theme config, muted when the widget is disabled.
*/
@(private)
button_theme_base :: proc(frame_state: ^Button_State) -> Button_Config {
	color := o.Color.FOREGROUND

	if frame_state.is_disabled {
		color = o.Color.MUTED
	}

	return Button_Config{kind = .BUTTON, line_height = set.F32(1)}
}

/*
Renders an interactive button with focus, pointer, and keyboard handling.

Runs layout on the layout pass and draws chrome plus children on the draw pass.
*/
Button :: proc(props: Button_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)

	frame_state := Button_State {
		is_disabled = o.cfg_style_bool(cfg.disabled),
		is_focused  = was_focused,
	}

	event := widget_refresh_merged(props, &frame_state, button_theme_base)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	child := props.child
	handlers := widget_lifecycle_handlers(props, Button_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = widget_refresh_merged(props, &frame_state, button_theme_base)
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
			o.Children(child, layout_id, config, frame_state)
		}

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) do return

	frame_state.is_focused = widget_is_focused(key)

	rect := o.ui_layout_rect(layout_id)

	got_focus, lost_focus := widget_handle_interaction(
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

	event, _ = widget_refresh_merged_if_interaction_changed(props, &frame_state, button_theme_base, style_fp)
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

	if !o.ui_layout_paint_skip(layout_id) {
		o.Draw_Rectangle(rect, background, radius, border, border_color)
	}

	o.Children(child, layout_id, config, frame_state)

	widget_dispatch_events(props, &frame_state, handlers, event, key, got_focus, lost_focus)
}
