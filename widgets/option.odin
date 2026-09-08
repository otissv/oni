package oni_widgets

import o ".."
import set "../set"

/*
Option configuration (Radix Select.Item).
*/
Option_Config :: o.Widget_Config

/*
Option per-frame state including selection / highlight bits.
*/
Option_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	value:             string,
	text:              string,
	is_selected:       bool,
	is_highlighted:    bool,
}

/*
Option event snapshot.
*/
Option_Event :: o.Widget_Event(Option_State)

/*
Option props: a selectable row inside Select content.

`value` is required. `text` is the label shown by `Select_Value` (defaults to
`value` when empty). Optional `child` replaces the default text label.
*/
Option_Props :: struct {
	config:                       Option_Config,
	value:                        string,
	text:                         string,
	child:                        proc(frame_state: Option_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Option_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Option_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	scroll_bar:                   Scroll_Bar_Style,
	on_focus:                     proc(event: Option_Event),
	on_blur:                      proc(event: Option_Event),
	on_mouse_enter:               proc(event: Option_Event),
	on_mouse_leave:               proc(event: Option_Event),
	on_mouse_pressed:             proc(event: Option_Event),
	on_mouse_down:                proc(event: Option_Event),
	on_mouse_released:            proc(event: Option_Event),
	on_mouse_move:                proc(event: Option_Event),
	on_click:                     proc(event: Option_Event),
	on_contextmenu:               proc(event: Option_Event),
	on_key_pressed:               proc(event: Option_Event),
	on_key_down:                  proc(event: Option_Event),
	on_key_released:              proc(event: Option_Event),
}

@(private)
option_theme_base :: proc(frame_state: ^Option_State) -> Option_Config {
	bg := o.Color.TRANSPARENT

	if frame_state.is_highlighted || frame_state.is_hovered {
		bg = o.Color.ACCENT
	} else if frame_state.is_selected {
		bg = o.Color.MUTED
	}

	return Option_Config {
		kind = .OPTION,
		direction = set.Direction(.HORIZONTAL),
		justify = set.Justify(o.Justify_Pos{x = .START, y = .CENTER}),
		padding = set.Padding(o.Pd_pos{x = 10, y = 6}),
		radius = set.Radius(f32(4)),
		background = set.Background(bg),
		line_height = set.F32(1),
	}
}

@(private)
option_refresh_merged :: proc(props: Option_Props, frame_state: ^Option_State) -> Option_Event {
	event := widget_event(frame_state^)
	base := option_theme_base(frame_state)
	override := props.config
	frame_state.config = o.resolve_widget_config(base, override, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
option_display_text :: proc(props: Option_Props) -> string {
	if props.text != "" do return props.text

	return props.value
}

/*
Renders a selectable option for the parent Select.

Must be used inside `Select` content. Activating commits `value` (or toggles it
when `multiple`) and closes dropdown selects.
*/
Option :: proc(props: Option_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	text := option_display_text(props)
	disabled := o.cfg_style_bool(cfg.disabled)
	is_selected := false
	is_highlighted := false
	option_index := -1

	if select_ctx_ok() {
		ctx := select_ctx_top()

		if ctx.disabled {
			disabled = true
		}

		is_selected = select_ctx_has_value(ctx, props.value)
		option_index = select_register_option(props.value, text, key, disabled)
		is_highlighted = option_index >= 0 && option_index == ctx.highlight
	}

	frame_state := Option_State {
		is_disabled    = disabled,
		is_focused     = was_focused,
		value          = props.value,
		text           = text,
		is_selected    = is_selected,
		is_highlighted = is_highlighted,
	}

	event := option_refresh_merged(props, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props, Option_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	props_with_select := props
	props_with_select.on_click = option_on_click

	if select_ctx_ok() {
		ctx := select_ctx_top()
		ctx.option_child = props.child
		ctx.option_user_click = props.on_click
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
			event = option_refresh_merged(props, &frame_state)
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
				option_label_child,
				layout_id,
				config,
				frame_state,
				key,
				props.config,
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
		props_with_select,
		&frame_state,
		handlers,
		key,
		was_focused,
		config.tabbable,
		layout_id,
		rect,
		config,
	)

	if frame_state.is_hovered {
		select_note_pointer()

		if select_ctx_ok() && option_index >= 0 {
			select_ctx_top().highlight = option_index
			frame_state.is_highlighted = true
		}
	}

	widget_handle_scroll_wheel(layout_id, config, frame_state.is_hovered, key, props.on_scroll)
	scroll := o.widget_scroll_get(key)
	config.scroll_x = scroll.x
	config.scroll_y = scroll.y
	frame_state.config = config

	fp := widget_style_interaction_fp(&frame_state)

	if fp != style_fp || frame_state.is_highlighted != is_highlighted {
		event = option_refresh_merged(props, &frame_state)
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

	if !o.ui_layout_paint_skip(layout_id) {
		o.Draw_Rectangle(rect, background, radius, border, border_color)
	}

	widget_children(
		option_label_child,
		layout_id,
		config,
		frame_state,
		key,
		props.config,
		props.on_scroll,
		props.scroll_bar,
		frame_state.is_hovered,
	)

	widget_dispatch_events(props_with_select, &frame_state, handlers, event, key, was_focused)
}
