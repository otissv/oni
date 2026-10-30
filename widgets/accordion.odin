package oni_widgets

import o ".."
import set "../set"

// Selection is controlled. In single mode only the first nonempty value is used.
Accordion_Config :: struct {
	using widget:                 o.Widget_Config,
	value:                        []string,
	multiple:                     bool,
	prevent_collapse:             bool,
	unmount:                      bool,
	can_interactive_during_mount: bool,
}

// Root lifecycle and interaction state are supplied by Rectangle.
Accordion_State :: Rectangle_State
Accordion_Event :: Rectangle_Event

// on_value_change receives a frame-temporary slice of caller-owned strings.
// Copy the slice into app-owned storage to retain it beyond the current frame.
Accordion_Props :: struct {
	config:            Accordion_Config,
	child:             proc(frame_state: Accordion_State),
	on_mount:          proc(frame_state: Accordion_State) -> o.Mount,
	on_unmount:        proc(frame_state: Accordion_State) -> o.Mount,
	on_scroll:         proc(scroll_x, scroll_y: f32),
	on_focus:          proc(event: Accordion_Event),
	on_blur:           proc(event: Accordion_Event),
	on_mouse_enter:    proc(event: Accordion_Event),
	on_mouse_leave:    proc(event: Accordion_Event),
	on_mouse_pressed:  proc(event: Accordion_Event),
	on_mouse_down:     proc(event: Accordion_Event),
	on_mouse_released: proc(event: Accordion_Event),
	on_mouse_move:     proc(event: Accordion_Event),
	on_click:          proc(event: Accordion_Event),
	on_contextmenu:    proc(event: Accordion_Event),
	on_key_pressed:    proc(event: Accordion_Event),
	on_key_down:       proc(event: Accordion_Event),
	on_key_released:   proc(event: Accordion_Event),
	on_value_change:   proc(value: []string),
}

@(private)
accordion_theme_base :: proc(state: ^Rectangle_State) -> Rectangle_Config {
	_ = state

	return {
		kind = .ACCORDION,
		direction = set.Direction(.VERTICAL),
		width = set.Width(.GROW),
		gap_y = set.Gap_Y(u16(0)),
	}
}

// Compose Item descendants; their expansion is derived from a frozen selection.
Accordion :: proc(props: Accordion_Props) {
	root := Accordion_Ctx{config = props.config, on_value_change = props.on_value_change, child = props.child}
	root.value = accordion_normalize(props.config)
	previous := accordion_ctx
	previous_item := accordion_item_ctx
	accordion_ctx = &root
	accordion_item_ctx = nil
	defer {
		accordion_ctx = previous
		accordion_item_ctx = previous_item
	}

	cfg := props.config.widget
	cfg.id = o.element_key(cfg.id)

	if o.ui_pass() == .Draw {
		root.triggers = make([dynamic]Accordion_Trigger_Entry, 0, 8, context.temp_allocator)
	}

	rectangle_with_theme({
		config = cfg,
		child = accordion_child,
		unmount = props.config.unmount,
		can_interactive_during_mount = props.config.can_interactive_during_mount,
		on_mount = props.on_mount,
		on_unmount = props.on_unmount,
		on_scroll = props.on_scroll,
		on_focus = props.on_focus,
		on_blur = props.on_blur,
		on_mouse_enter = props.on_mouse_enter,
		on_mouse_leave = props.on_mouse_leave,
		on_mouse_pressed = props.on_mouse_pressed,
		on_mouse_down = props.on_mouse_down,
		on_mouse_released = props.on_mouse_released,
		on_mouse_move = props.on_mouse_move,
		on_click = props.on_click,
		on_contextmenu = props.on_contextmenu,
		on_key_pressed = props.on_key_pressed,
		on_key_down = props.on_key_down,
		on_key_released = props.on_key_released,
	}, accordion_theme_base)
}

@(private)
accordion_child :: proc(state: Rectangle_State) {
	root := accordion_ctx

	if root.child != nil {
		root.child(state)
	}

	if o.ui_pass() == .Draw {
		accordion_keyboard(root)
	}
}
