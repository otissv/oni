package app

import "core:hash"

UI_State :: struct {
	frame:       u64,
	scope_stack: [dynamic]UI_Id,
	widgets:     map[UI_Id]UI_Widget_Entry,
}

UI_Widget_Entry :: struct {
	shaped:     Shaped_Text,
	last_frame: u64,
}

ui_init :: proc() {
	if g.ui.widgets == nil {
		g.ui.widgets = make(map[UI_Id]UI_Widget_Entry)
	}
}

ui_shutdown :: proc() {
	if g.ui.widgets != nil {
		for _, &entry in g.ui.widgets {
			shaped_text_release(&entry.shaped)
		}
		clear(&g.ui.widgets)
		delete(g.ui.widgets)
		g.ui.widgets = nil
	}

	delete(g.ui.scope_stack)
	g.ui.scope_stack = nil
	g.ui.frame = 0
}

ui_begin_frame :: proc() {
	g.ui.frame += 1
}

ui_end_frame :: proc() {
	if g.ui.widgets == nil do return

	remove_ids := make([dynamic]UI_Id, context.temp_allocator)
	for id, entry in g.ui.widgets {
		if entry.last_frame != g.ui.frame {
			append(&remove_ids, id)
		}
	}

	for id in remove_ids {
		if entry, ok := &g.ui.widgets[id]; ok {
			shaped_text_release(&entry.shaped)
			delete_key(&g.ui.widgets, id)
		}
	}
}

ui_push_scope :: proc(id: UI_Id) {
	append(&g.ui.scope_stack, id)
}

ui_pop_scope :: proc() {
	if len(g.ui.scope_stack) > 0 {
		ordered_remove(&g.ui.scope_stack, len(g.ui.scope_stack) - 1)
	}
}

ui_parent_hash :: proc() -> u64 {
	h: u64 = 14695981039346656037
	for scope in g.ui.scope_stack {
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

ui_widget_shaped :: proc(id: UI_Id) -> ^Shaped_Text {
	entry: ^UI_Widget_Entry
	if e, ok := &g.ui.widgets[id]; ok {
		entry = e
	} else {
		g.ui.widgets[id] = {shaped = {pool_slot = INVALID_SHAPE_POOL_SLOT}}
		entry = &g.ui.widgets[id]
	}

	entry.last_frame = g.ui.frame
	return &entry.shaped
}
