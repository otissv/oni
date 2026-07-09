package widgets

import oni ".."
import sdl "vendor:sdl3"

/*
Builds a widget event carrying the current frame_state and optional input metadata.
*/
widget_event :: proc(
	frame_state: $S,
	mouse_button: u8 = 0,
	key: oni.Scancode = oni.Scancode(0),
) -> oni.Widget_Event(S) {
	return {frame_state = frame_state, mouse_button = mouse_button, key = key}
}

/*
Merges theme defaults, prop overrides, and live frame_state into a resolved config.
*/
widget_config :: proc(
	props: $P,
	frame_state: ^$S,
	theme_base: proc(frame_state: ^S) -> oni.Widget_Config,
) -> oni.Resolved_Widget_Config {
	event := widget_event(frame_state^)
	base := theme_base(frame_state)
	override := props.config
	return oni.resolve_widget_config(base, override, frame_state, event)
}

/*
Refreshes merged config on frame_state and returns a fresh event snapshot.
*/
@(private)
widget_refresh_merged :: proc(
	props: $P,
	frame_state: ^$S,
	theme_base: proc(frame_state: ^S) -> oni.Widget_Config,
) -> oni.Widget_Event(S) {
	frame_state.config = widget_config(props, frame_state, theme_base)
	return widget_event(frame_state^)
}

@(private)
widget_resolve_hit_rect :: proc(rect: oni.Rect, config: oni.Resolved_Widget_Config) -> oni.Rect {
	out := rect
	if out.w == 0 {
		if w := oni.length_resolve(config.width, 0); w > 0 do out.w = w
	}
	if out.h == 0 {
		if h := oni.length_resolve(config.height, 0); h > 0 do out.h = h
	}
	return out
}

@(private)
widget_lifecycle_handlers :: proc(props: $P, $S: typeid) -> Widget_Lifecycle_Handlers(S) {
	return {
		unmount = props.unmount,
		can_interactive_during_mount = props.can_interactive_during_mount,
		on_mount = props.on_mount,
		on_unmount = props.on_unmount,
	}
}

@(private)
widget_handle_interaction :: proc(
	props: $P,
	frame_state: ^$S,
	handlers: Widget_Lifecycle_Handlers(S),
	key: string,
	was_focused: bool,
	tabbable: bool,
	rect: oni.Rect,
	config: oni.Resolved_Widget_Config,
) -> (
	got_focus: bool,
	lost_focus: bool,
) {
	frame_state.is_hovered = oni.pointer_over(rect, config.space)
	frame_state.is_left_clicked = frame_state.is_hovered && oni.w_ctx.left_mouse.pressed
	frame_state.is_right_clicked = frame_state.is_hovered && oni.w_ctx.right_mouse.pressed
	frame_state.is_middle_clicked = frame_state.is_hovered && oni.w_ctx.middle_mouse.pressed
	frame_state.is_left_released = frame_state.is_hovered && oni.w_ctx.left_mouse.released
	frame_state.is_right_released = frame_state.is_hovered && oni.w_ctx.right_mouse.released
	frame_state.is_Pressed = frame_state.is_hovered && oni.w_ctx.left_mouse.down

	if !widget_can_interact(handlers, frame_state) do return

	return widget_handle_pointer_focus(
		key,
		tabbable,
		was_focused,
		frame_state.is_hovered,
		&frame_state.is_focused,
	)
}

@(private)
widget_dispatch_events :: proc(
	props: $P,
	frame_state: ^$S,
	handlers: Widget_Lifecycle_Handlers(S),
	event: oni.Widget_Event(S),
	key: string,
	got_focus: bool,
	lost_focus: bool,
) {
	if !widget_can_interact(handlers, frame_state) do return

	state := frame_state^

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
		props.on_contextmenu(widget_event(state, mouse_button = sdl.BUTTON_RIGHT))
	}

	if got_focus && props.on_focus != nil {
		props.on_focus(widget_event(state, mouse_button = sdl.BUTTON_LEFT))
	}

	if lost_focus && props.on_blur != nil {
		props.on_blur(widget_event(state, mouse_button = sdl.BUTTON_LEFT))
	}

	if state.is_hovered && props.on_mouse_pressed != nil {
		if oni.w_ctx.left_mouse.pressed {
			props.on_mouse_pressed(widget_event(state, mouse_button = sdl.BUTTON_LEFT))
		}
		if oni.w_ctx.right_mouse.pressed {
			props.on_mouse_pressed(widget_event(state, mouse_button = sdl.BUTTON_RIGHT))
		}
		if oni.w_ctx.middle_mouse.pressed {
			props.on_mouse_pressed(widget_event(state, mouse_button = sdl.BUTTON_MIDDLE))
		}
	}

	if state.is_hovered && props.on_mouse_down != nil {
		if oni.w_ctx.left_mouse.down {
			props.on_mouse_down(widget_event(state, mouse_button = sdl.BUTTON_LEFT))
		}
		if oni.w_ctx.right_mouse.down {
			props.on_mouse_down(widget_event(state, mouse_button = sdl.BUTTON_RIGHT))
		}
		if oni.w_ctx.middle_mouse.down {
			props.on_mouse_down(widget_event(state, mouse_button = sdl.BUTTON_MIDDLE))
		}
	}

	if state.is_hovered && props.on_mouse_released != nil {
		if oni.w_ctx.left_mouse.released {
			props.on_mouse_released(widget_event(state, mouse_button = sdl.BUTTON_LEFT))
		}
		if oni.w_ctx.right_mouse.released {
			props.on_mouse_released(widget_event(state, mouse_button = sdl.BUTTON_RIGHT))
		}
		if oni.w_ctx.middle_mouse.released {
			props.on_mouse_released(widget_event(state, mouse_button = sdl.BUTTON_MIDDLE))
		}
	}

	clicked := oni.consume_pointer_click(
		key,
		state.is_hovered,
		oni.w_ctx.left_mouse.pressed,
		oni.w_ctx.left_mouse.released,
	)
	click_event := widget_event(state, mouse_button = sdl.BUTTON_LEFT)

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
			key_frame_state := oni.w_ctx.keys[scancode]
			key_event := widget_event(state, key = oni.Scancode(scancode))

			if props.on_key_pressed != nil && key_frame_state.pressed {
				props.on_key_pressed(key_event)
			}
			if props.on_key_down != nil && key_frame_state.down {
				props.on_key_down(key_event)
			}
			if props.on_key_released != nil && key_frame_state.released {
				props.on_key_released(key_event)
			}
		}
	}
}
