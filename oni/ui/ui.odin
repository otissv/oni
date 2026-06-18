package ui

import ngin "../engine"
import "core:hash"

ui_init :: proc() {
	if ngin.state.ui.widgets == nil {
		ngin.state.ui.widgets = make(map[ngin.UI_Id]ngin.UI_Widget_Entry)
	}
}

ui_shutdown :: proc() {
	if ngin.state.ui.widgets != nil {
		for _, &entry in ngin.state.ui.widgets {
			ngin.shaped_text_release(&entry.shaped)
		}
		clear(&ngin.state.ui.widgets)
		delete(ngin.state.ui.widgets)
		ngin.state.ui.widgets = nil
	}

	delete(ngin.state.ui.scope_stack)
	ngin.state.ui.scope_stack = nil
	ngin.state.ui.frame = 0
}

ui_begin_frame :: proc() {
	ngin.state.ui.frame += 1
}

ui_end_frame :: proc() {
	if ngin.state.ui.widgets == nil do return

	remove_ids := make([dynamic]ngin.UI_Id, context.temp_allocator)
	for id, entry in ngin.state.ui.widgets {
		if entry.last_frame != ngin.state.ui.frame {
			append(&remove_ids, id)
		}
	}

	for id in remove_ids {
		if entry, ok := &ngin.state.ui.widgets[id]; ok {
			ngin.shaped_text_release(&entry.shaped)
			delete_key(&ngin.state.ui.widgets, id)
		}
	}
}

ui_push_scope :: proc(id: ngin.UI_Id) {
	append(&ngin.state.ui.scope_stack, id)
}

ui_pop_scope :: proc() {
	if len(ngin.state.ui.scope_stack) > 0 {
		ordered_remove(&ngin.state.ui.scope_stack, len(ngin.state.ui.scope_stack) - 1)
	}
}

ui_parent_hash :: proc() -> u64 {
	h: u64 = 14695981039346656037
	for scope in ngin.state.ui.scope_stack {
		h ~= u64(scope)
		h *= 1099511628211
	}
	return h
}

ui_id :: proc(label: string) -> ngin.UI_Id {
	label_hash := u64(hash.crc32(transmute([]u8)label))
	parent := ui_parent_hash()
	return ngin.UI_Id(label_hash ~ parent)
}

ui_widget_shaped :: proc(id: ngin.UI_Id) -> ^ngin.Shaped_Text {
	entry: ^ngin.UI_Widget_Entry
	if e, ok := &ngin.state.ui.widgets[id]; ok {
		entry = e
	} else {
		ngin.state.ui.widgets[id] = {
			shaped = {pool_slot = ngin.INVALID_SHAPE_POOL_SLOT},
		}
		entry = &ngin.state.ui.widgets[id]
	}

	entry.last_frame = ngin.state.ui.frame
	return &entry.shaped
}
