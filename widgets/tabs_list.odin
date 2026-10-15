package oni_widgets

import o ".."
import set "../set"

/*
Tabs list configuration.
*/
Tabs_List_Config :: struct {
	using _:           o.Widget_Config,
	activate_on_focus: bool,
	variant:           Tabs_List_Variant,
}

/*
Tabs list per-frame state.
*/
Tabs_List_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	orientation:       Tabs_Orientation,
	variant:           Tabs_List_Variant,
	activate_on_focus: bool,
}

/*
Tabs list event snapshot.
*/
Tabs_List_Event :: o.Widget_Event(Tabs_List_State)

/*
Tabs list props.

Groups `Tabs_Trigger` children. `config.activate_on_focus` matches Base UI:
when true, arrow-key focus also activates the tab; when false (default),
Space/Enter activate. `config.variant` controls list and selected-trigger
chrome.
*/
Tabs_List_Props :: struct {
	config:                       Tabs_List_Config,
	child:                        proc(frame_state: Tabs_List_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Tabs_List_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Tabs_List_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Tabs_List_Event),
	on_blur:                      proc(event: Tabs_List_Event),
	on_mouse_enter:               proc(event: Tabs_List_Event),
	on_mouse_leave:               proc(event: Tabs_List_Event),
	on_mouse_pressed:             proc(event: Tabs_List_Event),
	on_mouse_down:                proc(event: Tabs_List_Event),
	on_mouse_released:            proc(event: Tabs_List_Event),
	on_mouse_move:                proc(event: Tabs_List_Event),
	on_click:                     proc(event: Tabs_List_Event),
	on_contextmenu:               proc(event: Tabs_List_Event),
	on_key_pressed:               proc(event: Tabs_List_Event),
	on_key_down:                  proc(event: Tabs_List_Event),
	on_key_released:              proc(event: Tabs_List_Event),
}

@(private)
tabs_list_theme_base :: proc(frame_state: ^Tabs_List_State) -> Tabs_List_Config {
	direction := o.Direction_Layout.HORIZONTAL
	gap_x := u16(0)
	gap_y := u16(0)

	if frame_state.orientation == .VERTICAL {
		direction = .VERTICAL
		gap_x = 0
		gap_y = u16(0)
	}

	background := o.Color.MUTED
	border := f32(0)
	border_color := o.Color.TRANSPARENT
	padding := o.Pd_pos {
		x = 4,
		y = 4,
	}

	if frame_state.variant == .LINE {
		background = .TRANSPARENT
		padding = {
			x = 0,
			y = 0,
		}

		if frame_state.orientation == .HORIZONTAL {
			border = 0
		}
	}

	return Tabs_List_Config {
		kind = .TABS_LIST,
		tabbable = set.Tabbable(false),
		width = set.Width(.GROW),
		direction = set.Direction(direction),
		justify = set.Justify(o.Justify_Pos{x = .START, y = .CENTER}),
		gap_x = set.Gap_X(gap_x),
		gap_y = set.Gap_Y(gap_y),
		padding = set.Padding(padding),
		background = set.Background(background),
		border = set.Border(border),
		border_color = set.Border_color(border_color),
	}
}

@(private)
tabs_list_refresh_merged :: proc(
	props: Tabs_List_Props,
	frame_state: ^Tabs_List_State,
) -> Tabs_List_Event {
	event := widget_event(frame_state^)
	base := tabs_list_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

/*
Renders the tab trigger strip inside a `Tabs` root.

Outside a root the list still lays out as a container but does not change
activation policy on any enclosing tabs context.
*/
Tabs_List :: proc(props: Tabs_List_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)
	was_focused := widget_is_focused(key)
	in_tabs := tabs_ctx_ok()
	orientation := Tabs_Orientation.HORIZONTAL
	variant := tabs_variant_normalize(cfg.variant)
	prev_in_list := false

	if in_tabs {
		ctx := tabs_ctx_top()
		orientation = ctx.orientation
		prev_in_list = ctx.in_list
		ctx.activate_on_focus = cfg.activate_on_focus
		ctx.variant = variant
		ctx.in_list = true
	}

	defer {
		if in_tabs && tabs_ctx_ok() {
			tabs_ctx_top().in_list = prev_in_list
		}
	}

	frame_state := Tabs_List_State {
		is_disabled       = o.cfg_style_bool(cfg.disabled) || (in_tabs && tabs_ctx_top().disabled),
		is_focused        = was_focused,
		orientation       = orientation,
		variant           = variant,
		activate_on_focus = cfg.activate_on_focus,
	}

	if frame_state.is_disabled {
		cfg.disabled = set.Disabled(true)
	}

	resolved_props := props
	resolved_props.config = cfg
	event := tabs_list_refresh_merged(resolved_props, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(resolved_props, Tabs_List_State)

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = tabs_list_refresh_merged(resolved_props, &frame_state)
			config = frame_state.config
		}

		if skip_layout {
			return
		}

		can_interact := widget_can_interact(handlers, &frame_state)
		widget_register_tab_order(key, config.tabbable, can_interact)
		widget_children(
			props.child,
			layout_id,
			config,
			frame_state,
			key,
			cfg,
			props.on_scroll,
			frame_state.is_hovered,
		)

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) {
		return
	}

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)
	widget_handle_interaction(
		resolved_props,
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

	if widget_style_interaction_fp(&frame_state) != style_fp {
		event = tabs_list_refresh_merged(resolved_props, &frame_state)
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

	background: o.RGBA

	if resolved_background, ok := o.style_background_rgba(config, &frame_state, event); ok {
		background = resolved_background
	}

	border: o.Bd_px

	if resolved_border, ok := o.resolve_border(config.border, &frame_state, event); ok {
		border = resolved_border
	}

	border_color: o.RGBA

	if resolved_border_color, ok := o.style_border_color_rgba(config, &frame_state, event); ok {
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
		cfg,
		props.on_scroll,
		frame_state.is_hovered,
	)

	if frame_state.variant == .LINE && frame_state.orientation == .HORIZONTAL {
		line := o.Rect {
			x = rect.x,
			y = rect.y + rect.h - 1,
			w = rect.w,
			h = 1,
		}
		o.Draw_Rectangle(line, o.to_rgba_color(o.Color.BORDER))
	}

	widget_draw_box_border(layout_id, rect, radius, border, border_color)
	widget_dispatch_events(resolved_props, &frame_state, handlers, event, key, was_focused)
}
