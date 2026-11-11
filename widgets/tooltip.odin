package oni_widgets

import o ".."
import set "../set"

/*
Tooltip root configuration: Widget_Config plus caller-owned `open` and hover delay.
*/
Tooltip_Config :: struct {
	using _:      o.Widget_Config,
	open:         bool,
	show_delay:   f32,
}

/*
Tooltip root per-frame state merged with resolved style and open flag.
*/
Tooltip_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	open:              bool,
	disabled:          bool,
	show_delay:        f32,
}

/*
Tooltip root event snapshot.
*/
Tooltip_Event :: o.Widget_Event(Tooltip_State)

/*
Tooltip root props: caller-owned `config.open`, compound Trigger / Content children.

Pass `config.open` every frame and update from `on_open_change`. The trigger opens
the tooltip on hover after `show_delay`; only one tooltip is active globally.
*/
Tooltip_Props :: struct {
	config:                       Tooltip_Config,
	on_open_change:               proc(open: bool),
	child:                        proc(frame_state: Tooltip_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Tooltip_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Tooltip_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Tooltip_Event),
	on_blur:                      proc(event: Tooltip_Event),
	on_mouse_enter:               proc(event: Tooltip_Event),
	on_mouse_leave:               proc(event: Tooltip_Event),
	on_mouse_pressed:             proc(event: Tooltip_Event),
	on_mouse_down:                proc(event: Tooltip_Event),
	on_mouse_released:            proc(event: Tooltip_Event),
	on_mouse_move:                proc(event: Tooltip_Event),
	on_click:                     proc(event: Tooltip_Event),
	on_contextmenu:               proc(event: Tooltip_Event),
	on_key_pressed:               proc(event: Tooltip_Event),
	on_key_down:                  proc(event: Tooltip_Event),
	on_key_released:              proc(event: Tooltip_Event),
}

@(private)
tooltip_root_theme_base :: proc(frame_state: ^Tooltip_State) -> Tooltip_Config {
	_ = frame_state

	return Tooltip_Config {
		kind = .TOOLTIP,
		direction = set.Direction(.VERTICAL),
		gap_y = set.Gap_Y(u16(0)),
		background = set.Background(o.Color.TRANSPARENT),
	}
}

@(private)
tooltip_root_refresh_merged :: proc(
	props: Tooltip_Props,
	frame_state: ^Tooltip_State,
) -> Tooltip_Event {
	event := widget_event(frame_state^)
	base := tooltip_root_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
tooltip_root_refresh_merged_if_interaction_changed :: proc(
	props: Tooltip_Props,
	frame_state: ^Tooltip_State,
	prev_fp: u8,
) -> (
	event: Tooltip_Event,
	fp: u8,
) {
	fp = widget_style_interaction_fp(frame_state)

	if fp == prev_fp {
		return widget_event(frame_state^), fp
	}

	return tooltip_root_refresh_merged(props, frame_state), fp
}

@(private)
tooltip_resolve_show_delay :: proc(cfg: Tooltip_Config) -> f32 {
	if cfg.show_delay > 0 {
		return cfg.show_delay
	}

	return TOOLTIP_DEFAULT_SHOW_DELAY_S
}

/*
Renders a composable tooltip root.

`Tooltip_Trigger` and `Tooltip_Content` must be descendants. Content paints in
`.POPOVER` space and anchors to the trigger while open. Hover opens after delay;
click does not toggle.
*/
Tooltip :: proc(props: Tooltip_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	open := cfg.open
	disabled := o.cfg_style_bool(cfg.disabled)
	show_delay := tooltip_resolve_show_delay(cfg)

	frame_state := Tooltip_State {
		is_disabled = disabled,
		is_focused  = was_focused,
		open        = open,
		disabled    = disabled,
		show_delay  = show_delay,
	}

	props_resolved := props
	props_resolved.config = cfg

	event := tooltip_root_refresh_merged(props_resolved, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props_resolved, Tooltip_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	tooltip_register_owner(
		key,
		{
			on_open_change = props.on_open_change,
			show_delay = show_delay,
			disabled = disabled,
		},
	)
	tooltip_note_app_open(key, open)

	tooltip_ctx_push(
		{
			tooltip_key = key,
			open = open,
			disabled = disabled,
			show_delay = show_delay,
			on_open_change = props.on_open_change,
		},
	)
	defer tooltip_ctx_pop()

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = tooltip_root_refresh_merged(props_resolved, &frame_state)
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
				props.child,
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

	tooltip_frame_tick()
	tooltip_ctx_top().pointer_owned = false
	tooltip_ctx_top().trigger_hovered = false

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

	event, _ = tooltip_root_refresh_merged_if_interaction_changed(
		props_resolved,
		&frame_state,
		style_fp,
	)
	config = frame_state.config
	frame_state.open = open

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
		props.child,
		layout_id,
		config,
		frame_state,
		key,
		props_resolved.config,
		props.on_scroll,
		frame_state.is_hovered,
	)

	Tooltip_Process_Hover()

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	widget_dispatch_events(props_resolved, &frame_state, handlers, event, key, was_focused)
}
