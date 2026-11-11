package oni_widgets

import o ".."
import set "../set"
import "core:fmt"

Menubar_Item_Config :: struct {
	using _: o.Widget_Config,
	text_value: string,
	value: string,
	checked: bool,
	indeterminate: bool,
	close_on_select: o.Cfg(o.Style_Bool),
	inset: bool,
	destructive: bool,
	unmount: bool,
	can_interactive_during_mount: bool,
}

Menubar_Item_State :: Rectangle_State
Menubar_Item_Event :: Rectangle_Event

Menubar_Item_Props :: struct {
	config: Menubar_Item_Config,
	on_select: proc(event: Menubar_Item_Event) -> bool,
	on_checked_change: proc(checked: bool),
	child:                        proc(frame_state: Menubar_Item_State),
	on_mount:                     proc(frame_state: Menubar_Item_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Menubar_Item_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Menubar_Item_Event),
	on_blur:                      proc(event: Menubar_Item_Event),
	on_mouse_enter:               proc(event: Menubar_Item_Event),
	on_mouse_leave:               proc(event: Menubar_Item_Event),
	on_mouse_pressed:             proc(event: Menubar_Item_Event),
	on_mouse_down:                proc(event: Menubar_Item_Event),
	on_mouse_released:            proc(event: Menubar_Item_Event),
	on_mouse_move:                proc(event: Menubar_Item_Event),
	on_click:                     proc(event: Menubar_Item_Event),
	on_contextmenu:               proc(event: Menubar_Item_Event),
	on_key_pressed:               proc(event: Menubar_Item_Event),
	on_key_down:                  proc(event: Menubar_Item_Event),
	on_key_released:              proc(event: Menubar_Item_Event),
}

Menubar_Trigger_Config :: Menubar_Item_Config
Menubar_Trigger_State :: Menubar_Item_State
Menubar_Trigger_Event :: Menubar_Item_Event
Menubar_Trigger_Props :: Menubar_Item_Props
Menubar_Sub_Trigger_Config :: Menubar_Item_Config
Menubar_Sub_Trigger_State :: Menubar_Item_State
Menubar_Sub_Trigger_Event :: Menubar_Item_Event
Menubar_Sub_Trigger_Props :: Menubar_Item_Props
Menubar_Checkbox_Item_Config :: Menubar_Item_Config
Menubar_Checkbox_Item_State :: Menubar_Item_State
Menubar_Checkbox_Item_Event :: Menubar_Item_Event
Menubar_Checkbox_Item_Props :: Menubar_Item_Props
Menubar_Radio_Item_Config :: Menubar_Item_Config
Menubar_Radio_Item_State :: Menubar_Item_State
Menubar_Radio_Item_Event :: Menubar_Item_Event
Menubar_Radio_Item_Props :: Menubar_Item_Props

@(private)
Menubar_Part_Kind :: enum { TRIGGER, ITEM, CHECKBOX, RADIO, SUB }

@(private)
Menubar_Action :: struct {
	props: Menubar_Item_Props,
	entry: o.Menubar_Entry,
	kind: Menubar_Part_Kind,
	checked: bool,
}

@(private) menubar_action: ^Menubar_Action

@(private)
menubar_content_id :: proc(id: o.UI_Id) -> string {
	return fmt.tprintf("__menubar_content_%d", id)
}

@(private)
menubar_part_theme_base :: proc(state: ^Rectangle_State) -> o.Widget_Config {
	action := menubar_action
	bg := o.Color.TRANSPARENT
	opacity := f32(1)
	active := action.kind == .TRIGGER && menubar_ctx.value == action.entry.value

	if !state.is_disabled && (state.is_hovered || state.is_focused || active) do bg = .ACCENT
	if state.is_disabled do opacity = 0.5
	width := o.Width(o.Width_Mode.GROW)
	if action.kind == .TRIGGER do width = o.Width_Mode.FIT
	kinds := [Menubar_Part_Kind]o.Widget_Kind {
		.TRIGGER = .MENUBAR_TRIGGER, .ITEM = .MENUBAR_ITEM,
		.CHECKBOX = .MENUBAR_CHECKBOX_ITEM, .RADIO = .MENUBAR_RADIO_ITEM,
		.SUB = .MENUBAR_SUB_TRIGGER,
	}

	return {
		kind = kinds[action.kind], width = set.Width(width), height = set.Height(f32(30)),
		direction = set.Direction(menubar_ctx.rtl ? .HORIZONTAL_REVERSE : .HORIZONTAL),
		justify = set.Justify(o.Justify_Pos{x = .START, y = .CENTER}),
		padding = set.Padding(o.Pd_pos{x = 8, y = 4}),
		gap_x = set.Gap_X(u16(8)), background = set.Background(bg),
		radius = set.Radius(f32(4)), opacity = set.F32(opacity),
		tabbable = set.Tabbable(false), line_height = set.F32(1),
		color = action.props.config.destructive ? set.Color(o.Color.DESTRUCTIVE) : set.Color(o.Color.FOREGROUND),
	}
}

@(private)
menubar_part_child :: proc(state: Rectangle_State) {
	action := menubar_action
	cfg := action.props.config

	if action.kind == .CHECKBOX || action.kind == .RADIO || cfg.inset {
		mark := ""
		if action.checked do mark = action.kind == .RADIO ? "●" : "✓"
		if action.kind == .CHECKBOX && cfg.indeterminate do mark = "−"
		Text({config = {text = mark, width = set.Width(f32(16))}})
	}

	if action.props.child != nil {
		action.props.child(state)
	} else if cfg.text_value != "" {
		Text({config = {text = cfg.text_value, width = set.Width(.FIT)}})
	}

	if action.kind == .SUB {
		Text({config = {text = menubar_ctx.rtl ? "‹" : "›", width = set.Width(.GROW), align = set.Align(.RIGHT)}})
	}
}

@(private)
menubar_part_click :: proc(event: Rectangle_Event) {
	action := menubar_action
	ctx := menubar_ctx
	if ctx == nil || action.entry.disabled do return
	if action.kind != .TRIGGER && ctx.value != ctx.menu_value do return

	switch action.kind {
	case .TRIGGER:
		menubar_set_value(ctx.value == action.entry.value ? "" : action.entry.value, false)
		if ctx.value != "" && event.key != o.Scancode(0) {
			ctx.runtime.pending_group = action.entry.submenu
			ctx.runtime.pending_last = false
		}
	case .SUB:
		menubar_open_sub(action.entry, true)
	case .ITEM, .CHECKBOX, .RADIO:
		if action.props.on_select != nil && !action.props.on_select(event) do return

		if action.kind == .CHECKBOX && action.props.on_checked_change != nil {
			action.props.on_checked_change(!action.props.config.checked || action.props.config.indeterminate)
		}

		if action.kind == .RADIO && menubar_radio_ctx != nil && !action.checked && menubar_radio_ctx.on_value_change != nil {
			menubar_radio_ctx.on_value_change(action.props.config.value)
		}

		close := true
		if action.props.config.close_on_select.mode != .UNSET {
			close = o.cfg_style_bool(action.props.config.close_on_select)
		}
		if close do menubar_set_value("", true)
	}

	if event.key != o.Scancode(0) do menubar_consume(event.key)
	if action.props.on_click != nil do action.props.on_click(event)
}

@(private)
menubar_part_hover :: proc(event: Rectangle_Event) {
	action := menubar_action
	ctx := menubar_ctx
	if !o.w_ctx.mouse_moved || action.entry.disabled do return

	if action.kind == .TRIGGER {
		if ctx.value != "" {
			menubar_set_value(action.entry.value, false)
			o.widget_set_focused_id(action.entry.key)
		}
	} else {
		o.widget_set_focused_id(action.entry.key)

		if action.kind == .SUB {
			menubar_open_sub(action.entry, false)
		} else {
			ctx.runtime.depth = min(ctx.runtime.depth, ctx.level)
		}
	}

	if action.props.on_mouse_move != nil do action.props.on_mouse_move(event)
}

@(private)
menubar_part :: proc(props: Menubar_Item_Props, kind: Menubar_Part_Kind) {
	ctx := menubar_ctx
	if ctx == nil || ctx.menu_value == "" do return
	if kind != .TRIGGER && ctx.group == ctx.root do return
	if kind == .RADIO && (menubar_radio_ctx == nil || props.config.value == "") do return
	key := o.element_key(props.config.id)
	id := o.ui_id(key)
	disabled := ctx.disabled || ctx.menu_disabled || o.cfg_style_bool(props.config.disabled)
	if kind == .RADIO do disabled ||= menubar_radio_ctx.disabled
	entry := o.Menubar_Entry {
		id = id, key = key, value = kind == .TRIGGER ? ctx.menu_value : props.config.value,
		text = props.config.text_value, group = ctx.group, disabled = disabled,
		panel_key = ctx.panel_key,
	}
	for existing in ctx.seen {
		if existing.id == id || (kind == .TRIGGER && existing.group == ctx.root && existing.value == entry.value) {
			ctx.trigger = 0
			return
		}
	}
	append(&ctx.seen, entry)
	if kind == .TRIGGER || kind == .SUB {
		entry.submenu = ctx.menu_group
		ctx.trigger = id
	}

	if o.ui_pass() == .Layout {
		if props.config.unmount {
			entry.disabled = true
		}
		append(&ctx.runtime.entries, entry)
	} else {
		registered := false
		for existing in ctx.runtime.entries {
			if existing.id == id {
				entry = existing
				disabled ||= existing.disabled
				registered = true
				break
			}
		}
		if !registered do return
	}

	action := Menubar_Action {props = props, entry = entry, kind = kind, checked = props.config.checked}
	if kind == .RADIO do action.checked = menubar_radio_ctx.value == props.config.value
	previous := menubar_action
	menubar_action = &action
	defer menubar_action = previous
	cfg := o.merge_widget_config(o.Widget_Config{}, props.config)
	cfg.id = key
	cfg.tabbable = set.Tabbable(false)
	if disabled do cfg.disabled = set.Disabled(true)

	if o.ui_pass() == .Draw {
		rect := o.ui_layout_rect(id)
		space := ctx.group == ctx.root ? o.Draw_Space.SCREEN : o.Draw_Space.POPOVER
		if o.pointer_hits(id, rect, space) {
			ctx.pointer_inside = true
			if o.w_ctx.left_mouse.pressed && !disabled do o.widget_set_focused_id(key)
		}
	}

	panel := Rectangle_Props {
		config = cfg, child = menubar_part_child,
		unmount = props.config.unmount, can_interactive_during_mount = props.config.can_interactive_during_mount,
		on_mount = props.on_mount, on_unmount = props.on_unmount,
		on_scroll = props.on_scroll, on_focus = props.on_focus, on_blur = props.on_blur,
		on_mouse_enter = props.on_mouse_enter, on_mouse_leave = props.on_mouse_leave,
		on_mouse_pressed = props.on_mouse_pressed, on_mouse_down = props.on_mouse_down,
		on_mouse_released = props.on_mouse_released, on_mouse_move = menubar_part_hover,
		on_click = menubar_part_click, on_contextmenu = props.on_contextmenu,
		on_key_pressed = props.on_key_pressed, on_key_down = props.on_key_down,
		on_key_released = props.on_key_released,
	}
	rectangle_with_theme(panel, menubar_part_theme_base)

	if o.ui_pass() == .Layout {
		node_index, exists := o.state.ui.layout.id_to_node[id]
		inactive := !exists

		if exists {
			node := &o.state.ui.layout.nodes[node_index]
			inactive = node.config.disabled || o.layout_visibility_is_hidden(node.config.visibility)
			parent := node.parent

			for parent >= 0 {
				ancestor := &o.state.ui.layout.nodes[parent]
				inactive ||= ancestor.config.disabled || o.layout_visibility_is_hidden(ancestor.config.visibility)
				parent = ancestor.parent
			}
			lifecycle := o.widget_lifecycle_entry(id)
			inactive ||= lifecycle.unmounting == .RUNNING || (lifecycle.mounting == .RUNNING && !props.config.can_interactive_during_mount)
		}

		for &registered in ctx.runtime.entries {
			if registered.id == id do registered.disabled ||= inactive
		}
	}
}

Menubar_Trigger :: proc(props: Menubar_Trigger_Props) { menubar_part(props, .TRIGGER) }
Menubar_Item :: proc(props: Menubar_Item_Props) { menubar_part(props, .ITEM) }
Menubar_Checkbox_Item :: proc(props: Menubar_Checkbox_Item_Props) { menubar_part(props, .CHECKBOX) }
Menubar_Radio_Item :: proc(props: Menubar_Radio_Item_Props) { menubar_part(props, .RADIO) }
Menubar_Sub_Trigger :: proc(props: Menubar_Sub_Trigger_Props) { menubar_part(props, .SUB) }
