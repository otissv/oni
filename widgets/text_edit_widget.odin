package oni_widgets

import o ".."

Text_Edit_Widget_Opts :: struct {
	selectable:      bool,
	editable:        bool,
	multiline:       bool,
	max_length:      int,
	draw_space:      o.Draw_Space,
	caret_color:     o.RGBA,
	has_caret_color: bool,
}

@(private)
text_edit_widget_edit_plain :: proc(
	geo: ^o.Text_Edit_Geometry,
	plain: string,
) -> string {
	if geo != nil && len(geo.plain) > 0 {
		return geo.plain
	}

	return plain
}

@(private)
text_edit_widget_insert_text :: proc(
	edit: ^o.Text_Edit_State,
	plain: string,
	insert: string,
	opts: Text_Edit_Widget_Opts,
) -> (
	new_plain: string,
	changed: bool,
) {
	new_plain = plain

	if len(insert) == 0 do return new_plain, false

	if !o.text_edit_within_max_length(plain, opts.max_length, insert) {
		return new_plain, false
	}

	o.text_edit_undo_push(&edit.undo, plain, edit.caret, edit.selection, o.state.ui.frame)
	start, end := o.text_edit_selection_normalized(edit.selection)
	new_plain, edit.caret = o.text_edit_plain_splice(plain, start, end, insert)
	edit.selection = {edit.caret, edit.caret}
	edit.has_preferred_column = false

	return new_plain, true
}

text_edit_widget_apply_layout_scroll_defaults :: proc(
	author: o.Widget_Config,
	multiline: bool,
	layout_config: ^o.Resolved_Widget_Config,
) {
	if layout_config == nil do return
	if author.overflow_x.mode != .UNSET || author.overflow_y.mode != .UNSET do return

	ov_auto: o.Overflow = .AUTO
	ov_hidden: o.Overflow = .HIDDEN

	if multiline && o.length_is_definite(layout_config.height) {
		layout_config.overflow_y = ov_auto
		layout_config.overflow_x = ov_hidden

		return
	}

	if !multiline {
		layout_config.overflow_x = ov_auto
		layout_config.overflow_y = ov_hidden
	}
}

@(private)
text_edit_widget_page_lines :: proc(layout_id: o.UI_Id, geo: ^o.Text_Edit_Geometry) -> int {
	metrics, ok := o.Scrollport_Metrics_Get(layout_id)
	if !ok do return 1

	return o.text_edit_page_line_count(geo, metrics.viewport_size.y)
}

@(private)
text_edit_widget_commit_scroll :: proc(
	key: string,
	layout_id: o.UI_Id,
	scroll: ^o.Vec2,
	before: o.Vec2,
) {
	if scroll == nil do return

	delta := o.Vec2{scroll.x - before.x, scroll.y - before.y}

	if delta.x == 0 && delta.y == 0 do return

	o.layout_apply_scroll_delta(layout_id, delta)
	o.widget_scroll_set(key, scroll^)
}

@(private)
text_edit_widget_sync_edit_scroll :: proc(
	key: string,
	layout_id: o.UI_Id,
	edit: ^o.Text_Edit_State,
	geo: ^o.Text_Edit_Geometry,
	scroll: ^o.Vec2,
	config: o.Resolved_Widget_Config,
) {
	if scroll == nil || edit == nil || geo == nil do return
	if !o.style_is_scrollport(config.overflow_x, config.overflow_y) do return

	metrics, ok := o.Scrollport_Metrics_Get(layout_id)
	if !ok do return

	before := scroll^
	o.text_edit_scroll_to_show_edit(
		scroll,
		geo,
		edit.caret,
		edit.selection,
		metrics.viewport_size,
		metrics.max_scroll,
		config.overflow_x,
		config.overflow_y,
	)
	text_edit_widget_commit_scroll(key, layout_id, scroll, before)
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
	scroll: ^o.Vec2,
	plain: string,
	can_interact: bool,
	config: o.Resolved_Widget_Config,
	opts: Text_Edit_Widget_Opts = {},
) {
	if !can_interact || !opts.selectable do return

	edit := o.widget_text_edit_ensure(key)
	if edit == nil do return

	geo := o.layout_text_edit_geometry(layout_id)
	edit_plain := text_edit_widget_edit_plain(geo, plain)
	local := text_edit_widget_local_point(layout_rect, scroll^)

	if o.w_ctx.left_mouse.pressed &&
	   o.pointer_hits(layout_id, layout_rect, opts.draw_space) {
		edit.drag_active = true

		if geo != nil {
			edit.caret, edit.selection = o.text_edit_register_click(
				edit,
				local,
				f64(o.state.ui.frame),
				geo,
				layout_rect,
				scroll^,
				edit_plain,
			)
			o.text_edit_set_preferred_column(edit, geo, edit.caret)
		} else {
			edit.caret = 0
			edit.selection = {}
		}

		text_edit_widget_sync_edit_scroll(key, layout_id, edit, geo, scroll, config)
	}

	if edit.drag_active && o.w_ctx.left_mouse.down && geo != nil {
		before := scroll^
		metrics, metrics_ok := o.Scrollport_Metrics_Get(layout_id)

		if metrics_ok &&
		   o.text_edit_drag_scroll_step(
			   layout_id,
			   scroll,
			   metrics.max_scroll,
			   config.overflow_x,
			   config.overflow_y,
		   ) {
			text_edit_widget_commit_scroll(key, layout_id, scroll, before)
			local = text_edit_widget_local_point(layout_rect, scroll^)
		}

		if o.w_ctx.mouse_moved || scroll^ != before {
			edit.caret, edit.selection = o.text_edit_pointer_selection(
				geo,
				layout_rect,
				scroll^,
				local,
				o.state.input.modifiers.shift,
				edit.caret,
				edit.selection,
			)
		}

		text_edit_widget_sync_edit_scroll(key, layout_id, edit, geo, scroll, config)
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

@(private)
text_edit_widget_sync_ime_caret :: proc(
	key: string,
	layout_id: o.UI_Id,
	layout_rect: o.Rect,
	scroll: o.Vec2,
	edit: ^o.Text_Edit_State,
	geo: ^o.Text_Edit_Geometry,
) {
	if !widget_is_focused(key) do return

	caret_rect := layout_rect

	if geo != nil {
		caret_geom := o.text_edit_caret_geometry(geo, layout_rect, scroll, edit.caret)
		caret_rect = {caret_geom.x, caret_geom.y, max(caret_geom.height * 0.05, 2), caret_geom.height}
	}

	o.input_sync_text_input_session(caret_rect, edit.caret)
}

text_edit_widget_consume_commands :: proc(
	key: string,
	layout_id: o.UI_Id,
	layout_rect: o.Rect,
	scroll: ^o.Vec2,
	plain: string,
	config: o.Resolved_Widget_Config,
	opts: Text_Edit_Widget_Opts = {},
) -> (
	new_plain: string,
	changed: bool,
) {
	new_plain = plain
	edit := o.widget_text_edit_get(key)
	if edit == nil || !widget_is_focused(key) do return new_plain, false

	geo := o.layout_text_edit_geometry(layout_id)
	cmd := o.text_edit_take_command(true)

	switch cmd {
	case .SELECT_ALL:
		edit.selection = o.text_edit_select_all(plain)
		edit.caret = edit.selection.head
		edit.has_preferred_column = false
	case .COPY:
		o.text_edit_copy_plain(plain, edit.selection)
	case .CUT:
		if o.text_edit_copy_plain(plain, edit.selection) {
			start, end := o.text_edit_selection_normalized(edit.selection)
			new_plain, edit.caret = o.text_edit_plain_splice(plain, start, end, "")
			edit.selection = {edit.caret, edit.caret}
			edit.has_preferred_column = false
			changed = true
		}
	case .PASTE:
		if paste, ok := o.clipboard_get_text(); ok {
			new_plain, changed = text_edit_widget_insert_text(edit, plain, paste, opts)
		}
	case .UNDO:
		if entry, ok := o.text_edit_undo_pop(&edit.undo); ok {
			new_plain = entry.text
			edit.caret = entry.caret
			edit.selection = entry.selection
			edit.has_preferred_column = false
			changed = true
		}
	case .NONE:
	}

	if cmd != .NONE && cmd != .COPY {
		text_edit_widget_sync_edit_scroll(key, layout_id, edit, geo, scroll, config)
	}

	text_edit_widget_sync_ime_caret(key, layout_id, layout_rect, scroll^, edit, geo)

	return new_plain, changed
}

text_edit_widget_handle_keys :: proc(
	key: string,
	layout_id: o.UI_Id,
	layout_rect: o.Rect,
	scroll: ^o.Vec2,
	plain: string,
	config: o.Resolved_Widget_Config,
	opts: Text_Edit_Widget_Opts,
) -> (
	new_plain: string,
	changed: bool,
) {
	new_plain = plain
	edit := o.widget_text_edit_get(key)
	if edit == nil || !opts.editable || !widget_is_focused(key) do return new_plain, false

	geo := o.layout_text_edit_geometry(layout_id)
	edit_plain := text_edit_widget_edit_plain(geo, plain)
	page_lines := text_edit_widget_page_lines(layout_id, geo)
	shift := o.state.input.modifiers.shift
	ctrl := o.state.input.modifiers.ctrl || o.state.input.modifiers.super

	for scancode in 0 ..< o.KEY_COUNT {
		if o.shortcut_key_consumed(o.Scancode(scancode)) do continue

		key_state := o.w_ctx.keys[scancode]
		if !key_state.pressed do continue

		nav_caret, nav_sel, handled := o.text_edit_handle_key_navigation(
			edit_plain,
			edit.caret,
			edit.selection,
			geo,
			o.Scancode(scancode),
			shift,
			ctrl,
			opts.multiline,
			page_lines,
			edit,
		)

		if handled {
			edit.caret = nav_caret
			edit.selection = nav_sel
			o.shortcut_consume_key(o.Scancode(scancode))
			text_edit_widget_sync_edit_scroll(key, layout_id, edit, geo, scroll, config)

			continue
		}

		#partial switch o.Scancode(scancode) {
		case .RETURN, .KP_ENTER:
			if opts.multiline {
				new_plain, changed = text_edit_widget_insert_text(edit, new_plain, "\n", opts)

				if changed {
					o.shortcut_consume_key(o.Scancode(scancode))
					text_edit_widget_sync_edit_scroll(key, layout_id, edit, geo, scroll, config)
				}
			} else {
				o.shortcut_consume_key(o.Scancode(scancode))
			}
		case .BACKSPACE:
			o.text_edit_undo_push(&edit.undo, new_plain, edit.caret, edit.selection, o.state.ui.frame)
			new_plain, edit.caret, edit.selection, changed = o.text_edit_backspace(
				new_plain,
				edit.caret,
				edit.selection,
			)

			if changed {
				edit.has_preferred_column = false
				o.shortcut_consume_key(o.Scancode(scancode))
				text_edit_widget_sync_edit_scroll(key, layout_id, edit, geo, scroll, config)
			}
		case .DELETE:
			o.text_edit_undo_push(&edit.undo, new_plain, edit.caret, edit.selection, o.state.ui.frame)
			new_plain, edit.caret, edit.selection, changed = o.text_edit_delete(
				new_plain,
				edit.caret,
				edit.selection,
			)

			if changed {
				edit.has_preferred_column = false
				o.shortcut_consume_key(o.Scancode(scancode))
				text_edit_widget_sync_edit_scroll(key, layout_id, edit, geo, scroll, config)
			}
		}
	}

	inserted := o.input_take_text_input()

	if len(inserted) > 0 {
		new_plain, changed = text_edit_widget_insert_text(edit, new_plain, inserted, opts)

		if changed {
			text_edit_widget_sync_edit_scroll(key, layout_id, edit, geo, scroll, config)
		}
	}

	edit.caret = o.text_edit_clamp_offset(new_plain, edit.caret)
	edit.selection = o.text_edit_clamp_selection(new_plain, edit.selection)
	text_edit_widget_sync_ime_caret(key, layout_id, layout_rect, scroll^, edit, geo)

	return new_plain, changed
}

text_edit_widget_handle_selectable :: proc(
	key: string,
	plain: string,
) {
	if !widget_is_focused(key) do return

	edit := o.widget_text_edit_get(key)
	if edit == nil do return

	cmd := o.text_edit_take_command(true)

	if cmd == .COPY {
		o.text_edit_copy_plain(plain, edit.selection)
	}
}

text_edit_widget_apply_document_plain :: proc(
	tagged: string,
	key: string,
	layout_id: o.UI_Id,
	layout_rect: o.Rect,
	scroll: ^o.Vec2,
	plain: string,
	config: o.Resolved_Widget_Config,
	opts: Text_Edit_Widget_Opts = {},
) -> (
	new_tagged: string,
	changed: bool,
) {
	new_tagged = tagged
	edit := o.widget_text_edit_get(key)
	if edit == nil || !widget_is_focused(key) do return new_tagged, false

	geo := o.layout_text_edit_geometry(layout_id)
	cmd := o.text_edit_take_command(true)

	switch cmd {
	case .SELECT_ALL:
		edit.selection = o.text_edit_select_all(plain)
		edit.caret = edit.selection.head
		edit.has_preferred_column = false
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
			edit.has_preferred_column = false
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
			edit.has_preferred_column = false
			changed = true
		}
	case .UNDO:
		if entry, ok := o.text_edit_undo_pop(&edit.undo); ok {
			new_tagged = entry.text
			edit.caret = entry.caret
			edit.selection = entry.selection
			edit.has_preferred_column = false
			changed = true
		}
	case .NONE:
	}

	if cmd != .NONE && cmd != .COPY {
		text_edit_widget_sync_edit_scroll(key, layout_id, edit, geo, scroll, config)
	}

	text_edit_widget_sync_ime_caret(key, layout_id, layout_rect, scroll^, edit, geo)

	return new_tagged, changed
}

text_edit_widget_apply_document_keys :: proc(
	tagged: string,
	key: string,
	layout_id: o.UI_Id,
	layout_rect: o.Rect,
	scroll: ^o.Vec2,
	plain: string,
	config: o.Resolved_Widget_Config,
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
	page_lines := text_edit_widget_page_lines(layout_id, geo)
	shift := o.state.input.modifiers.shift
	ctrl := o.state.input.modifiers.ctrl || o.state.input.modifiers.super

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
			shift,
			ctrl,
			opts.multiline,
			page_lines,
			edit,
		)

		if handled {
			edit.caret = nav_caret
			edit.selection = nav_sel
			o.shortcut_consume_key(o.Scancode(scancode))
			text_edit_widget_sync_edit_scroll(key, layout_id, edit, geo, scroll, config)

			continue
		}

		#partial switch o.Scancode(scancode) {
		case .RETURN, .KP_ENTER:
			if opts.multiline {
				inserted, inserted_changed := text_edit_widget_insert_text(edit, new_plain, "\n", opts)

				if inserted_changed {
					new_plain = inserted
					plain_changed = true
					o.shortcut_consume_key(o.Scancode(scancode))
					text_edit_widget_sync_edit_scroll(key, layout_id, edit, geo, scroll, config)
				}
			} else {
				o.shortcut_consume_key(o.Scancode(scancode))
			}
		case .BACKSPACE:
			o.text_edit_undo_push(&edit.undo, tagged, edit.caret, edit.selection, o.state.ui.frame)
			new_plain, edit.caret, edit.selection, plain_changed = o.text_edit_backspace(
				new_plain,
				edit.caret,
				edit.selection,
			)

			if plain_changed {
				edit.has_preferred_column = false
				o.shortcut_consume_key(o.Scancode(scancode))
				text_edit_widget_sync_edit_scroll(key, layout_id, edit, geo, scroll, config)
			}
		case .DELETE:
			o.text_edit_undo_push(&edit.undo, tagged, edit.caret, edit.selection, o.state.ui.frame)
			new_plain, edit.caret, edit.selection, plain_changed = o.text_edit_delete(
				new_plain,
				edit.caret,
				edit.selection,
			)

			if plain_changed {
				edit.has_preferred_column = false
				o.shortcut_consume_key(o.Scancode(scancode))
				text_edit_widget_sync_edit_scroll(key, layout_id, edit, geo, scroll, config)
			}
		}
	}

	inserted := o.input_take_text_input()

	if len(inserted) > 0 {
		new_plain, plain_changed = text_edit_widget_insert_text(edit, new_plain, inserted, opts)

		if plain_changed {
			text_edit_widget_sync_edit_scroll(key, layout_id, edit, geo, scroll, config)
		}
	}

	if plain_changed {
		doc := o.text_document_from_tagged(tagged)
		defer o.text_document_free_runs(&doc)

		if new_plain != doc.plain {
			if !o.text_document_splice_plain(&doc, 0, len(doc.plain), new_plain) {
				changed = false
			} else {
				new_tagged = o.text_document_to_tagged(&doc)
				changed = true
			}
		}
	}

	edit.caret = o.text_edit_clamp_offset(new_plain, edit.caret)
	edit.selection = o.text_edit_clamp_selection(new_plain, edit.selection)
	text_edit_widget_sync_ime_caret(key, layout_id, layout_rect, scroll^, edit, geo)

	return new_tagged, changed
}

text_edit_widget_after_wheel_scroll :: proc(
	key: string,
	layout_id: o.UI_Id,
	scroll: ^o.Vec2,
	before: o.Vec2,
) {
	if scroll == nil do return
	if scroll.x == before.x && scroll.y == before.y do return

	text_edit_widget_commit_scroll(key, layout_id, scroll, before)
}
