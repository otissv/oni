package oni

// Focus scopes are retained in Widget_Context so saved focus survives reloads.
// Their tab ranges are rebuilt during Layout and enforced before Draw.
widget_focus_scopes_begin_frame :: proc() {
	w_ctx.focus_scopes_ready = false
	w_ctx.focus_scope_excluded = 0
	w_ctx.focus_scope_parent = -1
	w_ctx.focus_scope_order = 0
	for &scope in w_ctx.focus_scopes {
		scope.seen = false
	}
}

// Begins a modal content scope during Layout. key is also the empty-scope fallback.
widget_focus_scope_begin :: proc(key: Widget_ID) -> int {
	assert(ui_pass() == .Layout)
	assert(key != "")
	index := -1
	for scope, i in w_ctx.focus_scopes {
		if scope.key == key {
			index = i
			break
		}
	}
	if index < 0 {
		index = len(w_ctx.focus_scopes)
		return_scope := index == 0 ? -1 : w_ctx.focus_scope_active
		append(&w_ctx.focus_scopes, Widget_Focus_Scope {
			key = widget_retain_key(key),
			return_focus = widget_retain_key(w_ctx.focused_id),
			return_scope = return_scope,
		})
	}
	scope := &w_ctx.focus_scopes[index]
	assert(!scope.seen)
	assert(w_ctx.focus_scope_parent != index)
	scope.parent = w_ctx.focus_scope_parent
	scope.order = w_ctx.focus_scope_order
	w_ctx.focus_scope_order += 1
	scope.start = len(w_ctx.tab_order)
	scope.end = scope.start
	scope.seen = true
	w_ctx.focus_scope_parent = index
	return index
}

widget_focus_scope_end :: proc(index: int) {
	assert(w_ctx.focus_scope_parent == index)
	w_ctx.focus_scopes[index].end = len(w_ctx.tab_order)
	w_ctx.focus_scope_parent = w_ctx.focus_scopes[index].parent
}

widget_focus_scope_allows :: proc(id: Widget_ID) -> bool {
	id := id
	if !w_ctx.focus_scopes_ready || len(w_ctx.focus_scopes) == 0 do return true
	if anchor, valid := widget_menubar_focus_anchor(id); valid {
		id = anchor
	}
	scope := w_ctx.focus_scopes[w_ctx.focus_scope_active]
	if scope.start == scope.end do return id == scope.key
	for target in w_ctx.tab_order[scope.start:scope.end] {
		if target == id do return true
	}
	return false
}

widget_focus_scopes_resolve :: proc() {
	// Restore through the saved modal chain before removing closed scopes.
	if len(w_ctx.focus_scopes) > 0 {
		index := w_ctx.focus_scope_active
		for index >= 0 && index < len(w_ctx.focus_scopes) {
			scope := w_ctx.focus_scopes[index]
			if scope.seen do break

			widget_change_navigation_focus(scope.return_focus)
			index = scope.return_scope
		}
	}
	// Keep indices stable until restoration is complete; parents are rebuilt next Layout.
	for i := len(w_ctx.focus_scopes) - 1; i >= 0; i -= 1 {
		if w_ctx.focus_scopes[i].seen do continue
		closing := w_ctx.focus_scopes[i]
		// A surviving modal must not retain a return target in a closed modal.
		for &scope in w_ctx.focus_scopes {
			if scope.return_scope == i {
				widget_release_key(scope.return_focus)
				scope.return_focus = widget_retain_key(closing.return_focus)
				scope.return_scope = closing.return_scope
			}
		}
		widget_release_key(w_ctx.focus_scopes[i].key)
		widget_release_key(w_ctx.focus_scopes[i].return_focus)
		for j := i; j + 1 < len(w_ctx.focus_scopes); j += 1 {
			w_ctx.focus_scopes[j] = w_ctx.focus_scopes[j + 1]
		}
		resize(&w_ctx.focus_scopes, len(w_ctx.focus_scopes) - 1)
		for &scope in w_ctx.focus_scopes {
			if scope.parent > i do scope.parent -= 1
			if scope.return_scope > i do scope.return_scope -= 1
		}
	}
	w_ctx.focus_scope_active = 0
	for scope, i in w_ctx.focus_scopes {
		active := w_ctx.focus_scopes[w_ctx.focus_scope_active]
		if scope.order > active.order {
			w_ctx.focus_scope_active = i
		}
	}
	w_ctx.focus_scopes_ready = true
	if !widget_focus_scope_allows(w_ctx.focused_id) {
		scope := w_ctx.focus_scopes[w_ctx.focus_scope_active]
		target := scope.start == scope.end ? scope.key : w_ctx.tab_order[scope.start]
		widget_change_navigation_focus(target)
	}
}

widget_focus_scopes_shutdown :: proc() {
	for scope in w_ctx.focus_scopes {
		widget_release_key(scope.key)
		widget_release_key(scope.return_focus)
	}
	delete(w_ctx.focus_scopes)
	w_ctx.focus_scopes = nil
}
