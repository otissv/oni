package oni_widgets

import o ".."
import set "../set"

/*
Collapsible root configuration: Widget_Config plus caller-owned `open`.

`disabled` is the usual Widget_Config style field (`set.Disabled` / `set.Bool`).
*/
Collapsible_Config :: struct {
	using _: o.Widget_Config,
	open:    bool,
}

/*
Collapsible root per-frame state merged with resolved style and open flag.
*/
Collapsible_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	open:              bool,
	disabled:          bool,
}

/*
Collapsible root event snapshot.
*/
Collapsible_Event :: o.Widget_Event(Collapsible_State)

/*
Collapsible root props: caller-owned `config.open`, compound Trigger / Content children.

Pass `config.open` every frame and update from `on_open_change`. Composition
matches shadcn Collapsible: root → Trigger + Content (in-flow expand/collapse).
*/
Collapsible_Props :: struct {
	config:                       Collapsible_Config,
	on_open_change:               proc(open: bool),
	child:                        proc(frame_state: Collapsible_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Collapsible_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Collapsible_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Collapsible_Event),
	on_blur:                      proc(event: Collapsible_Event),
	on_mouse_enter:               proc(event: Collapsible_Event),
	on_mouse_leave:               proc(event: Collapsible_Event),
	on_mouse_pressed:             proc(event: Collapsible_Event),
	on_mouse_down:                proc(event: Collapsible_Event),
	on_mouse_released:            proc(event: Collapsible_Event),
	on_mouse_move:                proc(event: Collapsible_Event),
	on_click:                     proc(event: Collapsible_Event),
	on_contextmenu:               proc(event: Collapsible_Event),
	on_key_pressed:               proc(event: Collapsible_Event),
	on_key_down:                  proc(event: Collapsible_Event),
	on_key_released:              proc(event: Collapsible_Event),
}

@(private)
collapsible_root_theme_base :: proc(frame_state: ^Collapsible_State) -> Collapsible_Config {
	_ = frame_state

	return Collapsible_Config {
		kind = .COLLAPSIBLE,
		direction = set.Direction(.VERTICAL),
		gap_y = set.Gap_Y(u16(0)),
		background = set.Background(o.Color.TRANSPARENT),
	}
}

@(private)
collapsible_root_refresh_merged :: proc(
	props: Collapsible_Props,
	frame_state: ^Collapsible_State,
) -> Collapsible_Event {
	event := widget_event(frame_state^)
	base := collapsible_root_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
collapsible_root_refresh_merged_if_interaction_changed :: proc(
	props: Collapsible_Props,
	frame_state: ^Collapsible_State,
	prev_fp: u8,
) -> (
	event: Collapsible_Event,
	fp: u8,
) {
	fp = widget_style_interaction_fp(frame_state)

	if fp == prev_fp {
		return widget_event(frame_state^), fp
	}

	return collapsible_root_refresh_merged(props, frame_state), fp
}

/*
Renders a composable collapsible root.

`Collapsible_Trigger` and `Collapsible_Content` must be descendants. Content
stays in the parent layout flow and expands or collapses with `config.open`.
*/
Collapsible :: proc(props: Collapsible_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	open := cfg.open
	disabled := o.cfg_style_bool(cfg.disabled)

	frame_state := Collapsible_State {
		is_disabled = disabled,
		is_focused  = was_focused,
		open        = open,
		disabled    = disabled,
	}

	props_resolved := props
	props_resolved.config = cfg

	event := collapsible_root_refresh_merged(props_resolved, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props_resolved, Collapsible_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	collapsible_ctx_push(
		{
			open = open,
			disabled = disabled,
			on_open_change = props.on_open_change,
		},
	)
	defer collapsible_ctx_pop()

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = collapsible_root_refresh_merged(props_resolved, &frame_state)
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

	event, _ = collapsible_root_refresh_merged_if_interaction_changed(
		props_resolved,
		&frame_state,
		style_fp,
	)
	config = frame_state.config
	frame_state.open = collapsible_ctx_top().open

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

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	widget_dispatch_events(props_resolved, &frame_state, handlers, event, key, was_focused)
}
