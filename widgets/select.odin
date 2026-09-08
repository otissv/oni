package oni_widgets

import o ".."
import set "../set"

/*
Select root configuration (Radix Select.Root).
*/
Select_Config :: o.Widget_Config

/*
Select root per-frame state merged with resolved style and compound fields.
*/
Select_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	value:             string,
	values:            []string,
	open:              bool,
	name:              string,
	required:          bool,
	disabled:          bool,
	multiple:          bool,
	size:              u8,
	autocomplete:      string,
	listbox:           bool,
}

/*
Select root event snapshot.
*/
Select_Event :: o.Widget_Event(Select_State)

/*
Select root props: controlled value/open, compound children, and handlers.

`child` builds the trigger tree. `content` is the options panel (Radix Content);
when open it is laid out in a popover anchored under the trigger.

HTML-like fields:
- `disabled` — blocks interaction (also honors `config.disabled`)
- `multiple` — toggle many values; stays open; use `values` / `on_values_change`
- `size` — visible rows; `size > 1` or `multiple` renders an inline listbox
- `autocomplete` — form autofill hint string (e.g. `"on"` / `"off"`)
*/
Select_Props :: struct {
	config:                       Select_Config,
	value:                        string,
	values:                       []string,
	open:                         bool,
	name:                         string,
	required:                     bool,
	disabled:                     bool,
	multiple:                     bool,
	size:                         u8,
	autocomplete:                 string,
	on_value_change:              proc(value: string),
	on_values_change:             proc(values: []string),
	on_open_change:               proc(open: bool),
	child:                        proc(frame_state: Select_State),
	content:                      proc(frame_state: Select_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Select_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Select_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	scroll_bar:                   Scroll_Bar_Style,
	on_focus:                     proc(event: Select_Event),
	on_blur:                      proc(event: Select_Event),
	on_mouse_enter:               proc(event: Select_Event),
	on_mouse_leave:               proc(event: Select_Event),
	on_mouse_pressed:             proc(event: Select_Event),
	on_mouse_down:                proc(event: Select_Event),
	on_mouse_released:            proc(event: Select_Event),
	on_mouse_move:                proc(event: Select_Event),
	on_click:                     proc(event: Select_Event),
	on_contextmenu:               proc(event: Select_Event),
	on_key_pressed:               proc(event: Select_Event),
	on_key_down:                  proc(event: Select_Event),
	on_key_released:              proc(event: Select_Event),
}

@(private)
select_theme_base :: proc(frame_state: ^Select_State) -> Select_Config {
	_ = frame_state

	return Select_Config {
		kind = .SELECT,
		direction = set.Direction(.VERTICAL),
		gap_y = set.Gap_Y(u16(0)),
	}
}

@(private)
select_refresh_merged :: proc(props: Select_Props, frame_state: ^Select_State) -> Select_Event {
	event := widget_event(frame_state^)
	base := select_theme_base(frame_state)
	override := props.config
	frame_state.config = o.resolve_widget_config(base, override, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
select_refresh_merged_if_interaction_changed :: proc(
	props: Select_Props,
	frame_state: ^Select_State,
	prev_fp: u8,
) -> (
	event: Select_Event,
	fp: u8,
) {
	fp = widget_style_interaction_fp(frame_state)

	if fp == prev_fp {
		return widget_event(frame_state^), fp
	}

	return select_refresh_merged(props, frame_state), fp
}

@(private)
select_resolve_open_value :: proc(
	props: Select_Props,
	key: string,
) -> (
	open: bool,
	value: string,
	value_label: string,
	open_controlled: bool,
	value_controlled: bool,
) {
	open_controlled = props.on_open_change != nil
	value_controlled =
		(props.multiple && props.on_values_change != nil) ||
		(!props.multiple && props.on_value_change != nil)
	rt := select_runtime_ensure(key)

	if open_controlled {
		open = props.open
	} else if rt != nil {
		open = rt.open
	}

	if props.multiple {
		value = ""
		value_label = ""
	} else if value_controlled {
		value = props.value
	} else if rt != nil && rt.value_set {
		value = rt.value
	} else {
		value = props.value
	}

	if !props.multiple && rt != nil {
		value_label = rt.value_label
	}

	return
}

/*
Renders a Radix-style Select root.

Push compound context for Trigger / Value / Option parts. Optional `content` is
shown in a popover while open, or inline when `multiple` / `size > 1` (listbox).
Escape and outside pointer press dismiss dropdowns.
*/
Select :: proc(props: Select_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	open, value, value_label, open_controlled, value_controlled := select_resolve_open_value(
		props,
		key,
	)
	listbox := select_is_listbox(props.multiple, props.size)
	disabled := props.disabled || o.cfg_style_bool(cfg.disabled)

	if listbox {
		open = true
	}

	frame_state := Select_State {
		is_disabled  = disabled,
		is_focused   = was_focused,
		value        = value,
		values       = props.values,
		open         = open,
		name         = props.name,
		required     = props.required,
		disabled     = disabled,
		multiple     = props.multiple,
		size         = props.size,
		autocomplete = props.autocomplete,
		listbox      = listbox,
	}

	if props.disabled {
		cfg.disabled = set.Disabled(true)
	}

	props_resolved := props
	props_resolved.config = cfg

	event := select_refresh_merged(props_resolved, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props_resolved, Select_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	rt := select_runtime_ensure(key)
	highlight := -1

	if rt != nil {
		highlight = rt.highlight
	}

	select_ctx_push(
		{
			select_key = key,
			value = value,
			value_label = value_label,
			open = open,
			disabled = disabled,
			required = props.required,
			multiple = props.multiple,
			size = props.size,
			autocomplete = props.autocomplete,
			listbox = listbox,
			name = props.name,
			on_value_change = props.on_value_change,
			on_values_change = props.on_values_change,
			on_open_change = props.on_open_change,
			highlight = highlight,
			value_controlled = value_controlled,
			open_controlled = open_controlled,
			user_child = props.child,
			user_content = props.content,
		},
	)
	defer select_ctx_pop()

	ctx := select_ctx_top()

	if props.multiple {
		if value_controlled {
			select_copy_values_into_ctx(ctx, props.values)
		} else {
			select_load_runtime_values(ctx, rt)
		}

		frame_state.values = Select_Get_Values()
	}

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = select_refresh_merged(props_resolved, &frame_state)
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
				select_compound_child,
				layout_id,
				config,
				frame_state,
				key,
				props_resolved.config,
				props.on_scroll,
				props.scroll_bar,
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

	event, _ = select_refresh_merged_if_interaction_changed(props_resolved, &frame_state, style_fp)
	config = frame_state.config
	frame_state.open = select_ctx_top().open || select_ctx_top().listbox
	frame_state.value = select_ctx_top().value
	frame_state.values = Select_Get_Values()

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

	widget_children(
		select_compound_child,
		layout_id,
		config,
		frame_state,
		key,
		props_resolved.config,
		props.on_scroll,
		props.scroll_bar,
		frame_state.is_hovered,
	)

	ctx = select_ctx_top()

	if select_content_is_active(ctx) {
		trigger_focused := ctx.trigger_key != "" && widget_is_focused(ctx.trigger_key)
		root_focused := widget_is_focused(key)

		if trigger_focused || root_focused || ctx.listbox {
			select_handle_typing_keys()
		}

		if !ctx.listbox && o.w_ctx.left_mouse.pressed && !ctx.pointer_owned {
			select_set_open(false)
		}
	}

	widget_dispatch_events(props_resolved, &frame_state, handlers, event, key, was_focused)
}
