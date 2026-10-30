package oni_widgets

import o ".."

// Trigger and Content retain the full Collapsible styling and lifecycle API.
Accordion_Trigger_Config :: struct {
	using widget:                 Collapsible_Trigger_Config,
	unmount:                      bool,
	can_interactive_during_mount: bool,
}
Accordion_Trigger_State :: Collapsible_Trigger_State
Accordion_Trigger_Event :: Collapsible_Trigger_Event
Accordion_Trigger_Props :: struct {
	config:            Accordion_Trigger_Config,
	child:             proc(frame_state: Accordion_Trigger_State),
	on_mount:          proc(frame_state: Accordion_Trigger_State) -> o.Mount,
	on_unmount:        proc(frame_state: Accordion_Trigger_State) -> o.Mount,
	on_scroll:         proc(scroll_x, scroll_y: f32),
	on_focus:          proc(event: Accordion_Trigger_Event),
	on_blur:           proc(event: Accordion_Trigger_Event),
	on_mouse_enter:    proc(event: Accordion_Trigger_Event),
	on_mouse_leave:    proc(event: Accordion_Trigger_Event),
	on_mouse_pressed:  proc(event: Accordion_Trigger_Event),
	on_mouse_down:     proc(event: Accordion_Trigger_Event),
	on_mouse_released: proc(event: Accordion_Trigger_Event),
	on_mouse_move:     proc(event: Accordion_Trigger_Event),
	on_click:          proc(event: Accordion_Trigger_Event),
	on_contextmenu:    proc(event: Accordion_Trigger_Event),
	on_key_pressed:    proc(event: Accordion_Trigger_Event),
	on_key_down:       proc(event: Accordion_Trigger_Event),
	on_key_released:   proc(event: Accordion_Trigger_Event),
}

Accordion_Content_Config :: struct {
	using content:                Collapsible_Content_Config,
	unmount:                      bool,
	can_interactive_during_mount: bool,
}
Accordion_Content_State :: Collapsible_Content_State
Accordion_Content_Event :: Collapsible_Content_Event
Accordion_Content_Props :: struct {
	config:            Accordion_Content_Config,
	child:             proc(frame_state: Accordion_Content_State),
	on_mount:          proc(frame_state: Accordion_Content_State) -> o.Mount,
	on_unmount:        proc(frame_state: Accordion_Content_State) -> o.Mount,
	on_scroll:         proc(scroll_x, scroll_y: f32),
	on_focus:          proc(event: Accordion_Content_Event),
	on_blur:           proc(event: Accordion_Content_Event),
	on_mouse_enter:    proc(event: Accordion_Content_Event),
	on_mouse_leave:    proc(event: Accordion_Content_Event),
	on_mouse_pressed:  proc(event: Accordion_Content_Event),
	on_mouse_down:     proc(event: Accordion_Content_Event),
	on_mouse_released: proc(event: Accordion_Content_Event),
	on_mouse_move:     proc(event: Accordion_Content_Event),
	on_click:          proc(event: Accordion_Content_Event),
	on_contextmenu:    proc(event: Accordion_Content_Event),
	on_key_pressed:    proc(event: Accordion_Content_Event),
	on_key_down:       proc(event: Accordion_Content_Event),
	on_key_released:   proc(event: Accordion_Content_Event),
}

@(private)
Accordion_Trigger_Ctx :: struct {
	props: Accordion_Trigger_Props,
	root:  ^Accordion_Ctx,
	key:   string,
}

@(private)
accordion_trigger_ctx: ^Accordion_Trigger_Ctx

// Compose a label, icon, or arbitrary noninteractive children inside the trigger.
Accordion_Trigger :: proc(props: Accordion_Trigger_Props) {
	if accordion_item_ctx == nil || accordion_item_ctx.root != accordion_ctx {
		return
	}

	resolved := Collapsible_Trigger_Props{
		config = props.config.widget,
		unmount = props.config.unmount,
		can_interactive_during_mount = props.config.can_interactive_during_mount,
		child = props.child,
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
	}

	resolved.config.kind = .ACCORDION_TRIGGER
	resolved.config.id = o.element_key(resolved.config.id)
	trigger := Accordion_Trigger_Ctx{props = props, root = accordion_ctx, key = resolved.config.id}
	previous := accordion_trigger_ctx
	accordion_trigger_ctx = &trigger
	defer { accordion_trigger_ctx = previous }
	resolved.child = accordion_trigger_child
	Collapsible_Trigger(resolved)
}

@(private)
accordion_trigger_child :: proc(state: Accordion_Trigger_State) {
	trigger := accordion_trigger_ctx

	if trigger.root != nil && o.ui_pass() == .Draw {
		for key in o.w_ctx.tab_order {
			if key != trigger.key {
				continue
			}

			append(&trigger.root.triggers, Accordion_Trigger_Entry{
				key = key,
				item = accordion_item_ctx^,
				event = widget_event(state),
				on_focus = trigger.props.on_focus,
				on_blur = trigger.props.on_blur,
			})
			break
		}
	}

	if trigger.props.child != nil {
		trigger.props.child(state)
	}
}

// Closed content is removed from layout; force_mount uses HIDDEN instead.
Accordion_Content :: proc(props: Accordion_Content_Props) {
	if accordion_item_ctx == nil || accordion_item_ctx.root != accordion_ctx {
		return
	}

	resolved := Collapsible_Content_Props{
		config = props.config.content,
		unmount = props.config.unmount,
		can_interactive_during_mount = props.config.can_interactive_during_mount,
		child = props.child,
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
	}

	resolved.config.kind = .ACCORDION_CONTENT
	Collapsible_Content(resolved)
}
