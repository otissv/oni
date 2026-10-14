package oni_widgets

import o ".."
import set "../set"

/*
Dialog root configuration.
*/
Dialog_Config :: o.Widget_Config

/*
Dialog root per-frame state merged with resolved style and open flag.
*/
Dialog_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	open:              bool,
	disabled:          bool,
}

/*
Dialog root event snapshot.
*/
Dialog_Event :: o.Widget_Event(Dialog_State)

/*
Dialog root props: caller-owned `open`, compound Trigger / Scrim / Content children.

Pass `open` every frame and update from `on_open_change`. Escape and outside
pointer press dismiss the modal while open.
*/
Dialog_Props :: struct {
	config:                       Dialog_Config,
	open:                         bool,
	disabled:                     bool,
	on_open_change:               proc(open: bool),
	child:                        proc(frame_state: Dialog_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Dialog_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Dialog_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Dialog_Event),
	on_blur:                      proc(event: Dialog_Event),
	on_mouse_enter:               proc(event: Dialog_Event),
	on_mouse_leave:               proc(event: Dialog_Event),
	on_mouse_pressed:             proc(event: Dialog_Event),
	on_mouse_down:                proc(event: Dialog_Event),
	on_mouse_released:            proc(event: Dialog_Event),
	on_mouse_move:                proc(event: Dialog_Event),
	on_click:                     proc(event: Dialog_Event),
	on_contextmenu:               proc(event: Dialog_Event),
	on_key_pressed:               proc(event: Dialog_Event),
	on_key_down:                  proc(event: Dialog_Event),
	on_key_released:              proc(event: Dialog_Event),
}

@(private)
dialog_root_theme_base :: proc(frame_state: ^Dialog_State) -> Dialog_Config {
	_ = frame_state

	return Dialog_Config {
		kind = .DIALOG,
		direction = set.Direction(.VERTICAL),
		gap_y = set.Gap_Y(u16(0)),
	}
}

@(private)
dialog_root_refresh_merged :: proc(
	props: Dialog_Props,
	frame_state: ^Dialog_State,
) -> Dialog_Event {
	event := widget_event(frame_state^)
	base := dialog_root_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
dialog_root_refresh_merged_if_interaction_changed :: proc(
	props: Dialog_Props,
	frame_state: ^Dialog_State,
	prev_fp: u8,
) -> (
	event: Dialog_Event,
	fp: u8,
) {
	fp = widget_style_interaction_fp(frame_state)

	if fp == prev_fp {
		return widget_event(frame_state^), fp
	}

	return dialog_root_refresh_merged(props, frame_state), fp
}

/*
Renders a composable modal dialog root.

`Dialog_Trigger`, `Dialog_Scrim`, `Dialog_Content`, `Dialog_Cancel`, and
`Dialog_Action` must be descendants. Scrim and content paint in `.OVERLAY`
space while open.
*/
Dialog :: proc(props: Dialog_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	open := props.open
	disabled := props.disabled || o.cfg_style_bool(cfg.disabled)

	if disabled {
		cfg.disabled = set.Disabled(true)
	}

	frame_state := Dialog_State {
		is_disabled = disabled,
		is_focused  = was_focused,
		open        = open,
		disabled    = disabled,
	}

	props_resolved := props
	props_resolved.config = cfg

	event := dialog_root_refresh_merged(props_resolved, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props_resolved, Dialog_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	dialog_ctx_push(
		{
			dialog_key = key,
			open = open,
			disabled = disabled,
			on_open_change = props.on_open_change,
		},
	)
	defer dialog_ctx_pop()

	if o.ui_pass() == .Layout {
		dialog_ctx_top().pointer_owned = false

		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = dialog_root_refresh_merged(props_resolved, &frame_state)
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

	event, _ = dialog_root_refresh_merged_if_interaction_changed(
		props_resolved,
		&frame_state,
		style_fp,
	)
	config = frame_state.config
	frame_state.open = dialog_ctx_top().open

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

	dialog_root_handle_dismiss(key)

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	widget_dispatch_events(props_resolved, &frame_state, handlers, event, key, was_focused)
}

@(private)
dialog_root_handle_dismiss :: proc(root_key: string) {
	_ = root_key

	if !dialog_ctx_ok() {
		return
	}

	ctx := dialog_ctx_top()

	if !ctx.open {
		return
	}

	esc := o.w_ctx.keys[int(o.Scancode.ESCAPE)]

	if esc.pressed && !o.shortcut_key_consumed(.ESCAPE) {
		dialog_set_open(false)
		o.state.shortcuts.consumed_keys[int(o.Scancode.ESCAPE)] = true
	}

	if o.w_ctx.left_mouse.pressed && !ctx.pointer_owned {
		dialog_set_open(false)
	}
}
