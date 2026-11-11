package oni

// Entries borrow frame-arena strings and live only between Layout and Draw.
Menubar_Entry :: struct {
	id: UI_Id,
	key, value, text: string,
	panel_key: string,
	group, submenu: UI_Id,
	disabled: bool,
}

// Only ids and the bounded typeahead buffer survive a frame or DLL reload.
Menubar_Runtime :: struct {
	frame: u64,
	open_id: UI_Id,
	path: [32]UI_Id,
	depth: int,
	pending_group: UI_Id,
	pending_last: bool,
	entries: [dynamic]Menubar_Entry,
	prefix: [128]u8,
	prefix_len: int,
	prefix_tick: i64,
}

widget_menubar_begin_frame :: proc() {
	if w_ctx == nil do return
	for id, runtime in w_ctx.menubars {
		if runtime.frame + 1 < state.ui.frame {
			delete_key(&w_ctx.menubars, id)
		}
	}
}

widget_menubar_focus_anchor :: proc(key: string) -> (anchor: string, valid: bool) {
	for root, runtime in w_ctx.menubars {
		if runtime.frame != state.ui.frame do continue
		found := false
		for entry in runtime.entries {
			if entry.key == key && !entry.disabled do found = true
		}
		if !found do continue
		for entry in runtime.entries {
			if entry.group != root || entry.disabled do continue
			for tab_key in w_ctx.tab_order {
				if tab_key == entry.key do return entry.key, true
			}
		}
	}

	return "", false
}
