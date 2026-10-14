package oni_widgets

import o ".."
import set "../set"

/*
Radio item configuration.
*/
Radio_Config :: o.Widget_Config

/*
Radio per-frame state.

`checked` is true when this item's `value` is the group's current value.
`group_disabled` is true when the enclosing group is disabled, so the item
does not apply a second opacity fade on top of the group.
*/
Radio_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	value:             string,
	checked:           bool,
	group_disabled:    bool,
}

/*
Radio event snapshot.
*/
Radio_Event :: o.Widget_Event(Radio_State)

/*
Radio item props.

`value` is required and must be unique inside the parent `Radio_Group`. The
item is inert outside a group, when `value` is empty, or when another item
already registered the same value. `child` replaces the built-in dot and runs
only while `checked` is true.
*/
Radio_Props :: struct {
	config:                       Radio_Config,
	value:                        string,
	disabled:                     bool,
	child:                        proc(frame_state: Radio_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Radio_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Radio_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Radio_Event),
	on_blur:                      proc(event: Radio_Event),
	on_mouse_enter:               proc(event: Radio_Event),
	on_mouse_leave:               proc(event: Radio_Event),
	on_mouse_pressed:             proc(event: Radio_Event),
	on_mouse_down:                proc(event: Radio_Event),
	on_mouse_released:            proc(event: Radio_Event),
	on_mouse_move:                proc(event: Radio_Event),
	on_click:                     proc(event: Radio_Event),
	on_contextmenu:               proc(event: Radio_Event),
	on_key_pressed:               proc(event: Radio_Event),
	on_key_down:                  proc(event: Radio_Event),
	on_key_released:              proc(event: Radio_Event),
}

@(private)
Radio_Action :: struct {
	active:     bool,
	registered: bool,
	checked:    bool,
	value:      string,
	on_click:   proc(event: Radio_Event),
}

@(private)
radio_action: Radio_Action

@(private)
RADIO_DOT_SCALE :: f32(0.5)

@(private)
radio_theme_base :: proc(frame_state: ^Radio_State) -> Radio_Config {
	border_color := o.Color.BORDER

	if frame_state.is_Pressed {
		border_color = o.Color.PRIMARY_PRESSED
	} else if frame_state.is_hovered {
		border_color = o.Color.PRIMARY
	}

	if frame_state.is_focused {
		border_color = o.Color.RING
	}

	dot := o.Color.PRIMARY

	if frame_state.is_Pressed {
		dot = o.Color.PRIMARY_PRESSED
	} else if frame_state.is_hovered {
		dot = o.Color.PRIMARY_HOVER
	}

	opacity := f32(1)

	if frame_state.is_disabled && !frame_state.group_disabled {
		opacity = 0.5
	}

	return Radio_Config {
		kind = .RADIO,
		tabbable = set.Tabbable(false),
		width = set.Width(f32(16)),
		height = set.Height(f32(16)),
		justify = set.Justify(o.Justify_Align.CENTER),
		border = set.Border(f32(1)),
		border_color = set.Border_color(border_color),
		radius = set.Radius(f32(9999)),
		background = set.Background(o.Color.TRANSPARENT),
		color = set.Colors(dot),
		opacity = set.F32(opacity),
		overflow_x = set.Overflow_X(.HIDDEN),
		overflow_y = set.Overflow_Y(.HIDDEN),
	}
}

@(private)
radio_refresh_merged :: proc(props: Radio_Props, frame_state: ^Radio_State) -> Radio_Event {
	event := widget_event(frame_state^)
	base := radio_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
radio_checked_now :: proc(value: string, registered: bool) -> bool {
	if !registered || !radio_ctx_ok() || value == "" {
		return false
	}

	current := radio_ctx_top().value

	return current != "" && current == value
}

@(private)
radio_on_click :: proc(event: Radio_Event) {
	action := radio_action

	if !action.active {
		return
	}

	if event.key == .RETURN {
		return
	}

	if action.registered && !action.checked && action.value != "" && radio_ctx_ok() {
		ctx := radio_ctx_top()

		if action.value != ctx.value {
			if ctx.on_value_change != nil {
				ctx.on_value_change(action.value)
			}

			if radio_ctx_ok() {
				radio_ctx_top().value = action.value
			}
		}
	}

	if action.on_click != nil {
		action.on_click(event)
	}
}

@(private)
radio_draw_indicator :: proc(layout_id: o.UI_Id, rect: o.Rect, color: o.RGBA) {
	if o.ui_layout_paint_skip(layout_id) {
		return
	}

	min_side := min(rect.w, rect.h)
	dot := min_side * RADIO_DOT_SCALE

	if dot < 1 {
		return
	}

	dot_rect := o.Rect {
		x = rect.x + (rect.w - dot) * 0.5,
		y = rect.y + (rect.h - dot) * 0.5,
		w = dot,
		h = dot,
	}
	radius := o.Radius_px {
		tl = dot,
		tr = dot,
		bl = dot,
		br = dot,
	}
	o.Draw_Rectangle(dot_rect, color, radius)
}

@(private)
radio_lookup_registered :: proc(group_key, element_id: string) -> bool {
	snap := radio_snapshot_find(group_key)

	return radio_item_index(snap, element_id) >= 0
}

/*
Renders one radio item inside a `Radio_Group`.

Pointer release, Space, and a label `for_id` check this item. Enter does not.
Arrow keys are handled by the enclosing group before items paint, using this
item when it is focused. Disabled, mounting, duplicate, and out-of-group items
cannot be selected.
*/
Radio :: proc(props: Radio_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)
	in_group := radio_ctx_ok()
	group_key := ""
	group_disabled := false
	own_disabled := props.disabled || o.cfg_style_bool(cfg.disabled)

	if in_group {
		ctx := radio_ctx_top()
		group_key = ctx.key
		group_disabled = ctx.disabled
	}

	was_focused := widget_is_focused(key)
	frame_state := Radio_State {
		is_disabled    = own_disabled || group_disabled || !in_group,
		is_focused     = was_focused,
		value          = props.value,
		group_disabled = group_disabled,
	}
	registered := false

	if in_group && o.ui_pass() != .Layout {
		registered = radio_lookup_registered(group_key, key)
	}

	if !registered && o.ui_pass() != .Layout {
		frame_state.is_disabled = true
		frame_state.group_disabled = false
	}

	frame_state.checked = radio_checked_now(props.value, registered)

	if frame_state.is_disabled {
		cfg.disabled = set.Disabled(true)
	}

	resolved_props := props
	resolved_props.config = cfg
	event := radio_refresh_merged(resolved_props, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	checked_fp := frame_state.checked
	config := frame_state.config
	handlers := widget_lifecycle_handlers(resolved_props, Radio_State)
	indicator_child := props.child

	previous_action := radio_action
	radio_action = {
		active   = true,
		value    = props.value,
		on_click = props.on_click,
	}
	defer radio_action = previous_action

	props_with_select := resolved_props
	props_with_select.on_click = radio_on_click

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = radio_refresh_merged(resolved_props, &frame_state)
			config = frame_state.config
		}

		if skip_layout {
			return
		}

		can_interact := widget_can_interact(handlers, &frame_state)

		if in_group {
			registered = radio_register_item(
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
			frame_state.checked = false
		} else {
			frame_state.checked = radio_checked_now(props.value, true)
		}

		disabled_changed :=
			frame_state.is_disabled != (own_disabled || group_disabled || !in_group)

		if frame_state.checked != checked_fp || disabled_changed {
			event = radio_refresh_merged(resolved_props, &frame_state)
			config = frame_state.config
		}

		if !frame_state.checked {
			indicator_child = nil
		}

		widget_children(
			indicator_child,
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
	can_interact := widget_can_interact(handlers, &frame_state)
	// Every enabled registered item can take pointer focus. Only the roving
	// tab stop is in the tab order.
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
	frame_state.checked = radio_checked_now(props.value, registered)
	scroll := o.widget_scroll_get(key)
	config.scroll_x = scroll.x
	config.scroll_y = scroll.y
	frame_state.config = config

	if widget_style_interaction_fp(&frame_state) != style_fp || frame_state.checked != checked_fp {
		event = radio_refresh_merged(resolved_props, &frame_state)
		config = frame_state.config
	}

	if can_interact {
		if widget_got_tab_focus(key) && props.on_focus != nil {
			props.on_focus(event)
		}

		if widget_lost_tab_focus(key) && props.on_blur != nil {
			props.on_blur(event)
		}

		if radio_take_arrow_blur(key, group_key) && props.on_blur != nil {
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

	indicator_color: o.RGBA

	if resolved_color, ok := o.style_color_rgba(config, &frame_state, event); ok {
		indicator_color = resolved_color
	}

	if !frame_state.checked {
		indicator_child = nil
	}

	o.Draw_Push_Opacity(config.opacity)
	defer o.Draw_Pop_Opacity()

	widget_draw_box_background(layout_id, rect, background, radius)
	widget_children(
		indicator_child,
		layout_id,
		config,
		frame_state,
		key,
		cfg,
		props.on_scroll,
		frame_state.is_hovered,
	)

	if indicator_child == nil && frame_state.checked {
		radio_draw_indicator(layout_id, rect, indicator_color)
	}

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	if radio_claim_arrow_focus(key, group_key) && props.on_focus != nil {
		focus_event := event
		focus_event.frame_state = frame_state
		props.on_focus(focus_event)
	}

	radio_action.registered = registered && can_interact
	radio_action.checked = frame_state.checked

	widget_dispatch_events(props_with_select, &frame_state, handlers, event, key, was_focused)
	radio_note_drawn(key, frame_state)
}
