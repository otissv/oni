package oni_widgets

import o ".."

@(private)
Accordion_Ctx :: struct {
	config:          Accordion_Config,
	value:           []string,
	triggers:        [dynamic]Accordion_Trigger_Entry,
	child:           proc(Accordion_State),
	on_value_change: proc([]string),
}

@(private)
Accordion_Trigger_Entry :: struct {
	key:      string,
	item:     Accordion_Item_Ctx,
	event:    Accordion_Trigger_Event,
	on_focus: proc(Accordion_Trigger_Event),
	on_blur:  proc(Accordion_Trigger_Event),
}

@(private)
Accordion_Item_Ctx :: struct {
	root:     ^Accordion_Ctx,
	value:    string,
	open:     bool,
	disabled: bool,
}

// These pointers are scoped to synchronous widget calls and restored by defer.
@(private)
accordion_ctx: ^Accordion_Ctx

@(private)
accordion_item_ctx: ^Accordion_Item_Ctx

/*
Releases accordion frame context pointers.

Called from widget `Shutdown` and from tests so a later frame cannot observe a stale root.
*/
accordion_shutdown :: proc() {
	accordion_ctx = nil
	accordion_item_ctx = nil
	accordion_trigger_ctx = nil
}

@(private)
accordion_contains :: proc(values: []string, value: string) -> bool {
	for entry in values {
		if entry == value {
			return true
		}
	}

	return false
}

@(private)
accordion_normalize :: proc(cfg: Accordion_Config) -> []string {
	values := make([]string, len(cfg.value), context.temp_allocator)
	count := 0

	for value in cfg.value {
		if value == "" || accordion_contains(values[:count], value) {
			continue
		}

		values[count] = value
		count += 1

		if !cfg.multiple {
			break
		}
	}

	return values[:count]
}

@(private)
accordion_propose :: proc(root: ^Accordion_Ctx, value: string, open: bool) {
	if root == nil || value == "" || o.cfg_style_bool(root.config.disabled) || root.on_value_change == nil {
		return
	}

	selected := accordion_contains(root.value, value)

	if selected == open || (!open && root.config.prevent_collapse && len(root.value) <= 1) {
		return
	}

	next := make([]string, len(root.value) + 1, context.temp_allocator)
	count := 0

	if root.config.multiple || !open {
		for entry in root.value {
			if entry != value {
				next[count] = entry
				count += 1
			}
		}
	}

	if open {
		next[count] = value
		count += 1
	}

	root.on_value_change(next[:count])
}

@(private)
accordion_item_change :: proc(open: bool) {
	item := accordion_item_ctx

	if item == nil {
		return
	}

	// Collapsible toggles its live context before calling us. Restore the
	// layout snapshot before application code runs or content reads it.
	collapsible_ctx_top().open = item.open

	if !item.disabled {
		accordion_propose(item.root, item.value, open)
	}
}

// Reports the current item's rendered expansion, including inside custom children.
Accordion_Is_Open :: proc() -> bool {
	return accordion_item_ctx != nil && accordion_item_ctx.root == accordion_ctx && accordion_item_ctx.open
}

@(private)
accordion_keyboard :: proc(root: ^Accordion_Ctx) {
	if o.w_ctx == nil || o.cfg_style_bool(root.config.disabled) {
		return
	}

	candidates := [?]o.Scancode{.UP, .DOWN, .HOME, .END}
	code: o.Scancode
	found := false

	for candidate in candidates {
		key := o.w_ctx.keys[int(candidate)]

		if (key.pressed || key.repeat) && !o.shortcut_key_consumed(candidate) {
			code = candidate
			found = true
			break
		}
	}

	if !found {
		return
	}

	triggers := root.triggers
	current := -1

	for entry, index in triggers {
		if entry.key == o.w_ctx.focused_id {
			current = index
			break
		}
	}

	if current < 0 {
		return
	}

	target := current

	#partial switch code {
	case .UP: target = (current + len(triggers) - 1) % len(triggers)
	case .DOWN: target = (current + 1) % len(triggers)
	case .HOME: target = 0
	case .END: target = len(triggers) - 1
	case:
		return
	}

	o.shortcut_consume_key(code)

	if target == current {
		return
	}

	previous := triggers[current]
	next := triggers[target]
	o.widget_set_focused_id(next.key)
	previous.event.frame_state.is_focused = false
	previous.event.key = code
	next.event.frame_state.is_focused = true
	next.event.key = code
	saved_item := accordion_item_ctx
	defer { accordion_item_ctx = saved_item }

	if previous.on_blur != nil {
		accordion_item_ctx = &previous.item
		previous.on_blur(previous.event)
	}

	if next.on_focus != nil && o.w_ctx.focused_id == next.key {
		accordion_item_ctx = &next.item
		next.on_focus(next.event)
	}
}
