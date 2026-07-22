package oni_widgets

import "core:strings"
import o ".."

Text_Edit_Widget_Opts :: struct {
	selectable:      bool,
	editable:        bool,
	caret_color:     o.RGBA,
	has_caret_color: bool,
}

text_edit_widget_local_point :: proc(layout_rect: o.Rect, scroll: o.Vec2) -> o.Vec2 {
	return {
		o.w_ctx.mouse_x - (layout_rect.x - scroll.x),
		o.w_ctx.mouse_y - (layout_rect.y - scroll.y),
	}
}

text_edit_widget_handle_pointer :: proc(
	key: string,
	layout_id: o.UI_Id,
	layout_rect: o.Rect,
	scroll: o.Vec2,
	plain: string,
	can_interact: bool,
) {
	if !can_interact do return

	edit := o.widget_text_edit_ensure(key)
	if edit == nil do return

	geo := o.layout_text_edit_geometry(layout_id)
	if geo == nil do return

	local := text_edit_widget_local_point(layout_rect, scroll)

	if o.w_ctx.left_mouse.pressed && o.pointer_hits(layout_id, layout_rect, .ARTBOARD) {
		edit.drag_active = true
		edit.caret, edit.selection = o.text_edit_register_click(
			edit,
			local,
			f64(o.state.ui.frame),
			geo,
			layout_rect,
			scroll,
			plain,
		)
	}

	if edit.drag_active && o.w_ctx.left_mouse.down && o.w_ctx.mouse_moved {
		edit.caret, edit.selection = o.text_edit_pointer_selection(
			geo,
			layout_rect,
			scroll,
			local,
			o.state.input.modifiers.shift,
			edit.caret,
			edit.selection,
		)
	}

	if o.w_ctx.left_mouse.released {
		edit.drag_active = false
	}
}

text_edit_widget_draw_overlay :: proc(
	opts: Text_Edit_Widget_Opts,
	key: string,
	layout_id: o.UI_Id,
	layout_rect: o.Rect,
	scroll: o.Vec2,
	focused: bool,
) {
	if !opts.selectable && !opts.editable do return

	edit := o.widget_text_edit_get(key)
	if edit == nil do return

	geo := o.layout_text_edit_geometry(layout_id)
	if geo == nil do return

	selection_color := o.RGBA{100, 150, 255, 90}
	caret_color := o.RGBA{255, 255, 255, 255}

	if opts.has_caret_color {
		caret_color = opts.caret_color
	}

	show_caret := opts.editable && focused
	caret_visible := o.text_edit_caret_visible(edit.blink_phase)

	if focused && opts.editable {
		edit.blink_phase = o.text_edit_update_blink(edit.blink_phase, f32(o.Frame_Time()), true)
	}

	o.text_edit_draw_overlay(
		geo,
		layout_rect,
		scroll,
		edit.selection,
		edit.caret,
		selection_color,
		caret_color,
		show_caret,
		caret_visible,
	)
}

text_edit_widget_consume_commands :: proc(
	key: string,
	plain: string,
) -> (
	new_plain: string,
	changed: bool,
) {
	new_plain = plain
	edit := o.widget_text_edit_get(key)
	if edit == nil do return new_plain, false

	cmd := o.text_edit_consume_command()

	switch cmd {
	case .SELECT_ALL:
		edit.selection = o.text_edit_select_all(plain)
		edit.caret = edit.selection.head
	case .COPY:
		o.text_edit_copy_plain(plain, edit.selection)
	case .CUT:
		if o.text_edit_copy_plain(plain, edit.selection) {
			start, end := o.text_edit_selection_normalized(edit.selection)
			new_plain, edit.caret = o.text_edit_plain_splice(plain, start, end, "")
			edit.selection = {edit.caret, edit.caret}
			changed = true
		}
	case .PASTE:
		if paste, ok := o.clipboard_get_text(); ok {
			o.text_edit_undo_push(&edit.undo, plain, edit.caret, edit.selection, o.state.ui.frame)
			start, end := o.text_edit_selection_normalized(edit.selection)
			new_plain, edit.caret = o.text_edit_plain_splice(plain, start, end, paste)
			edit.selection = {edit.caret, edit.caret}
			changed = true
		}
	case .UNDO:
		if entry, ok := o.text_edit_undo_pop(&edit.undo); ok {
			new_plain = entry.text
			edit.caret = entry.caret
			edit.selection = entry.selection
			changed = true
		}
	case .NONE:
	}

	return new_plain, changed
}

text_edit_widget_handle_keys :: proc(
	key: string,
	layout_id: o.UI_Id,
	layout_rect: o.Rect,
	scroll: o.Vec2,
	plain: string,
	opts: Text_Edit_Widget_Opts,
) -> (
	new_plain: string,
	changed: bool,
) {
	new_plain = plain
	edit := o.widget_text_edit_get(key)
	if edit == nil || !opts.editable || !widget_is_focused(key) do return new_plain, false

	geo := o.layout_text_edit_geometry(layout_id)

	for scancode in 0 ..< o.KEY_COUNT {
		if o.shortcut_key_consumed(o.Scancode(scancode)) do continue

		key_state := o.w_ctx.keys[scancode]
		if !key_state.pressed do continue

		nav_caret, nav_sel, handled := o.text_edit_handle_key_navigation(
			new_plain,
			edit.caret,
			edit.selection,
			geo,
			o.Scancode(scancode),
			o.state.input.modifiers.shift,
		)

		if handled {
			edit.caret = nav_caret
			edit.selection = nav_sel
			o.shortcut_consume_key(o.Scancode(scancode))

			continue
		}

		#partial switch o.Scancode(scancode) {
		case .BACKSPACE:
			o.text_edit_undo_push(&edit.undo, new_plain, edit.caret, edit.selection, o.state.ui.frame)
			new_plain, edit.caret, edit.selection, changed = o.text_edit_backspace(
				new_plain,
				edit.caret,
				edit.selection,
			)
			if changed {
				o.shortcut_consume_key(o.Scancode(scancode))
			}
		case .DELETE:
			o.text_edit_undo_push(&edit.undo, new_plain, edit.caret, edit.selection, o.state.ui.frame)
			new_plain, edit.caret, edit.selection, changed = o.text_edit_delete(
				new_plain,
				edit.caret,
				edit.selection,
			)
			if changed {
				o.shortcut_consume_key(o.Scancode(scancode))
			}
		}
	}

	inserted := o.input_take_text_input()

	if len(inserted) > 0 {
		o.text_edit_undo_push(&edit.undo, new_plain, edit.caret, edit.selection, o.state.ui.frame)
		start, end := o.text_edit_selection_normalized(edit.selection)
		new_plain, edit.caret = o.text_edit_plain_splice(new_plain, start, end, inserted)
		edit.selection = {edit.caret, edit.caret}
		changed = true
	}

	if widget_is_focused(key) {
		caret_rect := layout_rect
		if geo != nil {
			caret_geom := o.text_edit_caret_geometry(geo, layout_rect, scroll, edit.caret)
			caret_rect = {caret_geom.x, caret_geom.y, max(caret_geom.height * 0.05, 2), caret_geom.height}
		}
		o.input_sync_text_input_session(caret_rect, edit.caret)
	}

	return new_plain, changed
}

text_edit_widget_handle_selectable :: proc(
	key: string,
	plain: string,
) {
	edit := o.widget_text_edit_get(key)
	if edit == nil do return

	cmd := o.text_edit_consume_command()

	if cmd == .COPY {
		o.text_edit_copy_plain(plain, edit.selection)
	}
}

text_edit_widget_apply_document_plain :: proc(
	tagged: string,
	key: string,
	plain: string,
) -> (
	new_tagged: string,
	changed: bool,
) {
	new_tagged = tagged
	edit := o.widget_text_edit_get(key)
	if edit == nil do return new_tagged, false

	cmd := o.text_edit_consume_command()

	switch cmd {
	case .SELECT_ALL:
		edit.selection = o.text_edit_select_all(plain)
		edit.caret = edit.selection.head
	case .COPY:
		o.text_edit_copy_plain(plain, edit.selection)
	case .CUT:
		if o.text_edit_copy_plain(plain, edit.selection) {
			doc := o.text_document_from_tagged(tagged)
			defer o.text_document_free_runs(&doc)
			start, end := o.text_edit_selection_normalized(edit.selection)
			o.text_document_delete_range(&doc, start, end)
			new_tagged = o.text_document_to_tagged(&doc)
			edit.caret = start
			edit.selection = {start, start}
			changed = true
		}
	case .PASTE:
		if paste, ok := o.clipboard_get_text(); ok {
			doc := o.text_document_from_tagged(tagged)
			defer o.text_document_free_runs(&doc)
			o.text_edit_undo_push(&edit.undo, tagged, edit.caret, edit.selection, o.state.ui.frame)
			start, end := o.text_edit_selection_normalized(edit.selection)
			o.text_document_delete_range(&doc, start, end)
			o.text_document_insert_plain(&doc, start, paste)
			new_tagged = o.text_document_to_tagged(&doc)
			edit.caret = start + len(paste)
			edit.selection = {edit.caret, edit.caret}
			changed = true
		}
	case .UNDO:
		if entry, ok := o.text_edit_undo_pop(&edit.undo); ok {
			new_tagged = entry.text
			edit.caret = entry.caret
			edit.selection = entry.selection
			changed = true
		}
	case .NONE:
	}

	return new_tagged, changed
}

text_edit_widget_apply_document_keys :: proc(
	tagged: string,
	key: string,
	layout_id: o.UI_Id,
	layout_rect: o.Rect,
	scroll: o.Vec2,
	plain: string,
	opts: Text_Edit_Widget_Opts,
) -> (
	new_tagged: string,
	changed: bool,
) {
	new_tagged = tagged
	edit := o.widget_text_edit_get(key)
	if edit == nil || !opts.editable || !widget_is_focused(key) do return new_tagged, false

	geo := o.layout_text_edit_geometry(layout_id)
	new_plain := plain
	plain_changed := false

	for scancode in 0 ..< o.KEY_COUNT {
		if o.shortcut_key_consumed(o.Scancode(scancode)) do continue

		key_state := o.w_ctx.keys[scancode]
		if !key_state.pressed do continue

		nav_caret, nav_sel, handled := o.text_edit_handle_key_navigation(
			new_plain,
			edit.caret,
			edit.selection,
			geo,
			o.Scancode(scancode),
			o.state.input.modifiers.shift,
		)

		if handled {
			edit.caret = nav_caret
			edit.selection = nav_sel
			o.shortcut_consume_key(o.Scancode(scancode))

			continue
		}

		#partial switch o.Scancode(scancode) {
		case .BACKSPACE:
			o.text_edit_undo_push(&edit.undo, tagged, edit.caret, edit.selection, o.state.ui.frame)
			new_plain, edit.caret, edit.selection, plain_changed = o.text_edit_backspace(
				new_plain,
				edit.caret,
				edit.selection,
			)
			if plain_changed {
				o.shortcut_consume_key(o.Scancode(scancode))
			}
		case .DELETE:
			o.text_edit_undo_push(&edit.undo, tagged, edit.caret, edit.selection, o.state.ui.frame)
			new_plain, edit.caret, edit.selection, plain_changed = o.text_edit_delete(
				new_plain,
				edit.caret,
				edit.selection,
			)
			if plain_changed {
				o.shortcut_consume_key(o.Scancode(scancode))
			}
		}
	}

	inserted := o.input_take_text_input()

	if len(inserted) > 0 {
		o.text_edit_undo_push(&edit.undo, tagged, edit.caret, edit.selection, o.state.ui.frame)
		start, end := o.text_edit_selection_normalized(edit.selection)
		doc := o.text_document_from_tagged(tagged)
		defer o.text_document_free_runs(&doc)
		o.text_document_delete_range(&doc, start, end)
		o.text_document_insert_plain(&doc, start, inserted)
		new_tagged = o.text_document_to_tagged(&doc)
		edit.caret = start + len(inserted)
		edit.selection = {edit.caret, edit.caret}
		changed = true
	} else if plain_changed {
		doc := o.text_document_from_tagged(tagged)
		defer o.text_document_free_runs(&doc)
		doc.plain = strings.clone(new_plain)
		delete(doc.runs)
		delete(doc.layout_runs)
		doc.runs = make([]o.Text_Run, 1)
		doc.runs[0] = o.Text_Run{text = strings.clone(new_plain)}
		o.text_document_rebuild(&doc)
		new_tagged = o.text_document_to_tagged(&doc)
		changed = true
	}

	if widget_is_focused(key) {
		caret_rect := layout_rect
		if geo != nil {
			caret_geom := o.text_edit_caret_geometry(geo, layout_rect, scroll, edit.caret)
			caret_rect = {caret_geom.x, caret_geom.y, max(caret_geom.height * 0.05, 2), caret_geom.height}
		}
		o.input_sync_text_input_session(caret_rect, edit.caret)
	}

	return new_tagged, changed
}
