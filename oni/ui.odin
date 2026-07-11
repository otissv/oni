package oni

import "core:hash"


UI_Pass :: enum {
	Layout,
	Draw,
}

/*
Allocates UI widget and layout maps on first use.

Safe to call repeatedly; only creates storage when nil.
*/
ui_init :: proc() {
	if state.ui.widgets == nil {
		state.ui.widgets = make(map[UI_Id]UI_Widget_Entry)
	}

	if state.ui.layout.id_to_node == nil {
		state.ui.layout.id_to_node = make(map[UI_Id]int)
	}

	if state.ui.layout.table_tracks == nil {
		state.ui.layout.table_tracks = make(map[int]Layout_Table_Tracks)
	}

	if state.ui.layout_ids_prev == nil {
		state.ui.layout_ids_prev = make(map[UI_Id]bool)
	}

	if state.ui.layout_ids_snapshot == nil {
		state.ui.layout_ids_snapshot = make(map[UI_Id]bool)
	}
}

/*
Tears down widget storage, scope/style stacks, and layout state.
*/
ui_shutdown :: proc() {
	if state.ui.widgets != nil {
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
	delete(state.ui.layout.table_tracks)
	state.ui.layout.table_tracks = nil
	layout_shutdown()
	delete(state.ui.layout_ids_prev)
	state.ui.layout_ids_prev = nil
	delete(state.ui.layout_ids_snapshot)
	state.ui.layout_ids_snapshot = nil
	widget_ctx_shutdown()

	state.ui.frame = 0
	state.ui.pass = .Layout
}

/*
Starts a new UI frame and resets transient per-frame state.

Clears scope/style stacks, layout tree, widget input, and auto ids.
*/
ui_begin_frame :: proc() {
	ui_init()
	state.ui.frame += 1
	state.ui.pass = .Layout
	clear(&state.ui.layout_ids_prev)
	for id in state.ui.layout_ids_snapshot {
		state.ui.layout_ids_prev[id] = true
	}
	clear(&state.ui.scope_stack)
	clear(&state.ui.style_stack)
	layout_reset()

	w_ctx.auto_element_index = 0

	if w_ctx.tab_order != nil {
		clear(&w_ctx.tab_order)
	}

	if w_ctx.static_ids != nil {
		clear(&w_ctx.static_ids)
	}

	w_ctx.mouse_moved = false
	w_ctx.tab_focus_changed = false
	w_ctx.tab_focus_previous_id = {}

	clear_button_transients(&w_ctx.left_mouse)
	clear_button_transients(&w_ctx.right_mouse)
	clear_button_transients(&w_ctx.middle_mouse)

	for &key in w_ctx.keys {
		clear_key_transients(&key)
	}

	sync_widget_input()
}

/*
Switches the UI pass from layout to draw after measurement completes.
*/
ui_end_layout_pass :: proc() {
	clear(&state.ui.layout_ids_snapshot)
	for id in state.ui.layout.id_to_node {
		state.ui.layout_ids_snapshot[id] = true
	}

	widget_prune_focus()
	widget_process_tab_navigation()

	w_ctx.auto_element_index = 0
	if w_ctx.static_ids != nil {
		clear(&w_ctx.static_ids)
	}

	state.ui.pass = .Draw
}

/*
Prunes widgets not touched this frame.

Call once per frame after the draw pass finishes.
*/
ui_end_frame :: proc() {
	if state.ui.widgets == nil do return

	remove_ids := make([dynamic]UI_Id, context.temp_allocator)
	for id, entry in state.ui.widgets {
		if entry.last_frame != state.ui.frame {
			append(&remove_ids, id)
		}
	}

	for id in remove_ids {
		delete_key(&state.ui.widgets, id)
	}

	widget_prune_element_maps()
}

/*
Runs each UI builder through layout and draw passes, then ends the frame.

Each proc is invoked twice: once to measure, once to render.
*/
render :: proc(ui: ..proc()) {
	for u in ui {
		u()
		ui_end_layout_pass()

		u()
		ui_end_frame()
	}
}

/*
Returns whether the UI is in the layout or draw pass.
*/
ui_pass :: proc() -> UI_Pass {
	return state.ui.pass
}

/*
Returns the solved layout rectangle for a UI id.

Returns an empty rect when the id has no layout node.
*/
ui_layout_rect :: proc(id: UI_Id) -> Rect {
	if node_index, ok := state.ui.layout.id_to_node[id]; ok {
		return state.ui.layout.nodes[node_index].rect
	}
	return {}
}

/*
Returns whether a UI id was registered in the layout tree during the previous frame.
*/
ui_was_laid_out_prev :: proc(id: UI_Id) -> bool {
	return state.ui.layout_ids_prev[id]
}

/*
Returns whether a UI id is registered in the current frame layout tree.
*/
ui_has_layout_node :: proc(id: UI_Id) -> bool {
	_, ok := state.ui.layout.id_to_node[id]
	return ok
}

/*
Pushes an id onto the scope stack for hierarchical id generation.
*/
ui_push_scope :: proc(id: UI_Id) {
	append(&state.ui.scope_stack, id)
}

/*
Pops the most recent scope id from the stack.
*/
ui_pop_scope :: proc() {
	if len(state.ui.scope_stack) > 0 {
		ordered_remove(&state.ui.scope_stack, len(state.ui.scope_stack) - 1)
	}
}

/*
Hashes the current scope stack into a parent prefix for UI ids.

Uses FNV-1a over each scope id in stack order.
*/
ui_parent_hash :: proc() -> u64 {
	h: u64 = 14695981039346656037
	for scope in state.ui.scope_stack {
		h ~= u64(scope)
		h *= 1099511628211
	}
	return h
}

/*
Derives a stable UI id from a label and the current parent scope.

Combines a CRC32 of the label with the parent scope hash.
*/
ui_id :: proc(label: string) -> UI_Id {
	label_hash := u64(hash.crc32(transmute([]u8)label))
	parent := ui_parent_hash()
	return UI_Id(label_hash ~ parent)
}
