package oni_widgets

import o ".."
import sdl "vendor:sdl3"

/*
Pairs widget state with a resolved config into a merged state value.
*/
merge_state_config :: proc(state: $S, config: $C) -> o.Widget_Merged_State(S, C) {
	return {frame_state = state, config = config}
}

/*
Builds a widget event from separate state and config plus optional input metadata.
*/
merge_state_event :: proc(
	state: $S,
	config: $C,
	mouse_button: u8 = 0,
	key: o.Scancode = o.Scancode(0),
) -> o.Widget_Event(o.Widget_Merged_State(S, C)) {
	return {
		frame_state = merge_state_config(state, config),
		mouse_button = mouse_button,
		key = key,
	}
}

/*
Allocates the next auto-generated element id for widgets without an explicit id.
*/
auto_element_id :: proc() -> o.Widget_ID {
	return o.auto_element_id()
}

/*
Maps a user-facing id string to its runtime element key when one is provided.
*/
register_static_id :: proc(id: string, static_id: string) {
	o.register_static_id(id, static_id)
}

/*
Resolves the runtime element key for a widget, auto-generating one when id is empty.
*/
element_key :: proc(id: string) -> string {
	return o.element_key(id)
}

/*
Looks up the runtime element key registered for a user-facing id string.
*/
GetElementById :: proc(id: string) -> (static_id: string, ok: bool) {
	if o.w_ctx.static_ids == nil do return {}, false
	static_id, ok = o.w_ctx.static_ids[id]
	return
}

/*
Moves keyboard focus to the element registered under the given id.

Returns false when no element with that id has been registered this frame.
*/
FocusElement :: proc(id: string) -> bool {
	element_id, ok := GetElementById(id)
	if !ok do return false

	o.widget_set_focused_id(element_id)
	return true
}

/*
Returns the persisted scroll offset for a widget id registered this frame.
*/
Scroll_Get :: proc(id: string) -> (scroll: o.Vec2, ok: bool) {
	element_id, found := GetElementById(id)
	if !found do return {}, false
	return o.widget_scroll_get(element_id), true
}

/*
Sets the persisted scroll offset for a widget id registered this frame.
*/
Scroll_Set :: proc(id: string, scroll_x, scroll_y: f32) -> bool {
	element_id, ok := GetElementById(id)
	if !ok do return false
	o.widget_scroll_set(element_id, {scroll_x, scroll_y})
	return true
}

/*
Moves keyboard focus to the next tabbable element in declaration order.
*/
FocusNext :: proc() -> bool {
	return o.focus_next()
}

/*
Moves keyboard focus to the previous tabbable element in declaration order.
*/
FocusPrev :: proc() -> bool {
	return o.focus_prev()
}

/*
Clears one-frame pressed and released flags on a mouse button state.
*/
clear_button_transients :: proc(button: ^o.Widget_Mouse_Button_State) {
	button.pressed = false
	button.released = false
}

/*
Clears one-frame pressed, released, and repeat flags on a keyboard key state.
*/
clear_key_transients :: proc(key: ^o.Widget_Mouse_Key_State) {
	key.pressed = false
	key.released = false
	key.repeat = false
}

/*
Updates mouse button down state and sets pressed or released edge flags.
*/
update_mouse_button :: proc(button: ^o.Widget_Mouse_Button_State, is_down: bool) {
	if is_down {
		if !button.down do button.pressed = true
		button.down = true
	} else {
		if button.down do button.released = true
		button.down = false
	}
}

/*
Updates keyboard key down state and sets pressed, released, and repeat edge flags.

Repeat edges never set `pressed`, so global shortcuts stay press-once.
*/
update_key_state :: proc(key: ^o.Widget_Mouse_Key_State, is_down, is_repeat: bool) {
	key.repeat = is_down && is_repeat

	if is_down {
		if !key.down && !is_repeat {
			key.pressed = true
		}

		key.down = true
	} else {
		if key.down {
			key.released = true
		}

		key.down = false
	}
}

/*
Releases widget runtime maps allocated during the UI session.

Call when tearing down the widget layer or shutting down the application.
*/
Shutdown :: proc() {
	o.widget_ctx_shutdown()
}

/*
Finalizes the current layout pass after widget tree measurement.
*/
EndLayoutPass :: proc() {
	o.ui_end_layout_pass()
}

/*
Finalizes the current UI frame after the draw pass completes.
*/
EndFrame :: proc() {
	o.ui_end_frame()
}

/*
Runs each UI builder twice per frame: once for layout, once for draw.

Calls EndLayoutPass between passes and EndFrame after each draw pass.
*/
Render :: proc(ui: ..proc()) {
	for u in ui {
		u()
		EndLayoutPass()

		u()
		EndFrame()
	}
}

/*
Translates an SDL event into widget input state on the shared context.

Handles mouse motion, buttons, keyboard input, and window focus loss.
*/
ProcessEvent :: proc(event: ^sdl.Event) {
	o.widget_ctx_sync()
	#partial switch event.type {
	case .MOUSE_MOTION:
		o.w_ctx.mouse_moved = true
		o.w_ctx.mouse_x = event.motion.x
		o.w_ctx.mouse_y = event.motion.y

	case .MOUSE_BUTTON_DOWN:
		o.w_ctx.mouse_x = event.button.x
		o.w_ctx.mouse_y = event.button.y

		switch event.button.button {
		case sdl.BUTTON_LEFT:
			update_mouse_button(&o.w_ctx.left_mouse, true)
		case sdl.BUTTON_RIGHT:
			update_mouse_button(&o.w_ctx.right_mouse, true)
		case sdl.BUTTON_MIDDLE:
			update_mouse_button(&o.w_ctx.middle_mouse, true)
		}

	case .MOUSE_BUTTON_UP:
		o.w_ctx.mouse_x = event.button.x
		o.w_ctx.mouse_y = event.button.y

		switch event.button.button {
		case sdl.BUTTON_LEFT:
			update_mouse_button(&o.w_ctx.left_mouse, false)
		case sdl.BUTTON_RIGHT:
			update_mouse_button(&o.w_ctx.right_mouse, false)
		case sdl.BUTTON_MIDDLE:
			update_mouse_button(&o.w_ctx.middle_mouse, false)
		}

	case .KEY_DOWN:
		idx := int(event.key.scancode)
		if idx >= 0 && idx < o.KEY_COUNT {
			update_key_state(&o.w_ctx.keys[idx], true, event.key.repeat)
		}

	case .KEY_UP:
		idx := int(event.key.scancode)
		if idx >= 0 && idx < o.KEY_COUNT {
			update_key_state(&o.w_ctx.keys[idx], false, false)
		}

	case .WINDOW_FOCUS_LOST:
		for &key in o.w_ctx.keys {
			key.down = false
		}
	}
}

/*
Placeholder hook for external pointer state injection.

Currently unused; position and down state are ignored.
*/
SetPointerState :: proc(position: [2]f32, pointerDown: bool) {
	_ = position
	_ = pointerDown
}

/*
Forwards the current mouse position and left-button state to SetPointerState.
*/
SyncPointer :: proc() {
	SetPointerState({o.w_ctx.mouse_x, o.w_ctx.mouse_y}, o.w_ctx.left_mouse.down)
}
