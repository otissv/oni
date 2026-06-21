package oni

import "core:hash"


UI_Pass :: enum {
	Layout,
	Draw,
}

ui_init :: proc() {
	if state.ui.widgets == nil {
		state.ui.widgets = make(map[UI_Id]UI_Widget_Entry)
	}
	if state.ui.layout.id_to_node == nil {
		state.ui.layout.id_to_node = make(map[UI_Id]int)
	}
}

ui_shutdown :: proc() {
	if state.ui.widgets != nil {
		for _, &entry in state.ui.widgets {
			shaped_text_release(&entry.shaped)
		}
		clear(&state.ui.widgets)
		delete(state.ui.widgets)
		state.ui.widgets = nil
	}

	delete(state.ui.scope_stack)
	state.ui.scope_stack = nil

	delete(state.ui.style_stack)
	state.ui.style_stack = nil

	layout_reset()
	delete(state.ui.layout.id_to_node)
	state.ui.layout.id_to_node = nil

	state.ui.frame = 0
	state.ui.pass = .Layout
}

ui_begin_frame :: proc() {
	ui_init()
	state.ui.frame += 1
	state.ui.pass = .Layout
	clear(&state.ui.scope_stack)
	clear(&state.ui.style_stack)
	layout_reset()
}

ui_end_layout_pass :: proc() {
	state.ui.pass = .Draw
}

ui_end_frame :: proc() {
	if state.ui.widgets == nil do return

	remove_ids := make([dynamic]UI_Id, context.temp_allocator)
	for id, entry in state.ui.widgets {
		if entry.last_frame != state.ui.frame {
			append(&remove_ids, id)
		}
	}

	for id in remove_ids {
		if entry, ok := &state.ui.widgets[id]; ok {
			shaped_text_release(&entry.shaped)
			delete_key(&state.ui.widgets, id)
		}
	}
}

ui_pass :: proc() -> UI_Pass {
	return state.ui.pass
}

ui_layout_rect :: proc(id: UI_Id) -> Rect {
	if node_index, ok := state.ui.layout.id_to_node[id]; ok {
		return state.ui.layout.nodes[node_index].rect
	}
	return {}
}

ui_push_scope :: proc(id: UI_Id) {
	append(&state.ui.scope_stack, id)
}

ui_pop_scope :: proc() {
	if len(state.ui.scope_stack) > 0 {
		ordered_remove(&state.ui.scope_stack, len(state.ui.scope_stack) - 1)
	}
}

ui_parent_hash :: proc() -> u64 {
	h: u64 = 14695981039346656037
	for scope in state.ui.scope_stack {
		h ~= u64(scope)
		h *= 1099511628211
	}
	return h
}

ui_id :: proc(label: string) -> UI_Id {
	label_hash := u64(hash.crc32(transmute([]u8)label))
	parent := ui_parent_hash()
	return UI_Id(label_hash ~ parent)
}
