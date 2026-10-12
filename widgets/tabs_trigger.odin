package oni_widgets

import o ".."
import set "../set"

/*
Tabs trigger configuration (shadcn TabsTrigger / Base UI Tabs.Tab).
*/
Tabs_Trigger_Config :: o.Widget_Config

/*
Tabs trigger per-frame state.

`active` is true when this trigger's `value` is the root's current value.
`group_disabled` is true when the enclosing `Tabs` root is disabled, so the
trigger does not apply a second opacity fade on top of the root.
*/
Tabs_Trigger_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	value:             string,
	active:            bool,
	group_disabled:    bool,
	variant:           Tabs_List_Variant,
}

/*
Tabs trigger event snapshot.
*/
Tabs_Trigger_Event :: o.Widget_Event(Tabs_Trigger_State)

/*
Tabs trigger props.

`value` is required and must be unique inside the parent `Tabs`. The trigger is
inert outside a root, when `value` is empty, or when another trigger already
registered the same value.
*/
Tabs_Trigger_Props :: struct {
	config:                       Tabs_Trigger_Config,
	value:                        string,
	disabled:                     bool,
	child:                        proc(frame_state: Tabs_Trigger_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Tabs_Trigger_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Tabs_Trigger_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	scroll_bar:                   Scroll_Bar_Style,
	on_focus:                     proc(event: Tabs_Trigger_Event),
	on_blur:                      proc(event: Tabs_Trigger_Event),
	on_mouse_enter:               proc(event: Tabs_Trigger_Event),
	on_mouse_leave:               proc(event: Tabs_Trigger_Event),
	on_mouse_pressed:             proc(event: Tabs_Trigger_Event),
	on_mouse_down:                proc(event: Tabs_Trigger_Event),
	on_mouse_released:            proc(event: Tabs_Trigger_Event),
	on_mouse_move:                proc(event: Tabs_Trigger_Event),
	on_click:                     proc(event: Tabs_Trigger_Event),
	on_contextmenu:               proc(event: Tabs_Trigger_Event),
	on_key_pressed:               proc(event: Tabs_Trigger_Event),
	on_key_down:                  proc(event: Tabs_Trigger_Event),
	on_key_released:              proc(event: Tabs_Trigger_Event),
}

@(private)
Tabs_Trigger_Action :: struct {
	active:     bool,
	registered: bool,
	selected:   bool,
	value:      string,
	on_click:   proc(event: Tabs_Trigger_Event),
}

@(private)
tabs_trigger_action: Tabs_Trigger_Action

@(private)
tabs_trigger_theme_base :: proc(frame_state: ^Tabs_Trigger_State) -> Tabs_Trigger_Config {
	background := o.Color.TRANSPARENT
	color := o.Color.MUTED_FOREGROUND
	border := o.Bd {
		b = f32(1),
		t = f32(1),
		l = f32(1),
		r = f32(1),
	}
	border_color := o.Color.TRANSPARENT

	if frame_state.active {
		color = .FOREGROUND


		if frame_state.variant == .LINE {
			background = .TRANSPARENT
			border_color = .PRIMARY
			border = o.Bd {
				b = f32(0),
				t = f32(0),
				l = f32(0),
				r = f32(0),
			}
		} else {
			background = .BACKGROUND
		}

		if frame_state.is_focused {
			border_color = .RING
		}
	}

	if frame_state.is_hovered && !frame_state.active && !frame_state.is_disabled {
		color = .FOREGROUND
	}


	opacity := f32(1)

	if frame_state.is_disabled && !frame_state.group_disabled {
		opacity = 0.5
	}

	return Tabs_Trigger_Config {
		kind = .TABS_TRIGGER,
		tabbable = set.Tabbable(false),
		width = set.Width(.GROW),
		justify = set.Justify(o.Justify_Align.CENTER),
		padding = set.Padding(o.Pd_pos{x = 12, y = 6}),
		background = set.Background(background),
		wrap = set.Wrap(.PRESERVE),
		color = set.Colors(color),
		border = set.Border(border),
		border_color = set.Border_color(border_color),
		opacity = set.F32(opacity),
		overflow_x = set.Overflow_X(.HIDDEN),
		overflow_y = set.Overflow_Y(.HIDDEN),
	}
}

@(private)
tabs_trigger_refresh_merged :: proc(
	props: Tabs_Trigger_Props,
	frame_state: ^Tabs_Trigger_State,
) -> Tabs_Trigger_Event {
	event := widget_event(frame_state^)
	base := tabs_trigger_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
tabs_trigger_on_click :: proc(event: Tabs_Trigger_Event) {
	action := tabs_trigger_action

	if !action.active {
		return
	}

	if action.registered && action.value != "" && tabs_ctx_ok() {
		ctx := tabs_ctx_top()

		if action.value != ctx.value {
			if ctx.on_value_change != nil {
				ctx.on_value_change(action.value)
			}

			if tabs_ctx_ok() {
				tabs_ctx_top().value = action.value
			}
		}
	}

	if action.on_click != nil {
		action.on_click(event)
	}
}

/*
Renders one tab trigger inside a `Tabs` root.

Pointer release, Space, and Enter activate this trigger. Arrow keys are handled
by the enclosing root before triggers paint, using this trigger when it is
focused. Disabled, mounting, duplicate, and out-of-root triggers cannot activate.
*/
Tabs_Trigger :: proc(props: Tabs_Trigger_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)
	in_tabs := tabs_ctx_ok()
	group_key := ""
	group_disabled := false
	variant := Tabs_List_Variant.DEFAULT
	own_disabled := props.disabled || o.cfg_style_bool(cfg.disabled)

	if in_tabs {
		ctx := tabs_ctx_top()
		group_key = ctx.key
		group_disabled = ctx.disabled
		variant = ctx.variant
	}

	was_focused := widget_is_focused(key)
	frame_state := Tabs_Trigger_State {
		is_disabled    = own_disabled || group_disabled || !in_tabs,
		is_focused     = was_focused,
		value          = props.value,
		group_disabled = group_disabled,
		variant        = variant,
	}
	registered := false

	if in_tabs && o.ui_pass() != .Layout {
		registered = tabs_lookup_registered(group_key, key)
	}

	if !registered && o.ui_pass() != .Layout {
		frame_state.is_disabled = true
		frame_state.group_disabled = false
	}

	frame_state.active = tabs_active_now(props.value, registered)

	if frame_state.is_disabled {
		cfg.disabled = set.Disabled(true)
	}

	resolved_props := props
	resolved_props.config = cfg
	event := tabs_trigger_refresh_merged(resolved_props, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	active_fp := frame_state.active
	config := frame_state.config
	handlers := widget_lifecycle_handlers(resolved_props, Tabs_Trigger_State)
	child := props.child

	previous_action := tabs_trigger_action
	tabs_trigger_action = {
		active   = true,
		value    = props.value,
		on_click = props.on_click,
	}
	defer tabs_trigger_action = previous_action

	props_with_select := resolved_props
	props_with_select.on_click = tabs_trigger_on_click

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = tabs_trigger_refresh_merged(resolved_props, &frame_state)
			config = frame_state.config
		}

		if skip_layout {
			return
		}

		can_interact := widget_can_interact(handlers, &frame_state)

		if in_tabs {
			registered = tabs_register_trigger(
				{
					value = props.value,
					element_id = key,
					disabled = !can_interact,
					auto_focus = config.auto_focus,
					on_focus = props.on_focus,
				},
			)
		}

		if !registered {
			frame_state.is_disabled = true
			frame_state.group_disabled = false
			frame_state.active = false
		} else {
			frame_state.active = tabs_active_now(props.value, true)
		}

		disabled_changed := frame_state.is_disabled != (own_disabled || group_disabled || !in_tabs)

		if frame_state.active != active_fp || disabled_changed {
			event = tabs_trigger_refresh_merged(resolved_props, &frame_state)
			config = frame_state.config
		}

		widget_children(
			child,
			layout_id,
			config,
			frame_state,
			key,
			cfg,
			props.on_scroll,
			props.scroll_bar,
			frame_state.is_hovered,
		)

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) {
		return
	}

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)
	can_interact := widget_can_interact(handlers, &frame_state)
	pointer_tabbable := can_interact && registered
	widget_handle_interaction(
		props_with_select,
		&frame_state,
		handlers,
		key,
		was_focused,
		pointer_tabbable,
		layout_id,
		rect,
		config,
	)
	widget_handle_scroll_wheel(layout_id, config, frame_state.is_hovered, key, props.on_scroll)

	frame_state.is_focused = widget_is_focused(key)
	frame_state.active = tabs_active_now(props.value, registered)
	scroll := o.widget_scroll_get(key)
	config.scroll_x = scroll.x
	config.scroll_y = scroll.y
	frame_state.config = config

	if widget_style_interaction_fp(&frame_state) != style_fp || frame_state.active != active_fp {
		event = tabs_trigger_refresh_merged(resolved_props, &frame_state)
		config = frame_state.config
	}

	if can_interact {
		if widget_got_tab_focus(key) && props.on_focus != nil {
			props.on_focus(event)
		}

		if widget_lost_tab_focus(key) && props.on_blur != nil {
			props.on_blur(event)
		}

		if tabs_take_arrow_blur(key, group_key) && props.on_blur != nil {
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
		child,
		layout_id,
		config,
		frame_state,
		key,
		cfg,
		props.on_scroll,
		props.scroll_bar,
		frame_state.is_hovered,
	)

	if frame_state.active && frame_state.variant == .LINE && !o.ui_layout_paint_skip(layout_id) {
		line := o.Rect {
			x = rect.x,
			y = rect.y + rect.h - 2,
			w = rect.w,
			h = 2,
		}
		line_color := border_color

		if line_color.a == 0 {
			line_color = o.to_rgba_color(o.Color.PRIMARY)
		}

		o.Draw_Rectangle(line, line_color)
	}

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	if tabs_claim_arrow_focus(key, group_key) && props.on_focus != nil {
		focus_event := event
		focus_event.frame_state = frame_state
		props.on_focus(focus_event)
	}

	tabs_trigger_action.registered = registered && can_interact
	tabs_trigger_action.selected = frame_state.active

	widget_dispatch_events(props_with_select, &frame_state, handlers, event, key, was_focused)
	tabs_note_drawn(key, frame_state)
}
