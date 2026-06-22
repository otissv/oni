package widgets

import oni ".."
import set "../set"
import sdl "vendor:sdl3"


Rectangle_Config :: oni.Widget_Config
Rectangle_State :: oni.Widget_Merged_State(oni.Widget_State, oni.Resolved_Widget_Config)
Rectangle_Event :: oni.Widget_Event(Rectangle_State)

Rectangle_Props :: struct {
	config:            Rectangle_Config,
	child:             proc(state: Rectangle_State),
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
		font = set.Font(oni.theme.font_body),
		font_size = set.F32(oni.theme.font_body.size_px),
		color = set.Colors(color),
		line_height = set.F32(1),
		text_direction = set.Text_Direction(.LTR),
		space = set.Inherit_Space(),
		justify = set.Justify(oni.theme.justify),
		gap = set.Gap(oni.theme.gap),
	}
}

@(private)
rect_config :: proc(
	props: Rectangle_Props,
	state: ^Rectangle_State,
) -> oni.Resolved_Widget_Config {
	event := rect_event(state^)

	base := rect_theme_base(state)
	override := rect_props_override(props)
	return oni.resolve_widget_config(base, override, state, event)
}

@(private)
rect_refresh_merged :: proc(props: Rectangle_Props, state: ^Rectangle_State) -> Rectangle_Event {
	state.config = rect_config(props, state)
	return rect_event(state^)
}

Rectangle :: proc(props: Rectangle_Props) {
	cfg := props.config
	key := oni.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := oni.ui_id(layout_label)

	was_focused := oni.w_ctx.focused_id == key
	should_auto_focus :=
		cfg.auto_focus.mode == .Value && cfg.auto_focus.value && oni.w_ctx.auto_focused_id != key

	if should_auto_focus {
		oni.w_ctx.focused_id = key
		oni.w_ctx.auto_focused_id = key
	}

	state := Rectangle_State {
		is_disabled = cfg.disabled.mode == .Value && cfg.disabled.value,
		is_focused  = oni.w_ctx.focused_id == key,
	}

	event := rect_refresh_merged(props, &state)
	config := state.config
	child := props.child

	if oni.ui_pass() == .Layout {
		oni.Children(child, layout_id, config, state)
		return
	}

	layout_rect := oni.ui_layout_rect(layout_id)
	rect := layout_rect
	if rect.w == 0 {
		if w := oni.length_resolve(config.width, 0); w > 0 do rect.w = w
	}
	if rect.h == 0 {
		if h := oni.length_resolve(config.height, 0); h > 0 do rect.h = h
	}

	state.is_hovered = oni.pointer_over(rect, config.space)
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

	event = rect_refresh_merged(props, &state)

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

	config = state.config

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

	oni.Draw_rectangle(rect, background, radius, border, border_color)

	oni.Children(child, layout_id, config, state)
}
