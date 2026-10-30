package oni_widgets

import o ".."
import set "../set"

// Each item needs a nonempty value unique within its root.
Accordion_Item_Config :: struct {
	using widget:                 o.Widget_Config,
	value:                        string,
	unmount:                      bool,
	can_interactive_during_mount: bool,
}

Accordion_Item_State :: Collapsible_State
Accordion_Item_Event :: Collapsible_Event

Accordion_Item_Props :: struct {
	config:            Accordion_Item_Config,
	child:             proc(frame_state: Accordion_Item_State),
	on_mount:          proc(frame_state: Accordion_Item_State) -> o.Mount,
	on_unmount:        proc(frame_state: Accordion_Item_State) -> o.Mount,
	on_scroll:         proc(scroll_x, scroll_y: f32),
	on_focus:          proc(event: Accordion_Item_Event),
	on_blur:           proc(event: Accordion_Item_Event),
	on_mouse_enter:    proc(event: Accordion_Item_Event),
	on_mouse_leave:    proc(event: Accordion_Item_Event),
	on_mouse_pressed:  proc(event: Accordion_Item_Event),
	on_mouse_down:     proc(event: Accordion_Item_Event),
	on_mouse_released: proc(event: Accordion_Item_Event),
	on_mouse_move:     proc(event: Accordion_Item_Event),
	on_click:          proc(event: Accordion_Item_Event),
	on_contextmenu:    proc(event: Accordion_Item_Event),
	on_key_pressed:    proc(event: Accordion_Item_Event),
	on_key_down:       proc(event: Accordion_Item_Event),
	on_key_released:   proc(event: Accordion_Item_Event),
}

// An item composes the existing Collapsible lifecycle, layout and interaction.
// Orphan or empty-valued items are inert and closed.
Accordion_Item :: proc(props: Accordion_Item_Props) {
	root := accordion_ctx
	item := Accordion_Item_Ctx{root = root, value = props.config.value}
	cfg := props.config.widget
	cfg.kind = .ACCORDION_ITEM
	item.disabled = root == nil || props.config.value == "" || o.cfg_style_bool(cfg.disabled)

	if root != nil {
		item.disabled = item.disabled || o.cfg_style_bool(root.config.disabled)
		item.open = accordion_contains(root.value, item.value)
	}

	cfg.disabled = set.Disabled(item.disabled)
	previous := accordion_item_ctx
	accordion_item_ctx = &item
	defer { accordion_item_ctx = previous }

	collapsible_cfg := Collapsible_Config{open = item.open}
	collapsible_cfg.widget = cfg
	Collapsible({
		config = collapsible_cfg,
		on_open_change = accordion_item_change,
		child = props.child,
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
	})
}
