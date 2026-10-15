package oni_widgets

import o ".."
import set "../set"

/*
Context menu root configuration: Widget_Config plus caller-owned `open`.

`disabled` is the usual Widget_Config style field (`set.Disabled` / `set.Bool`).
*/
Context_Menu_Config :: struct {
	using _: o.Widget_Config,
	open:    bool,
}

/*
Context menu root per-frame state merged with resolved style and open flag.
*/
Context_Menu_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	open:              bool,
	disabled:          bool,
}

/*
Context menu root event snapshot.
*/
Context_Menu_Event :: o.Widget_Event(Context_Menu_State)

/*
Context menu root props: caller-owned `config.open`, compound Trigger / Content.

Pass `config.open` every frame and update from `on_open_change`. Right-click
(or contextmenu) on the trigger opens the content at the pointer; Escape and
outside pointer press dismiss while open.
*/
Context_Menu_Props :: struct {
	config:                       Context_Menu_Config,
	on_open_change:               proc(open: bool),
	child:                        proc(frame_state: Context_Menu_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Context_Menu_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Context_Menu_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Context_Menu_Event),
	on_blur:                      proc(event: Context_Menu_Event),
	on_mouse_enter:               proc(event: Context_Menu_Event),
	on_mouse_leave:               proc(event: Context_Menu_Event),
	on_mouse_pressed:             proc(event: Context_Menu_Event),
	on_mouse_down:                proc(event: Context_Menu_Event),
	on_mouse_released:            proc(event: Context_Menu_Event),
	on_mouse_move:                proc(event: Context_Menu_Event),
	on_click:                     proc(event: Context_Menu_Event),
	on_contextmenu:               proc(event: Context_Menu_Event),
	on_key_pressed:               proc(event: Context_Menu_Event),
	on_key_down:                  proc(event: Context_Menu_Event),
	on_key_released:              proc(event: Context_Menu_Event),
}

@(private)
context_menu_root_theme_base :: proc(frame_state: ^Context_Menu_State) -> Context_Menu_Config {
	_ = frame_state

	return Context_Menu_Config {
		kind = .CONTEXT_MENU,
		direction = set.Direction(.VERTICAL),
		gap_y = set.Gap_Y(u16(0)),
		background = set.Background(o.Color.TRANSPARENT),
	}
}

@(private)
context_menu_root_refresh_merged :: proc(
	props: Context_Menu_Props,
	frame_state: ^Context_Menu_State,
) -> Context_Menu_Event {
	event := widget_event(frame_state^)
	base := context_menu_root_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
context_menu_root_refresh_merged_if_interaction_changed :: proc(
	props: Context_Menu_Props,
	frame_state: ^Context_Menu_State,
	prev_fp: u8,
) -> (
	event: Context_Menu_Event,
	fp: u8,
) {
	fp = widget_style_interaction_fp(frame_state)

	if fp == prev_fp {
		return widget_event(frame_state^), fp
	}

	return context_menu_root_refresh_merged(props, frame_state), fp
}

/*
Renders a composable context menu root.

`Context_Menu_Trigger` and `Context_Menu_Content` must be descendants. Content
paints in `.POPOVER` space and anchors to the pointer (or trigger) while open.
*/
Context_Menu :: proc(props: Context_Menu_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	open := cfg.open
	disabled := o.cfg_style_bool(cfg.disabled)

	frame_state := Context_Menu_State {
		is_disabled = disabled,
		is_focused  = was_focused,
		open        = open,
		disabled    = disabled,
	}

	props_resolved := props
	props_resolved.config = cfg

	event := context_menu_root_refresh_merged(props_resolved, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props_resolved, Context_Menu_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	context_menu_ctx_push(
		{
			menu_key = key,
			open = open,
			disabled = disabled,
			on_open_change = props.on_open_change,
		},
	)
	defer context_menu_ctx_pop()

	if open {
		context_menu_restore_anchor_into_ctx()
	}

	if o.ui_pass() == .Layout {
		context_menu_ctx_top().pointer_owned = false

		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = context_menu_root_refresh_merged(props_resolved, &frame_state)
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

	event, _ = context_menu_root_refresh_merged_if_interaction_changed(
		props_resolved,
		&frame_state,
		style_fp,
	)
	config = frame_state.config
	frame_state.open = context_menu_ctx_top().open

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

	context_menu_handle_dismiss(key)

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	widget_dispatch_events(props_resolved, &frame_state, handlers, event, key, was_focused)
}
