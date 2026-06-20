package widgets


import oni ".."
import sdl "vendor:sdl3"


Rectangle_Config :: struct {
	using _: oni.Widget_config,
}

Rectangle_State :: oni.Widget_Merged_State(oni.Widget_State, Rectangle_Config)

Rectangle_Event :: oni.Widget_Event(Rectangle_State)

Rectangle_Props :: struct {
	using config:      Rectangle_Config,
	on_focus:          proc(event: Rectangle_Event),
	on_blur:           proc(event: Rectangle_Event),
	on_mouse_enter:    proc(event: Rectangle_Event),
	on_mouse_leave:    proc(event: Rectangle_Event),
	on_mouse_pressed:  proc(event: Rectangle_Event),
	on_mouse_down:     proc(event: Rectangle_Event),
	on_mouse_released: proc(event: Rectangle_Event),
	on_mouse_move:     proc(event: Rectangle_Event),
	on_click:          proc(event: Rectangle_Event),
	on_contextmenu:    proc(event: Rectangle_Event),
	on_key_pressed:    proc(event: Rectangle_Event),
	on_key_down:       proc(event: Rectangle_Event),
	on_key_released:   proc(event: Rectangle_Event),
}


@(private)
rect_event :: proc(
	state: Rectangle_State,
	mouse_button: u8 = 0,
	key: oni.Scancode = oni.Scancode(0),
) -> Rectangle_Event {
	return {state = state, mouse_button = mouse_button, key = key}
}

@(private)
rect_props_override :: proc(props: Rectangle_Props) -> Rectangle_Config {
	return props.config
}

@(private)
rect_theme_base :: proc(state: ^Rectangle_State) -> Rectangle_Config {
	color := oni.Color.Text

	if state.is_disabled {
		color = oni.Color.Text_muted
	}

	return Rectangle_Config {
		kind = .RECT,
		font = oni.theme.font_body,
		font_size = oni.theme.font_body.size_px,
		color = color,
		line_height = 1,
		text_direction = .LTR,
		space = .Screen,
		justify = oni.theme.justify,
		gap = oni.theme.gap,
	}
}

@(private)
rect_config :: proc(props: Rectangle_Props, state: ^Rectangle_State) -> Rectangle_Config {
	event := rect_event(state^)

	base := rect_theme_base(state)
	override := rect_props_override(props)

	resolved := oni.merge_element_declaration(base, override, state, event)

	override.color = resolved.color
	override.background = resolved.background
	override.border_color = resolved.border_color
	override.padding = resolved.padding
	override.radius = resolved.radius
	override.border = resolved.border
	override.gap = resolved.gap
	override.justify = resolved.justify
	override.direction = resolved.direction
	override.font = resolved.font
	override.font_size = resolved.font_size
	override.space = resolved.space
	override.line_height = resolved.line_height
	return override
}

@(private)
rect_refresh_merged :: proc(props: Rectangle_Props, state: ^Rectangle_State) -> Rectangle_Event {
	state.config = rect_config(props, state)
	return rect_event(state^)
}

Rectangle :: proc(props: Rectangle_Props) {
	key := oni.element_key(props.id)

	was_focused := oni.w_ctx.focused_id == key
	should_auto_focus := props.auto_focus && oni.w_ctx.auto_focused_id != key

	if should_auto_focus {
		oni.w_ctx.focused_id = key
		oni.w_ctx.auto_focused_id = key
	}

	state := Rectangle_State {
		is_disabled = props.disabled,
		is_focused  = oni.w_ctx.focused_id == key,
	}

	state.is_hovered = oni.pointer_over(
		{x = props.x, y = props.y, w = props.width, h = props.height},
		props.space,
	)
	state.is_left_clicked = state.is_hovered && oni.w_ctx.left_mouse.pressed
	state.is_right_clicked = state.is_hovered && oni.w_ctx.right_mouse.pressed
	state.is_middle_clicked = state.is_hovered && oni.w_ctx.middle_mouse.pressed
	state.is_left_released = state.is_hovered && oni.w_ctx.left_mouse.released
	state.is_right_released = state.is_hovered && oni.w_ctx.right_mouse.released
	state.is_Pressed = state.is_hovered && oni.w_ctx.left_mouse.down

	got_focus := false
	lost_focus := false

	if !state.is_disabled {
		if state.is_hovered && oni.w_ctx.left_mouse.pressed && !state.is_focused {
			oni.w_ctx.focused_id = key
			state.is_focused = true
			got_focus = true
		}

		if was_focused && !state.is_hovered && oni.w_ctx.left_mouse.pressed {
			oni.w_ctx.focused_id = {}
			state.is_focused = false
			lost_focus = true
		}
	}

	event := rect_refresh_merged(props, &state)

	if !state.is_disabled {
		entered, left := oni.consume_hover_transition(key, state.is_hovered)

		if entered && props.on_mouse_enter != nil {
			props.on_mouse_enter(event)
		}
		if left && props.on_mouse_leave != nil {
			props.on_mouse_leave(event)
		}

		if state.is_hovered && oni.w_ctx.mouse_moved && props.on_mouse_move != nil {
			props.on_mouse_move(event)
		}

		if state.is_hovered && oni.w_ctx.right_mouse.pressed && props.on_contextmenu != nil {
			props.on_contextmenu(rect_event(state, mouse_button = sdl.BUTTON_RIGHT))
		}

		if got_focus && props.on_focus != nil {
			props.on_focus(rect_event(state, mouse_button = sdl.BUTTON_LEFT))
		}

		if lost_focus && props.on_blur != nil {
			props.on_blur(rect_event(state, mouse_button = sdl.BUTTON_LEFT))
		}

		if state.is_hovered && props.on_mouse_pressed != nil {
			if oni.w_ctx.left_mouse.pressed {
				props.on_mouse_pressed(rect_event(state, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.pressed {
				props.on_mouse_pressed(rect_event(state, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.pressed {
				props.on_mouse_pressed(rect_event(state, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		if state.is_hovered && props.on_mouse_down != nil {
			if oni.w_ctx.left_mouse.down {
				props.on_mouse_down(rect_event(state, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.down {
				props.on_mouse_down(rect_event(state, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.down {
				props.on_mouse_down(rect_event(state, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		if state.is_hovered && props.on_mouse_released != nil {
			if oni.w_ctx.left_mouse.released {
				props.on_mouse_released(rect_event(state, mouse_button = sdl.BUTTON_LEFT))
			}
			if oni.w_ctx.right_mouse.released {
				props.on_mouse_released(rect_event(state, mouse_button = sdl.BUTTON_RIGHT))
			}
			if oni.w_ctx.middle_mouse.released {
				props.on_mouse_released(rect_event(state, mouse_button = sdl.BUTTON_MIDDLE))
			}
		}

		clicked := oni.consume_pointer_click(
			key,
			state.is_hovered,
			oni.w_ctx.left_mouse.pressed,
			oni.w_ctx.left_mouse.released,
		)
		click_event := rect_event(state, mouse_button = sdl.BUTTON_LEFT)

		if state.is_focused && props.on_click != nil {
			enter_key := oni.w_ctx.keys[int(sdl.Scancode.RETURN)]
			space_key := oni.w_ctx.keys[int(sdl.Scancode.SPACE)]

			if enter_key.pressed {
				clicked = true
				click_event.key = oni.Scancode(sdl.Scancode.RETURN)
			} else if space_key.pressed {
				clicked = true
				click_event.key = oni.Scancode(sdl.Scancode.SPACE)
			}
		}

		if clicked && props.on_click != nil {
			props.on_click(click_event)
		}

		if state.is_focused {
			for scancode in 0 ..< oni.KEY_COUNT {
				key_state := oni.w_ctx.keys[scancode]
				key_event := rect_event(state, key = oni.Scancode(scancode))

				if props.on_key_pressed != nil && key_state.pressed {
					props.on_key_pressed(key_event)
				}
				if props.on_key_down != nil && key_state.down {
					props.on_key_down(key_event)
				}
				if props.on_key_released != nil && key_state.released {
					props.on_key_released(key_event)
				}
			}
		}
	}

	if should_auto_focus && !was_focused && props.on_focus != nil {
		props.on_focus(event)
	}

	config := state.config

	background: oni.RGBA
	if resolved_background, background_ok := oni.to_rgba(config.background, &state, event);
	   background_ok {
		background = resolved_background
	}

	border: oni.Bd
	if resolved_border, border_ok := oni.resolve_border(config.border, &state, event); border_ok {
		border = resolved_border
	}

	border_color: oni.RGBA
	if resolved_border_color, border_color_ok := oni.to_rgba(config.border_color, &state, event);
	   border_color_ok {
		border_color = resolved_border_color
	}

	radius: oni.Radius_corners
	if resolved_radius, ok := oni.resolve_radius(config.radius, &state, event); ok {
		radius = resolved_radius
	}

	rect := oni.Rect {
		x = config.x,
		y = config.y,
		w = config.width,
		h = config.height,
	}

	// oni.Draw_Rectangle(rect, background, radius, border, border_color)

	oni.Draw_Rectangle(rect, background, 10)
}
