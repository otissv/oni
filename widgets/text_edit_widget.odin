package oni_widgets

import o ".."

Text_Edit_Widget_Opts :: struct {
	selectable:          bool,
	editable:            bool,
	caret:               bool,
	multiline:           bool,
	password:            bool,
	max_length:          int,
	draw_space:          o.Draw_Space,
	caret_color:         o.RGBA,
	has_caret_color:     bool,
	selection_color:     o.RGBA,
	has_selection_color: bool,
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

	truncated := o.text_edit_truncate_insert_for_max_length(
		plain,
		edit.selection,
		insert,
		opts.max_length,
	)

	if len(truncated) == 0 do return new_plain, false

	o.text_edit_record_mutation(edit, plain, o.state.ui.frame)
	start, end := o.text_edit_selection_normalized(edit.selection)
	new_plain, edit.caret = o.text_edit_plain_splice(plain, start, end, truncated)
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
	layout_rect: o.Rect,
	edit: ^o.Text_Edit_State,
	geo: ^o.Text_Edit_Geometry,
	scroll: ^o.Vec2,
	config: o.Resolved_Widget_Config,
	opts: Text_Edit_Widget_Opts = {},
	plain: string = "",
) {
	if scroll == nil || edit == nil || geo == nil do return
	if !o.style_is_scrollport(config.overflow_x, config.overflow_y) do return

	metrics, ok := o.Scrollport_Metrics_Get(layout_id)
	if !ok do return

	before := scroll^
	geo_caret := text_edit_widget_map_value_offset_to_geo(opts, plain, edit.caret, edit.caret)
	geo_sel := text_edit_widget_map_value_selection_to_geo(opts, plain, edit.selection, edit.caret)
	o.text_edit_scroll_to_show_edit(
		scroll,
		geo,
		layout_rect,
		geo_caret,
		geo_sel,
		metrics.viewport_size,
		metrics.max_scroll,
		config.overflow_x,
		config.overflow_y,
	)
	text_edit_widget_commit_scroll(key, layout_id, scroll, before)
}

text_edit_widget_abs_point :: proc() -> o.Vec2 {
	return {o.w_ctx.mouse_x, o.w_ctx.mouse_y}
}

@(private)
text_edit_widget_ime_text :: proc() -> string {
	if o.state == nil do return {}

	return o.state.input.ime_text
}

@(private)
text_edit_widget_display_insert_at :: proc(
	opts: Text_Edit_Widget_Opts,
	value: string,
	ime_at: int,
) -> int {
	if opts.password {
		return o.text_edit_password_value_to_mask_offset(value, ime_at)
	}

	return ime_at
}

@(private)
text_edit_widget_map_geo_offset_to_value :: proc(
	opts: Text_Edit_Widget_Opts,
	value: string,
	geo_offset: int,
	ime_at: int,
) -> int {
	offset := geo_offset
	ime := text_edit_widget_ime_text()
	insert_at := text_edit_widget_display_insert_at(opts, value, ime_at)

	if len(ime) > 0 {
		offset = o.text_edit_ime_display_to_value_offset(insert_at, len(ime), offset)
	}

	if opts.password {
		return o.text_edit_password_mask_to_value_offset(value, offset)
	}

	return offset
}

@(private)
text_edit_widget_map_value_offset_to_geo :: proc(
	opts: Text_Edit_Widget_Opts,
	value: string,
	value_offset: int,
	ime_at: int,
) -> int {
	offset := value_offset
	insert_at := ime_at

	if opts.password {
		offset = o.text_edit_password_value_to_mask_offset(value, value_offset)
		insert_at = o.text_edit_password_value_to_mask_offset(value, ime_at)
	}

	ime := text_edit_widget_ime_text()

	if len(ime) > 0 {
		return o.text_edit_ime_value_to_display_offset(insert_at, len(ime), offset)
	}

	return offset
}

@(private)
text_edit_widget_map_geo_selection_to_value :: proc(
	opts: Text_Edit_Widget_Opts,
	value: string,
	sel: o.Text_Selection,
	ime_at: int,
) -> o.Text_Selection {
	mapped := sel
	ime := text_edit_widget_ime_text()
	insert_at := text_edit_widget_display_insert_at(opts, value, ime_at)

	if len(ime) > 0 {
		mapped = o.text_edit_ime_display_selection_to_value(insert_at, len(ime), mapped)
	}

	if opts.password {
		return o.text_edit_password_value_selection(value, mapped)
	}

	return mapped
}

@(private)
text_edit_widget_map_value_selection_to_geo :: proc(
	opts: Text_Edit_Widget_Opts,
	value: string,
	sel: o.Text_Selection,
	ime_at: int,
) -> o.Text_Selection {
	mapped := sel
	insert_at := ime_at

	if opts.password {
		mapped = o.text_edit_password_mask_selection(value, sel)
		insert_at = o.text_edit_password_value_to_mask_offset(value, ime_at)
	}

	ime := text_edit_widget_ime_text()

	if len(ime) > 0 {
		return o.text_edit_ime_value_selection_to_display(insert_at, len(ime), mapped)
	}

	return mapped
}

@(private)
text_edit_widget_display_caret_offset :: proc(
	opts: Text_Edit_Widget_Opts,
	value: string,
	ime_at: int,
) -> int {
	insert_at := text_edit_widget_display_insert_at(opts, value, ime_at)
	ime := text_edit_widget_ime_text()

	if len(ime) == 0 do return insert_at

	cursor := 0

	if o.state != nil {
		cursor = o.state.input.ime_cursor
	}

	return o.text_edit_ime_display_caret(insert_at, ime, cursor)
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
	abs_point := text_edit_widget_abs_point()

	if o.w_ctx.left_mouse.pressed &&
	   o.pointer_hits(layout_id, layout_rect, opts.draw_space) {
		edit.drag_active = true
		shift := o.state.input.modifiers.shift

		if geo != nil {
			geo_caret, geo_sel := o.text_edit_register_click(
				edit,
				abs_point,
				f64(o.state.ui.frame),
				geo,
				layout_rect,
				edit_plain,
				shift,
			)
			edit.caret = text_edit_widget_map_geo_offset_to_value(opts, plain, geo_caret, edit.caret)
			edit.selection = text_edit_widget_map_geo_selection_to_value(opts, plain, geo_sel, edit.caret)
			o.text_edit_set_preferred_column(
				edit,
				geo,
				text_edit_widget_map_value_offset_to_geo(opts, plain, edit.caret, edit.caret),
			)
		} else {
			edit.caret = 0
			edit.selection = {}
			o.text_edit_reset_blink(edit)
		}

		if o.input_ime_active() {
			o.input_clear_ime()
		}

		text_edit_widget_sync_edit_scroll(key, layout_id, layout_rect, edit, geo, scroll, config, opts, plain)
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
			abs_point = text_edit_widget_abs_point()
		}

		if o.w_ctx.mouse_moved || scroll^ != before {
			geo_caret := text_edit_widget_map_value_offset_to_geo(opts, plain, edit.caret, edit.caret)
			geo_sel := text_edit_widget_map_value_selection_to_geo(opts, plain, edit.selection, edit.caret)
			new_geo_caret, new_geo_sel := o.text_edit_pointer_selection(
				geo,
				layout_rect,
				abs_point,
				geo_caret,
				geo_sel,
			)
			edit.caret = text_edit_widget_map_geo_offset_to_value(opts, plain, new_geo_caret, edit.caret)
			edit.selection = text_edit_widget_map_geo_selection_to_value(opts, plain, new_geo_sel, edit.caret)
		}

		text_edit_widget_sync_edit_scroll(key, layout_id, layout_rect, edit, geo, scroll, config, opts, plain)
	}

	if o.w_ctx.left_mouse.released {
		edit.drag_active = false
	}
}

@(private)
text_edit_widget_resolve_overlay_colors :: proc(
	opts: Text_Edit_Widget_Opts,
) -> (
	selection_color: o.RGBA,
	caret_color: o.RGBA,
) {
	selection_color = o.css_color_to_rgba(o.Color.SELECTION)
	caret_color = o.css_color_to_rgba(o.Color.FOREGROUND)

	if opts.has_selection_color {
		selection_color = opts.selection_color
	}

	if opts.has_caret_color {
		caret_color = opts.caret_color
	}

	return
}

text_edit_widget_draw_selection :: proc(
	opts: Text_Edit_Widget_Opts,
	key: string,
	layout_id: o.UI_Id,
	layout_rect: o.Rect,
	plain: string,
) {
	if !opts.selectable && !opts.editable do return

	edit := o.widget_text_edit_get(key)
	if edit == nil do return

	geo := o.layout_text_edit_geometry(layout_id)
	if geo == nil do return

	selection_color, _ := text_edit_widget_resolve_overlay_colors(opts)
	geo_sel := text_edit_widget_map_value_selection_to_geo(opts, plain, edit.selection, edit.caret)

	o.Draw_Push_Space(opts.draw_space)
	defer o.Draw_Pop_Space()

	o.text_edit_draw_selection(geo, layout_rect, geo_sel, selection_color)
}

text_edit_widget_draw_caret :: proc(
	opts: Text_Edit_Widget_Opts,
	key: string,
	layout_id: o.UI_Id,
	layout_rect: o.Rect,
	plain: string,
	focused: bool,
) {
	if !opts.selectable && !opts.editable do return

	edit := o.widget_text_edit_get(key)
	if edit == nil do return

	geo := o.layout_text_edit_geometry(layout_id)
	if geo == nil do return

	_, caret_color := text_edit_widget_resolve_overlay_colors(opts)
	show_caret := opts.caret && focused
	caret_visible := o.text_edit_caret_visible(edit.blink_phase)

	if focused && opts.caret {
		edit.blink_phase = o.text_edit_update_blink(edit.blink_phase, f32(o.Frame_Time()), true)
	}

	geo_caret := text_edit_widget_display_caret_offset(opts, plain, edit.caret)

	o.Draw_Push_Space(opts.draw_space)
	defer o.Draw_Pop_Space()

	o.text_edit_draw_caret(
		geo,
		layout_rect,
		geo_caret,
		caret_color,
		show_caret,
		caret_visible,
	)
}

text_edit_widget_draw_composition :: proc(
	opts: Text_Edit_Widget_Opts,
	key: string,
	layout_id: o.UI_Id,
	layout_rect: o.Rect,
	plain: string,
	focused: bool,
) {
	if !focused || !opts.editable do return

	ime := text_edit_widget_ime_text()
	if len(ime) == 0 do return

	edit := o.widget_text_edit_get(key)
	if edit == nil do return

	geo := o.layout_text_edit_geometry(layout_id)
	if geo == nil do return

	_, caret_color := text_edit_widget_resolve_overlay_colors(opts)
	insert_at := text_edit_widget_display_insert_at(opts, plain, edit.caret)
	cursor := 0
	length := 0

	if o.state != nil {
		cursor = o.state.input.ime_cursor
		length = o.state.input.ime_length
	}

	start, end := o.text_edit_ime_underline_range(insert_at, ime, cursor, length)

	o.Draw_Push_Space(opts.draw_space)
	defer o.Draw_Pop_Space()

	o.text_edit_draw_composition_underline(geo, layout_rect, start, end, caret_color)
}

text_edit_widget_draw_overlay :: proc(
	opts: Text_Edit_Widget_Opts,
	key: string,
	layout_id: o.UI_Id,
	layout_rect: o.Rect,
	plain: string,
	focused: bool,
) {
	text_edit_widget_draw_selection(opts, key, layout_id, layout_rect, plain)
	text_edit_widget_draw_composition(opts, key, layout_id, layout_rect, plain, focused)
	text_edit_widget_draw_caret(opts, key, layout_id, layout_rect, plain, focused)
}

/*
Clears IME and stops the SDL text-input session when a field blurs.
*/
text_edit_widget_blur_ime :: proc(was_focused: bool, focused: bool) {
	if !was_focused || focused do return

	o.input_clear_ime()
	o.input_sync_text_input_session({}, 0)
}

@(private)
text_edit_widget_sync_ime_caret :: proc(
	key: string,
	layout_id: o.UI_Id,
	layout_rect: o.Rect,
	edit: ^o.Text_Edit_State,
	geo: ^o.Text_Edit_Geometry,
	opts: Text_Edit_Widget_Opts = {},
	plain: string = "",
) {
	if !widget_is_focused(key) do return

	caret_rect := layout_rect

	if geo != nil {
		geo_caret := text_edit_widget_display_caret_offset(opts, plain, edit.caret)
		caret_geom := o.text_edit_caret_geometry(geo, layout_rect, geo_caret)
		caret_rect = {
			caret_geom.x,
			caret_geom.y,
			o.text_edit_caret_width_px(),
			caret_geom.height,
		}
	}

	o.input_sync_text_input_session(caret_rect, 0)
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
	if !opts.selectable && !opts.editable do return new_plain, false

	geo := o.layout_text_edit_geometry(layout_id)
	cmd := o.text_edit_take_command(true)

	switch cmd {
	case .SELECT_ALL:
		edit.selection = o.text_edit_select_all(plain)
		edit.caret = edit.selection.head
		edit.has_preferred_column = false
		o.text_edit_reset_blink(edit)
	case .COPY:
		o.text_edit_copy_plain(plain, edit.selection)
	case .CUT:
		if opts.editable && o.text_edit_copy_plain(plain, edit.selection) {
			o.text_edit_record_mutation(edit, plain, o.state.ui.frame)
			start, end := o.text_edit_selection_normalized(edit.selection)
			new_plain, edit.caret = o.text_edit_plain_splice(plain, start, end, "")
			edit.selection = {edit.caret, edit.caret}
			edit.has_preferred_column = false
			changed = true
		}
	case .PASTE:
		if opts.editable {
			if paste, ok := o.clipboard_get_text(); ok {
				defer delete(paste)
				normalized := o.text_edit_normalize_paste(paste, opts.multiline)
				new_plain, changed = text_edit_widget_insert_text(edit, plain, normalized, opts)
			}
		}
	case .UNDO:
		if opts.editable {
			if restored, ok := o.text_edit_apply_undo(edit, plain, o.state.ui.frame); ok {
				new_plain = restored
				changed = true
			}
		}
	case .REDO:
		if opts.editable {
			if restored, ok := o.text_edit_apply_redo(edit, plain, o.state.ui.frame); ok {
				new_plain = restored
				changed = true
			}
		}
	case .NONE:
	}

	if cmd != .NONE && cmd != .COPY {
		text_edit_widget_sync_edit_scroll(key, layout_id, layout_rect, edit, geo, scroll, config, opts, plain)
	}

	if opts.editable {
		text_edit_widget_sync_ime_caret(key, layout_id, layout_rect, edit, geo, opts, plain)
	}

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
	if edit == nil || !widget_is_focused(key) do return new_plain, false
	if !opts.editable && !opts.selectable do return new_plain, false

	geo := o.layout_text_edit_geometry(layout_id)
	edit_plain := text_edit_widget_edit_plain(geo, plain)
	page_lines := text_edit_widget_page_lines(layout_id, geo)
	shift := o.state.input.modifiers.shift
	ctrl := o.state.input.modifiers.ctrl || o.state.input.modifiers.super
	ime_active := o.input_ime_active()

	if !ime_active {
		for scancode in 0 ..< o.KEY_COUNT {
			if o.shortcut_key_consumed(o.Scancode(scancode)) do continue

			key_state := o.w_ctx.keys[scancode]
			if !(key_state.pressed || key_state.repeat) do continue

			nav_text := plain
			nav_caret := edit.caret
			nav_sel := edit.selection

			if opts.password {
				nav_text = edit_plain
				nav_caret = text_edit_widget_map_value_offset_to_geo(opts, plain, edit.caret, edit.caret)
				nav_sel = text_edit_widget_map_value_selection_to_geo(opts, plain, edit.selection, edit.caret)
			}

			handled: bool
			nav_caret, nav_sel, handled = o.text_edit_handle_key_navigation(
				nav_text,
				nav_caret,
				nav_sel,
				geo,
				o.Scancode(scancode),
				shift,
				ctrl,
				opts.multiline,
				page_lines,
				edit,
			)

			if handled {
				if opts.password {
					edit.caret = text_edit_widget_map_geo_offset_to_value(opts, plain, nav_caret, edit.caret)
					edit.selection = text_edit_widget_map_geo_selection_to_value(opts, plain, nav_sel, edit.caret)
				} else {
					edit.caret = nav_caret
					edit.selection = nav_sel
				}

				o.shortcut_consume_key(o.Scancode(scancode))
				text_edit_widget_sync_edit_scroll(key, layout_id, layout_rect, edit, geo, scroll, config, opts, plain)

				continue
			}

			if !opts.editable do continue

			#partial switch o.Scancode(scancode) {
			case .RETURN, .KP_ENTER:
				if opts.multiline {
					new_plain, changed = text_edit_widget_insert_text(edit, new_plain, "\n", opts)

					if changed {
						o.shortcut_consume_key(o.Scancode(scancode))
						text_edit_widget_sync_edit_scroll(key, layout_id, layout_rect, edit, geo, scroll, config, opts, plain)
					}
				} else {
					o.shortcut_consume_key(o.Scancode(scancode))
				}
			case .BACKSPACE:
				result_plain: string
				result_caret: int
				result_sel: o.Text_Selection
				result_changed: bool

				if ctrl {
					result_plain, result_caret, result_sel, result_changed = o.text_edit_backspace_word(
						new_plain,
						edit.caret,
						edit.selection,
					)
				} else {
					result_plain, result_caret, result_sel, result_changed = o.text_edit_backspace(
						new_plain,
						edit.caret,
						edit.selection,
					)
				}

				if result_changed {
					o.text_edit_record_mutation(edit, new_plain, o.state.ui.frame)
					new_plain = result_plain
					edit.caret = result_caret
					edit.selection = result_sel
					changed = true
					edit.has_preferred_column = false
					o.shortcut_consume_key(o.Scancode(scancode))
					text_edit_widget_sync_edit_scroll(key, layout_id, layout_rect, edit, geo, scroll, config, opts, plain)
				}
			case .DELETE:
				result_plain: string
				result_caret: int
				result_sel: o.Text_Selection
				result_changed: bool

				if ctrl {
					result_plain, result_caret, result_sel, result_changed = o.text_edit_delete_word(
						new_plain,
						edit.caret,
						edit.selection,
					)
				} else {
					result_plain, result_caret, result_sel, result_changed = o.text_edit_delete(
						new_plain,
						edit.caret,
						edit.selection,
					)
				}

				if result_changed {
					o.text_edit_record_mutation(edit, new_plain, o.state.ui.frame)
					new_plain = result_plain
					edit.caret = result_caret
					edit.selection = result_sel
					changed = true
					edit.has_preferred_column = false
					o.shortcut_consume_key(o.Scancode(scancode))
					text_edit_widget_sync_edit_scroll(key, layout_id, layout_rect, edit, geo, scroll, config, opts, plain)
				}
			}
		}
	}

	if opts.editable {
		inserted := o.input_take_text_input()

		if len(inserted) > 0 {
			if ime_active {
				o.input_clear_ime()
			}

			new_plain, changed = text_edit_widget_insert_text(edit, new_plain, inserted, opts)

			if changed {
				text_edit_widget_sync_edit_scroll(key, layout_id, layout_rect, edit, geo, scroll, config, opts, plain)
			}
		}

		edit.caret = o.text_edit_clamp_offset(new_plain, edit.caret)
		edit.selection = o.text_edit_clamp_selection(new_plain, edit.selection)
		text_edit_widget_sync_ime_caret(key, layout_id, layout_rect, edit, geo, opts, plain)
	} else {
		edit.caret = o.text_edit_clamp_offset(new_plain, edit.caret)
		edit.selection = o.text_edit_clamp_selection(new_plain, edit.selection)
	}

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
		o.text_edit_reset_blink(edit)
	case .COPY:
		o.text_edit_copy_plain(plain, edit.selection)
	case .CUT:
		if opts.editable && o.text_edit_copy_plain(plain, edit.selection) {
			o.text_edit_record_mutation(edit, tagged, o.state.ui.frame)
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
		if opts.editable {
			if paste, ok := o.clipboard_get_text(); ok {
				defer delete(paste)
				normalized := o.text_edit_normalize_paste(paste, opts.multiline)
				truncated := o.text_edit_truncate_insert_for_max_length(
					plain,
					edit.selection,
					normalized,
					opts.max_length,
				)

				if len(truncated) > 0 {
					doc := o.text_document_from_tagged(tagged)
					defer o.text_document_free_runs(&doc)
					o.text_edit_record_mutation(edit, tagged, o.state.ui.frame)
					start, end := o.text_edit_selection_normalized(edit.selection)
					o.text_document_delete_range(&doc, start, end)
					o.text_document_insert_plain(&doc, start, truncated)
					new_tagged = o.text_document_to_tagged(&doc)
					edit.caret = start + len(truncated)
					edit.selection = {edit.caret, edit.caret}
					edit.has_preferred_column = false
					changed = true
				}
			}
		}
	case .UNDO:
		if opts.editable {
			if restored, ok := o.text_edit_apply_undo(edit, tagged, o.state.ui.frame); ok {
				new_tagged = restored
				changed = true
			}
		}
	case .REDO:
		if opts.editable {
			if restored, ok := o.text_edit_apply_redo(edit, tagged, o.state.ui.frame); ok {
				new_tagged = restored
				changed = true
			}
		}
	case .NONE:
	}

	if cmd != .NONE && cmd != .COPY {
		text_edit_widget_sync_edit_scroll(key, layout_id, layout_rect, edit, geo, scroll, config, opts, plain)
	}

	text_edit_widget_sync_ime_caret(key, layout_id, layout_rect, edit, geo, opts, plain)

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
	ime_active := o.input_ime_active()

	if !ime_active {
		for scancode in 0 ..< o.KEY_COUNT {
			if o.shortcut_key_consumed(o.Scancode(scancode)) do continue

			key_state := o.w_ctx.keys[scancode]
			if !(key_state.pressed || key_state.repeat) do continue

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
				text_edit_widget_sync_edit_scroll(key, layout_id, layout_rect, edit, geo, scroll, config, opts, plain)

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
						text_edit_widget_sync_edit_scroll(key, layout_id, layout_rect, edit, geo, scroll, config, opts, plain)
					}
				} else {
					o.shortcut_consume_key(o.Scancode(scancode))
				}
			case .BACKSPACE:
				result_plain: string
				result_caret: int
				result_sel: o.Text_Selection
				result_changed: bool

				if ctrl {
					result_plain, result_caret, result_sel, result_changed = o.text_edit_backspace_word(
						new_plain,
						edit.caret,
						edit.selection,
					)
				} else {
					result_plain, result_caret, result_sel, result_changed = o.text_edit_backspace(
						new_plain,
						edit.caret,
						edit.selection,
					)
				}

				if result_changed {
					o.text_edit_record_mutation(edit, tagged, o.state.ui.frame)
					new_plain = result_plain
					edit.caret = result_caret
					edit.selection = result_sel
					plain_changed = true
					edit.has_preferred_column = false
					o.shortcut_consume_key(o.Scancode(scancode))
					text_edit_widget_sync_edit_scroll(key, layout_id, layout_rect, edit, geo, scroll, config, opts, plain)
				}
			case .DELETE:
				result_plain: string
				result_caret: int
				result_sel: o.Text_Selection
				result_changed: bool

				if ctrl {
					result_plain, result_caret, result_sel, result_changed = o.text_edit_delete_word(
						new_plain,
						edit.caret,
						edit.selection,
					)
				} else {
					result_plain, result_caret, result_sel, result_changed = o.text_edit_delete(
						new_plain,
						edit.caret,
						edit.selection,
					)
				}

				if result_changed {
					o.text_edit_record_mutation(edit, tagged, o.state.ui.frame)
					new_plain = result_plain
					edit.caret = result_caret
					edit.selection = result_sel
					plain_changed = true
					edit.has_preferred_column = false
					o.shortcut_consume_key(o.Scancode(scancode))
					text_edit_widget_sync_edit_scroll(key, layout_id, layout_rect, edit, geo, scroll, config, opts, plain)
				}
			}
		}
	}

	inserted := o.input_take_text_input()

	if len(inserted) > 0 {
		if ime_active {
			o.input_clear_ime()
		}

		new_plain, plain_changed = text_edit_widget_insert_text(edit, new_plain, inserted, opts)

		if plain_changed {
			text_edit_widget_sync_edit_scroll(key, layout_id, layout_rect, edit, geo, scroll, config, opts, plain)
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
	text_edit_widget_sync_ime_caret(key, layout_id, layout_rect, edit, geo, opts, plain)

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
