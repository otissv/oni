package oni_widgets

import o ".."
import set "../set"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

Menubar_Loop :: enum { ON, OFF }
Menubar_Direction :: enum { LTR, RTL }

Menubar_Config :: struct {
	using _: o.Widget_Config,
	value: string,
	unmount: bool,
	can_interactive_during_mount: bool,
	loop: Menubar_Loop,
	navigation_direction: Menubar_Direction,
}

Menubar_State :: Rectangle_State
Menubar_Event :: Rectangle_Event

Menubar_Props :: struct {
	config: Menubar_Config,
	child:                        proc(frame_state: Menubar_State),
	on_mount:                     proc(frame_state: Menubar_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Menubar_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Menubar_Event),
	on_blur:                      proc(event: Menubar_Event),
	on_mouse_enter:               proc(event: Menubar_Event),
	on_mouse_leave:               proc(event: Menubar_Event),
	on_mouse_pressed:             proc(event: Menubar_Event),
	on_mouse_down:                proc(event: Menubar_Event),
	on_mouse_released:            proc(event: Menubar_Event),
	on_mouse_move:                proc(event: Menubar_Event),
	on_click:                     proc(event: Menubar_Event),
	on_contextmenu:               proc(event: Menubar_Event),
	on_key_pressed:               proc(event: Menubar_Event),
	on_key_down:                  proc(event: Menubar_Event),
	on_key_released:              proc(event: Menubar_Event),
	on_value_change: proc(value: string),
}

@(private)
Menubar_Ctx :: struct {
	popup: Popover_Handle,
	seen: [dynamic]o.Menubar_Entry,
	root: o.UI_Id,
	runtime: o.Menubar_Runtime,
	value, menu_value: string,
	panel_key: string,
	group, menu_group, trigger: o.UI_Id,
	level: int,
	disabled, menu_disabled, pointer_inside: bool,
	can_interactive_during_mount: bool,
	rtl, loop: bool,
	on_value_change: proc(value: string),
	child: proc(state: Menubar_State),
}

// Scoped pointers are restored before return; retained state belongs to w_ctx.
@(private) menubar_ctx: ^Menubar_Ctx

@(private)
menubar_set_value :: proc(value: string, restore_focus: bool) {
	ctx := menubar_ctx

	if ctx == nil || ctx.disabled || ctx.value == value do return

	if restore_focus {
		for entry in ctx.runtime.entries {
			if entry.group == ctx.root && entry.value == ctx.value && !entry.disabled {
				o.widget_change_navigation_focus(entry.key)
				break
			}
		}
	}

	ctx.value = value
	ctx.runtime.depth = 0
	ctx.runtime.prefix_len = 0

	if ctx.on_value_change != nil {
		ctx.on_value_change(value)
	}
}

@(private)
menubar_entry_focused :: proc() -> int {
	for entry, i in menubar_ctx.runtime.entries {
		if entry.key == o.w_ctx.focused_id && !entry.disabled do return i
	}

	return -1
}

@(private)
menubar_focus_entry :: proc(entry: o.Menubar_Entry) {
	o.widget_change_navigation_focus(entry.key)
	if entry.panel_key == "" do return
	index, found := o.state.ui.layout.id_to_node[entry.id]

	if !found do return
	rect := o.state.ui.layout.nodes[index].rect
	parent := o.state.ui.layout.nodes[index].parent

	for parent >= 0 {
		node := &o.state.ui.layout.nodes[parent]

		if o.layout_node_is_scrollport(node) {
			viewport := o.layout_clip_box(node)
			delta: f32

			if rect.y < viewport.y {
				delta = rect.y - viewport.y
			} else if rect.y + rect.h > viewport.y + viewport.h {
				delta = rect.y + rect.h - viewport.y - viewport.h
			}

			if delta != 0 {
				scroll := o.widget_scroll_get(entry.panel_key)
				scroll.y = clamp(scroll.y + delta, 0, node.max_scroll.y)
				o.widget_scroll_set(entry.panel_key, scroll)
			}

			return
		}

		parent = node.parent
	}
}

@(private)
menubar_focus_group :: proc(group: o.UI_Id, last: bool) -> bool {
	ctx := menubar_ctx
	index := -1

	for entry, i in ctx.runtime.entries {
		if entry.group != group || entry.disabled do continue
		index = i
		if !last do break
	}

	if index < 0 do return false
	menubar_focus_entry(ctx.runtime.entries[index])
	ctx.runtime.pending_group = 0

	return true
}

@(private)
menubar_move :: proc(group: o.UI_Id, from, delta: int) -> int {
	entries := menubar_ctx.runtime.entries[:]
	count := len(entries)
	index := from

	for _ in 0 ..< count {
		index += delta

		if index < 0 || index >= count {
			if !menubar_ctx.loop do return -1
			index = index < 0 ? count - 1 : 0
		}

		if entries[index].group == group && !entries[index].disabled do return index
	}

	return -1
}

@(private)
menubar_open_sub :: proc(entry: o.Menubar_Entry, focus: bool) {
	ctx := menubar_ctx
	level := 0

	is_root_menu := false
	for candidate in ctx.runtime.entries {
		if candidate.group == ctx.root && candidate.submenu == entry.group do is_root_menu = true
	}

	if !is_root_menu {
		found := false

		for group, i in ctx.runtime.path[:ctx.runtime.depth] {
			if group == entry.group {
				level = i + 1
				found = true
				break
			}
		}

		if !found do return
	}

	if level >= len(ctx.runtime.path) do return
	ctx.runtime.path[level] = entry.submenu
	ctx.runtime.depth = level + 1

	if focus {
		ctx.runtime.pending_group = entry.submenu
		ctx.runtime.pending_last = false
	}
}

@(private)
menubar_close_sub :: proc() {
	ctx := menubar_ctx
	if ctx.runtime.depth <= 0 do return
	group := ctx.runtime.path[ctx.runtime.depth - 1]
	ctx.runtime.depth -= 1
	ctx.runtime.pending_group = 0

	for entry in ctx.runtime.entries {
		if entry.submenu == group && !entry.disabled {
			menubar_focus_entry(entry)
			break
		}
	}
}

@(private)
menubar_key :: proc(code: o.Scancode) -> bool {
	return o.w_ctx != nil && !o.shortcut_key_consumed(code) &&
	       (o.w_ctx.keys[int(code)].pressed || o.w_ctx.keys[int(code)].repeat)
}

@(private)
menubar_consume :: proc(code: o.Scancode) {
	o.state.shortcuts.consumed_keys[int(code)] = true
}

@(private)
menubar_keyboard :: proc() {
	ctx := menubar_ctx
	if ctx.disabled || !o.widget_focus_scope_allows(o.w_ctx.focused_id) do return
	if o.w_ctx.keys[int(o.Scancode.TAB)].pressed do return

	if ctx.runtime.pending_group != 0 {
		menubar_focus_group(ctx.runtime.pending_group, ctx.runtime.pending_last)
	}

	index := menubar_entry_focused()
	if index < 0 do return
	entry := ctx.runtime.entries[index]
	top := entry.group == ctx.root

	if menubar_key(.TAB) {
		// The engine has already moved focus in ui_end_layout_pass.
		menubar_set_value("", false)
		return
	}

	forward := ctx.rtl ? o.Scancode.LEFT : o.Scancode.RIGHT
	back := ctx.rtl ? o.Scancode.RIGHT : o.Scancode.LEFT

	if !top && menubar_key(forward) && entry.submenu != 0 {
		menubar_consume(forward)
		menubar_open_sub(entry, true)
		return
	}

	if !top && menubar_key(back) && ctx.runtime.depth > 0 {
		menubar_consume(back)
		menubar_close_sub()
		return
	}

	if top && (menubar_key(.DOWN) || menubar_key(.UP)) {
		last := menubar_key(.UP)
		menubar_consume(last ? .UP : .DOWN)
		menubar_set_value(entry.value, false)
		ctx.runtime.pending_group = entry.submenu
		ctx.runtime.pending_last = last
		menubar_focus_group(entry.submenu, last)
		return
	}

	if menubar_key(.HOME) || menubar_key(.END) {
		last := menubar_key(.END)
		menubar_consume(last ? .END : .HOME)
		menubar_focus_group(entry.group, last)

		if top && ctx.value != "" {
			focused := menubar_entry_focused()
			if focused >= 0 do menubar_set_value(ctx.runtime.entries[focused].value, false)
		}
		return
	}

	delta := 0
	code: o.Scancode
	group := entry.group

	if menubar_key(forward) {
		delta = 1
		code = forward
		group = ctx.root
	} else if menubar_key(back) {
		delta = -1
		code = back
		group = ctx.root
	} else if !top && menubar_key(.DOWN) {
		delta = 1
		code = .DOWN
	} else if !top && menubar_key(.UP) {
		delta = -1
		code = .UP
	}

	if delta != 0 {
		menubar_consume(code)

		if group == ctx.root && !top {
			for candidate, i in ctx.runtime.entries {
				if candidate.group == ctx.root && candidate.value == ctx.value {
					index = i
					break
				}
			}
		}

		next := menubar_move(group, index, delta)

		if next >= 0 {
			target := ctx.runtime.entries[next]
			menubar_focus_entry(target)

			if group == ctx.root && ctx.value != "" {
				menubar_set_value(target.value, false)
				ctx.runtime.pending_group = target.submenu
				ctx.runtime.pending_last = false
			}
		}

		return
	}

	menubar_typeahead(entry.group, index)
}

@(private)
menubar_typeahead :: proc(group: o.UI_Id, from: int) {
	input := o.state.input.text_input[:]
	if len(input) == 0 do return
	runtime := &menubar_ctx.runtime
	now := time.tick_now()._nsec

	if now - runtime.prefix_tick > 750_000_000 {
		runtime.prefix_len = 0
	}

	runtime.prefix_tick = now
	if runtime.prefix_len + len(input) > len(runtime.prefix) do runtime.prefix_len = 0
	if len(input) > len(runtime.prefix) do return
	copy(runtime.prefix[runtime.prefix_len:], input)
	runtime.prefix_len += len(input)
	prefix := string(runtime.prefix[:runtime.prefix_len])
	// Repeated characters cycle matches, rather than searching for "fff".
	first, first_width := utf8.decode_rune_in_string(prefix)
	repeated := true
	for c in prefix {
		if c != first do repeated = false
	}
	if repeated {
		runtime.prefix_len = first_width
		prefix = prefix[:first_width]
	}
	entries := runtime.entries[:]

	for offset in 1 ..= len(entries) {
		index := (from + offset) % len(entries)
		entry := entries[index]
		if entry.group != group || entry.disabled do continue
		if menubar_prefix_matches(entry.text, prefix) {
			menubar_focus_entry(entry)

			if group == menubar_ctx.root && menubar_ctx.value != "" {
				prefix_len := runtime.prefix_len
				menubar_set_value(entry.value, false)
				runtime.prefix_len = prefix_len
			}
			break
		}
	}
}

@(private)
menubar_prefix_matches :: proc(text, prefix: string) -> bool {
	text, prefix := text, prefix

	for len(prefix) > 0 {
		if len(text) == 0 do return false
		_, text_width := utf8.decode_rune_in_string(text)
		_, prefix_width := utf8.decode_rune_in_string(prefix)
		if !strings.equal_fold(text[:text_width], prefix[:prefix_width]) do return false
		text = text[text_width:]
		prefix = prefix[prefix_width:]
	}

	return true
}

@(private)
menubar_root_child :: proc(state: Rectangle_State) {
	ctx := menubar_ctx
	ctx.disabled ||= state.is_disabled
	ctx.disabled ||= state.unmounting == .RUNNING || (state.mounting == .RUNNING && !ctx.can_interactive_during_mount)

	if o.ui_pass() == .Draw {
		menubar_keyboard()
	}

	if ctx.child != nil do ctx.child(state)
}

// Available only within this root's child callback. Never retain a frame value.
Menubar_Get_Value :: proc() -> (value: string, ok: bool) {
	if menubar_ctx == nil do return "", false

	return menubar_ctx.value, true
}

// An empty value closes all menus. The callback requests a new caller-owned value.
Menubar :: proc(props: Menubar_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	root := o.ui_id(key)
	runtime := o.w_ctx.menubars[root]
	open_id := cfg.value == "" ? o.UI_Id(0) : o.ui_id(cfg.value)

	if o.ui_pass() == .Layout {
		if runtime.open_id != open_id {
			runtime.depth = 0
			runtime.prefix_len = 0
		}

		if open_id == 0 {
			runtime.depth = 0
			runtime.pending_group = 0
		}

		runtime.open_id = open_id
		runtime.frame = o.state.ui.frame
		runtime.entries = make([dynamic]o.Menubar_Entry, 0, 16, context.temp_allocator)
	}

	ctx := Menubar_Ctx {
		root = root, runtime = runtime, value = cfg.value,
		group = root, disabled = o.cfg_style_bool(cfg.disabled),
		rtl = cfg.navigation_direction == .RTL, loop = cfg.loop != .OFF,
		on_value_change = props.on_value_change, child = props.child,
		seen = make([dynamic]o.Menubar_Entry, 0, 16, context.temp_allocator),
		can_interactive_during_mount = cfg.can_interactive_during_mount,
	}
	previous := menubar_ctx
	previous_radio := menubar_radio_ctx
	menubar_ctx = &ctx
	menubar_radio_ctx = nil
	defer {
		menubar_ctx = previous
		menubar_radio_ctx = previous_radio
	}
	ctx.popup = popover_ctx_push({popover_key = key, open = cfg.value != "", disabled = ctx.disabled})
	defer popover_ctx_pop()

	base := o.Widget_Config {
		kind = .MENUBAR,
		id = cfg.id, width = set.Width(.FIT), height = set.Height(.FIT),
		direction = set.Direction(ctx.rtl ? .HORIZONTAL_REVERSE : .HORIZONTAL), padding = set.Padding(f32(4)),
		gap_x = set.Gap_X(u16(2)), border = set.Border(1),
		border_color = set.Border_color(o.Color.BORDER),
		background = set.Background(o.Color.BACKGROUND), radius = set.Radius(f32(6)),
		tabbable = set.Tabbable(false),
	}
	base = o.merge_widget_config(base, cfg)
	if cfg.text_direction.mode == .UNSET {
		base.text_direction = set.Text_Direction(ctx.rtl ? o.Text_Direction_Kind.RTL : o.Text_Direction_Kind.LTR)
	}
	base.id = key
	Rectangle({
		config = base,
		child = menubar_root_child,
		unmount = cfg.unmount,
		can_interactive_during_mount = cfg.can_interactive_during_mount,
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

	if !o.ui_has_layout_node(root) {
		delete_key(&o.w_ctx.menubars, root)
		return
	}

	if o.ui_pass() == .Draw && ctx.pointer_inside {
		Popover_Claim_Pointer(ctx.popup)
	}

	if o.ui_pass() == .Layout {
		for group, level in ctx.runtime.path[:ctx.runtime.depth] {
			valid := false
			for entry in ctx.runtime.entries {
				if entry.submenu == group && !entry.disabled do valid = true
			}
			if !valid {
				ctx.runtime.depth = level
				break
			}
		}
		if ctx.runtime.pending_group != 0 {
			valid := false
			for entry in ctx.runtime.entries {
				if entry.group == ctx.runtime.pending_group && !entry.disabled do valid = true
			}
			if !valid do ctx.runtime.pending_group = 0
		}
		menubar_sync_tab_stop()
	} else if ctx.value != "" {
		if o.w_ctx.keys[int(o.Scancode.TAB)].pressed {
			menubar_set_value("", false)
		} else if menubar_key(.ESCAPE) && !ctx.disabled && menubar_entry_focused() >= 0 && o.widget_focus_scope_allows(o.w_ctx.focused_id) {
			menubar_consume(.ESCAPE)
			if ctx.runtime.depth > 0 {
				menubar_close_sub()
			} else {
				menubar_set_value("", true)
			}
		} else if (o.w_ctx.left_mouse.pressed || o.w_ctx.right_mouse.pressed || o.w_ctx.middle_mouse.pressed) && !popover_context(ctx.popup).pointer_owned {
			menubar_set_value("", false)
		} else {
			// If a controlled menu disappears or is disabled, dismiss it once.
			valid := false
			for entry in ctx.runtime.entries {
				if entry.group == root && entry.value == ctx.value && !entry.disabled do valid = true
			}
			if !valid do menubar_set_value("", true)
		}
	}

	if o.w_ctx.menubars == nil do o.w_ctx.menubars = make(map[o.UI_Id]o.Menubar_Runtime)
	o.w_ctx.menubars[root] = ctx.runtime
}

@(private)
menubar_sync_tab_stop :: proc() {
	ctx := menubar_ctx
	wanted := ""

	for entry in ctx.runtime.entries {
		if entry.group != ctx.root || entry.disabled do continue
		if wanted == "" do wanted = entry.key
		if entry.key == o.w_ctx.focused_id || entry.value == ctx.value {
			wanted = entry.key
			break
		}
	}

	for entry in ctx.runtime.entries {
		for i := len(o.w_ctx.tab_order) - 1; i >= 0; i -= 1 {
			if o.w_ctx.tab_order[i] == entry.key do ordered_remove(&o.w_ctx.tab_order, i)
		}
	}

	if wanted != "" do o.register_tabbable(wanted)
}
