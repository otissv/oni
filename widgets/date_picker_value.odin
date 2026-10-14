package oni_widgets

import o ".."
import set "../set"

/*
Date picker value configuration.
*/
Date_Picker_Value_Config :: o.Widget_Config

/*
Date picker value per-frame state with resolved display text.
*/
Date_Picker_Value_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	text:              string,
	placeholder:       string,
	has_value:         bool,
}

/*
Date picker value event snapshot.
*/
Date_Picker_Value_Event :: o.Widget_Event(Date_Picker_Value_State)

/*
Date picker value props: shows the formatted selection or `placeholder`.

When `child` is set it replaces the default label text.
*/
Date_Picker_Value_Props :: struct {
	config:                       Date_Picker_Value_Config,
	placeholder:                  string,
	child:                        proc(frame_state: Date_Picker_Value_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Date_Picker_Value_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Date_Picker_Value_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Date_Picker_Value_Event),
	on_blur:                      proc(event: Date_Picker_Value_Event),
	on_mouse_enter:               proc(event: Date_Picker_Value_Event),
	on_mouse_leave:               proc(event: Date_Picker_Value_Event),
	on_mouse_pressed:             proc(event: Date_Picker_Value_Event),
	on_mouse_down:                proc(event: Date_Picker_Value_Event),
	on_mouse_released:            proc(event: Date_Picker_Value_Event),
	on_mouse_move:                proc(event: Date_Picker_Value_Event),
	on_click:                     proc(event: Date_Picker_Value_Event),
	on_contextmenu:               proc(event: Date_Picker_Value_Event),
	on_key_pressed:               proc(event: Date_Picker_Value_Event),
	on_key_down:                  proc(event: Date_Picker_Value_Event),
	on_key_released:              proc(event: Date_Picker_Value_Event),
}

@(private)
date_picker_value_theme_base :: proc(
	frame_state: ^Date_Picker_Value_State,
) -> Date_Picker_Value_Config {
	_ = frame_state

	return Date_Picker_Value_Config {
		kind = .DATE_PICKER_VALUE,
		line_height = set.F32(1),
		pointer_events = set.Pointer_Events(.NONE),
	}
}

@(private)
date_picker_value_refresh_merged :: proc(
	props: Date_Picker_Value_Props,
	frame_state: ^Date_Picker_Value_State,
) -> Date_Picker_Value_Event {
	event := widget_event(frame_state^)
	base := date_picker_value_theme_base(frame_state)
	override := props.config
	frame_state.config = o.resolve_widget_config(base, override, frame_state, event)

	return widget_event(frame_state^)
}

/*
Renders the selected value label for the parent Date_Picker.

Must be used inside `Date_Picker` (typically inside `Date_Picker_Trigger`).
*/
Date_Picker_Value :: proc(props: Date_Picker_Value_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	text, has_value := date_picker_resolve_value_text(props.placeholder)

	frame_state := Date_Picker_Value_State {
		is_disabled = o.cfg_style_bool(cfg.disabled),
		is_focused  = was_focused,
		text        = text,
		placeholder = props.placeholder,
		has_value   = has_value,
	}

	event := date_picker_value_refresh_merged(props, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props, Date_Picker_Value_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	if date_picker_ctx_ok() {
		date_picker_ctx_top().value_child = props.child
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
			event = date_picker_value_refresh_merged(props, &frame_state)
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
				date_picker_value_label_child,
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

	if !widget_prepare_draw(handlers, layout_id, &frame_state) {
		return
	}

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)

	widget_handle_interaction(
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
	widget_handle_scroll_wheel(layout_id, config, frame_state.is_hovered, key, props.on_scroll)
	scroll := o.widget_scroll_get(key)
	config.scroll_x = scroll.x
	config.scroll_y = scroll.y
	frame_state.config = config

	fp := widget_style_interaction_fp(&frame_state)

	if fp != style_fp {
		event = date_picker_value_refresh_merged(props, &frame_state)
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
		date_picker_value_label_child,
		layout_id,
		config,
		frame_state,
		key,
		props.config,
		props.on_scroll,
		frame_state.is_hovered,
	)

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	widget_dispatch_events(props, &frame_state, handlers, event, key, was_focused)
}
