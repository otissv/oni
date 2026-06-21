package widgets

import oni ".."
import "core:fmt"
import sdl "vendor:sdl3"


merge_state_config :: proc(state: $S, config: $C) -> Widget_Merged_State(S, C) {
	return {state = state, config = config}
}

merge_state_event :: proc(
	state: $S,
	config: $C,
	mouse_button: u8 = 0,
	key: oni.Scancode = oni.Scancode(0),
) -> oni.Widget_Event(Widget_Merged_State(S, C)) {
	return {state = merge_state_config(state, config), mouse_button = mouse_button, key = key}
}


auto_element_id :: proc() -> oni.Widget_ID {
	idx := oni.w_ctx.auto_element_index
	oni.w_ctx.auto_element_index += 1

	id := fmt.tprintf("__auto_element__{0}", idx)

	return id
}

register_static_id :: proc(id: string, static_id: string) {
	if id == "" do return

	if oni.w_ctx.static_ids == nil {
		oni.w_ctx.static_ids = make(map[string]oni.Widget_ID)
	}

	oni.w_ctx.static_ids[id] = static_id
}

element_key :: proc(id: string) -> string {
	key := auto_element_id()
	register_static_id(id, key)
	return key
}

GetElementById :: proc(id: string) -> (static_id: string, ok: bool) {
	if oni.w_ctx.static_ids == nil do return {}, false
	static_id, ok = oni.w_ctx.static_ids[id]
	return
}

FocusElement :: proc(id: string) -> bool {
	element_id, ok := GetElementById(id)
	if !ok do return false

	oni.w_ctx.focused_id = element_id
	return true
}

clear_button_transients :: proc(button: ^oni.Widget_Mouse_Button_State) {
	button.pressed = false
	button.released = false
}

clear_key_transients :: proc(key: ^oni.Widget_Mouse_Key_State) {
	key.pressed = false
	key.released = false
}

sync_mouse_state :: proc() {
	x, y: f32
	buttons := sdl.GetMouseState(&x, &y)

	oni.w_ctx.mouse_x = x
	oni.w_ctx.mouse_y = y
	oni.w_ctx.left_mouse.down = .LEFT in buttons
	oni.w_ctx.right_mouse.down = .RIGHT in buttons
	oni.w_ctx.middle_mouse.down = .MIDDLE in buttons
}

update_mouse_button :: proc(button: ^oni.Widget_Mouse_Button_State, is_down: bool) {
	if is_down {
		if !button.down do button.pressed = true
		button.down = true
	} else {
		if button.down do button.released = true
		button.down = false
	}
}

update_key_state :: proc(key: ^oni.Widget_Mouse_Key_State, is_down, is_repeat: bool) {
	if is_down {
		if !key.down && !is_repeat do key.pressed = true
		key.down = true
	} else {
		if key.down do key.released = true
		key.down = false
	}
}

Shutdown :: proc() {
	if oni.w_ctx.static_ids != nil {
		delete(oni.w_ctx.static_ids)
	}
	if oni.w_ctx.element_was_hovered != nil {
		delete(oni.w_ctx.element_was_hovered)
	}
	if oni.w_ctx.element_pointer_down != nil {
		delete(oni.w_ctx.element_pointer_down)
	}
}

BeginFrame :: proc() {
	oni.ui_begin_frame()

	oni.w_ctx.auto_element_index = 0

	if oni.w_ctx.static_ids != nil {
		clear(&oni.w_ctx.static_ids)
	}

	oni.w_ctx.mouse_moved = false

	clear_button_transients(&oni.w_ctx.left_mouse)
	clear_button_transients(&oni.w_ctx.right_mouse)
	clear_button_transients(&oni.w_ctx.middle_mouse)

	for &key in oni.w_ctx.keys {
		clear_key_transients(&key)
	}

	sync_mouse_state()
}

EndLayoutPass :: proc() {
	oni.ui_end_layout_pass()
}

EndFrame :: proc() {
	oni.ui_end_frame()
}

ProcessEvent :: proc(event: ^sdl.Event) {
	#partial switch event.type {
	case .MOUSE_MOTION:
		oni.w_ctx.mouse_moved = true
		oni.w_ctx.mouse_x = event.motion.x
		oni.w_ctx.mouse_y = event.motion.y

	case .MOUSE_BUTTON_DOWN:
		oni.w_ctx.mouse_x = event.button.x
		oni.w_ctx.mouse_y = event.button.y

		switch event.button.button {
		case sdl.BUTTON_LEFT:
			update_mouse_button(&oni.w_ctx.left_mouse, true)
		case sdl.BUTTON_RIGHT:
			update_mouse_button(&oni.w_ctx.right_mouse, true)
		case sdl.BUTTON_MIDDLE:
			update_mouse_button(&oni.w_ctx.middle_mouse, true)
		}

	case .MOUSE_BUTTON_UP:
		oni.w_ctx.mouse_x = event.button.x
		oni.w_ctx.mouse_y = event.button.y

		switch event.button.button {
		case sdl.BUTTON_LEFT:
			update_mouse_button(&oni.w_ctx.left_mouse, false)
		case sdl.BUTTON_RIGHT:
			update_mouse_button(&oni.w_ctx.right_mouse, false)
		case sdl.BUTTON_MIDDLE:
			update_mouse_button(&oni.w_ctx.middle_mouse, false)
		}

	case .KEY_DOWN:
		idx := int(event.key.scancode)
		if idx >= 0 && idx < oni.KEY_COUNT {
			update_key_state(&oni.w_ctx.keys[idx], true, event.key.repeat)
		}

	case .KEY_UP:
		idx := int(event.key.scancode)
		if idx >= 0 && idx < oni.KEY_COUNT {
			update_key_state(&oni.w_ctx.keys[idx], false, false)
		}

	case .WINDOW_FOCUS_LOST:
		for &key in oni.w_ctx.keys {
			key.down = false
		}
	}
}

SetPointerState :: proc(position: [2]f32, pointerDown: bool) {
	_ = position
	_ = pointerDown
}

SyncPointer :: proc() {
	SetPointerState({oni.w_ctx.mouse_x, oni.w_ctx.mouse_y}, oni.w_ctx.left_mouse.down)
}
