package oni_widgets

import o ".."
import sdl "vendor:sdl3"

/*
Builds a widget event carrying the current frame_state and optional input metadata.
*/
widget_event :: proc(
	frame_state: $S,
	mouse_button: u8 = 0,
	key: o.Scancode = o.Scancode(0),
) -> o.Widget_Event(S) {
	return {frame_state = frame_state, mouse_button = mouse_button, key = key}
}

/*
Merges theme defaults, prop overrides, and live frame_state into a resolved config.
*/
widget_config :: proc(
	props: $P,
	frame_state: ^$S,
	theme_base: proc(frame_state: ^S) -> o.Widget_Config,
) -> o.Resolved_Widget_Config {
	event := widget_event(frame_state^)
	base := theme_base(frame_state)
	override := props.config
	return o.resolve_widget_config(base, override, frame_state, event)
}

/*
Refreshes merged config on frame_state and returns a fresh event snapshot.
*/
@(private)
widget_refresh_merged :: proc(
	props: $P,
	frame_state: ^$S,
	theme_base: proc(frame_state: ^S) -> o.Widget_Config,
) -> o.Widget_Event(S) {
	frame_state.config = widget_config(props, frame_state, theme_base)
	return widget_event(frame_state^)
}

/*
Fingerprint of interaction bits that typically drive stateful style procs.

Used to skip a second resolve_widget_config when Draw-pass interaction matches
the fingerprint captured at the first merge this call.
*/
@(private)
widget_style_interaction_fp :: proc(frame_state: ^$S) -> u8 {
	fp: u8
	if frame_state.is_hovered do fp |= 1
	if frame_state.is_focused do fp |= 2
	if frame_state.is_Pressed do fp |= 4
	if frame_state.is_disabled do fp |= 8
	return fp
}

/*
Re-merges style only when interaction bits changed since `prev_fp`.
*/
@(private)
widget_refresh_merged_if_interaction_changed :: proc(
	props: $P,
	frame_state: ^$S,
	theme_base: proc(frame_state: ^S) -> o.Widget_Config,
	prev_fp: u8,
) -> (
	event: o.Widget_Event(S),
	fp: u8,
) {
	fp = widget_style_interaction_fp(frame_state)
	if fp == prev_fp {
		return widget_event(frame_state^), fp
	}
	return widget_refresh_merged(props, frame_state, theme_base), fp
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
	layout_id: o.UI_Id,
	rect: o.Rect,
	config: o.Resolved_Widget_Config,
) -> (
	got_focus: bool,
	lost_focus: bool,
) {
	o.draw_set_stack_index(o.ui_layout_stack_index(layout_id))
	frame_state.is_hovered = o.pointer_hits(layout_id, rect, config.space)
	frame_state.is_pointer_target = o.pointer_is_target(layout_id)
	frame_state.is_left_clicked =
		frame_state.is_hovered &&
		o.w_ctx.left_mouse.pressed &&
		!o.shortcut_mouse_consumed(sdl.BUTTON_LEFT)
	frame_state.is_right_clicked =
		frame_state.is_hovered &&
		o.w_ctx.right_mouse.pressed &&
		!o.shortcut_mouse_consumed(sdl.BUTTON_RIGHT)
	frame_state.is_middle_clicked =
		frame_state.is_hovered &&
		o.w_ctx.middle_mouse.pressed &&
		!o.shortcut_mouse_consumed(sdl.BUTTON_MIDDLE)
	frame_state.is_left_released = frame_state.is_hovered && o.w_ctx.left_mouse.released
	frame_state.is_right_released = frame_state.is_hovered && o.w_ctx.right_mouse.released
	frame_state.is_Pressed = frame_state.is_hovered && o.w_ctx.left_mouse.down

	if !widget_can_interact(handlers, frame_state) do return

	return widget_handle_pointer_focus(
		key,
		tabbable,
		was_focused,
		frame_state.is_pointer_target,
		&frame_state.is_focused,
	)
}

/*
Dispatches enter/leave, pointer, focus, click, and keyboard handlers for a widget.

Pointer handlers (move/press/down/release/click/contextmenu) are skipped when
`o.stop_propagation()` was already called this frame so ancestors that dispatch
after Children do not receive bubbled events. Enter/leave and keyboard are not
gated by the stop flag.
*/
@(private)
widget_dispatch_events :: proc(
	props: $P,
	frame_state: ^$S,
	handlers: Widget_Lifecycle_Handlers(S),
	event: o.Widget_Event(S),
	key: string,
	got_focus: bool,
	lost_focus: bool,
) {
	if !widget_can_interact(handlers, frame_state) do return

	state := frame_state^
	propagate := !o.w_ctx.pointer_propagation_stopped

	entered, left := o.consume_hover_transition(key, state.is_hovered)

	if entered && props.on_mouse_enter != nil {
		props.on_mouse_enter(event)
	}
	if left && props.on_mouse_leave != nil {
		props.on_mouse_leave(event)
	}

	if propagate && state.is_hovered && o.w_ctx.mouse_moved && props.on_mouse_move != nil {
		props.on_mouse_move(event)
	}

	if propagate &&
	   state.is_hovered &&
	   o.w_ctx.right_mouse.pressed &&
	   !o.shortcut_mouse_consumed(sdl.BUTTON_RIGHT) &&
	   props.on_contextmenu != nil {
		props.on_contextmenu(widget_event(state, mouse_button = sdl.BUTTON_RIGHT))
	}

	if got_focus && props.on_focus != nil {
		props.on_focus(widget_event(state, mouse_button = sdl.BUTTON_LEFT))
	}

	if lost_focus && props.on_blur != nil {
		props.on_blur(widget_event(state, mouse_button = sdl.BUTTON_LEFT))
	}

	if propagate && state.is_hovered && props.on_mouse_pressed != nil {
		if o.w_ctx.left_mouse.pressed && !o.shortcut_mouse_consumed(sdl.BUTTON_LEFT) {
			props.on_mouse_pressed(widget_event(state, mouse_button = sdl.BUTTON_LEFT))
		}
		if o.w_ctx.right_mouse.pressed && !o.shortcut_mouse_consumed(sdl.BUTTON_RIGHT) {
			props.on_mouse_pressed(widget_event(state, mouse_button = sdl.BUTTON_RIGHT))
		}
		if o.w_ctx.middle_mouse.pressed && !o.shortcut_mouse_consumed(sdl.BUTTON_MIDDLE) {
			props.on_mouse_pressed(widget_event(state, mouse_button = sdl.BUTTON_MIDDLE))
		}
	}

	if propagate && state.is_hovered && props.on_mouse_down != nil {
		if o.w_ctx.left_mouse.down {
			props.on_mouse_down(widget_event(state, mouse_button = sdl.BUTTON_LEFT))
		}
		if o.w_ctx.right_mouse.down {
			props.on_mouse_down(widget_event(state, mouse_button = sdl.BUTTON_RIGHT))
		}
		if o.w_ctx.middle_mouse.down {
			props.on_mouse_down(widget_event(state, mouse_button = sdl.BUTTON_MIDDLE))
		}
	}

	if propagate && state.is_hovered && props.on_mouse_released != nil {
		if o.w_ctx.left_mouse.released {
			props.on_mouse_released(widget_event(state, mouse_button = sdl.BUTTON_LEFT))
		}
		if o.w_ctx.right_mouse.released {
			props.on_mouse_released(widget_event(state, mouse_button = sdl.BUTTON_RIGHT))
		}
		if o.w_ctx.middle_mouse.released {
			props.on_mouse_released(widget_event(state, mouse_button = sdl.BUTTON_MIDDLE))
		}
	}

	clicked := o.consume_pointer_click(
		key,
		state.is_hovered,
		o.w_ctx.left_mouse.pressed,
		o.w_ctx.left_mouse.released,
	)
	click_event := widget_event(state, mouse_button = sdl.BUTTON_LEFT)

	if state.is_focused && props.on_click != nil {
		enter_key := o.w_ctx.keys[int(sdl.Scancode.RETURN)]
		space_key := o.w_ctx.keys[int(sdl.Scancode.SPACE)]

		if enter_key.pressed && !o.shortcut_key_consumed(.RETURN) {
			clicked = true
			click_event.key = o.Scancode(sdl.Scancode.RETURN)
		} else if space_key.pressed && !o.shortcut_key_consumed(.SPACE) {
			clicked = true
			click_event.key = o.Scancode(sdl.Scancode.SPACE)
		}
	}

	if clicked && props.on_click != nil {
		keyboard_click := click_event.key != o.Scancode(0)
		if propagate || keyboard_click {
			props.on_click(click_event)
		}
	}

	if state.is_focused {
		for scancode in 0 ..< o.KEY_COUNT {
			if o.shortcut_key_consumed(o.Scancode(scancode)) do continue
			key_frame_state := o.w_ctx.keys[scancode]
			key_event := widget_event(state, key = o.Scancode(scancode))

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
