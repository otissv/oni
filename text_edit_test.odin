package oni

import "core:testing"

@(test)
text_edit_cluster_navigation :: proc(t: ^testing.T) {
	text := "aβc"

	testing.expect_value(t, text_edit_cluster_prev(text, len(text)), 3)
	testing.expect_value(t, text_edit_cluster_prev(text, 3), 1)
	testing.expect_value(t, text_edit_cluster_prev(text, 1), 0)
	testing.expect_value(t, text_edit_cluster_next(text, 0), 1)
	testing.expect_value(t, text_edit_cluster_next(text, 1), 3)
	testing.expect_value(t, text_edit_cluster_next(text, 3), len(text))
}

@(test)
text_edit_plain_splice_replaces_range :: proc(t: ^testing.T) {
	new_text, caret := text_edit_plain_splice("hello", 1, 4, "i")
	defer delete(new_text)

	testing.expect_value(t, new_text, "hio")
	testing.expect_value(t, caret, 2)
}

@(test)
text_edit_backspace_deletes_selection :: proc(t: ^testing.T) {
	selection := Text_Selection{anchor = 1, head = 4}
	new_text, caret, new_sel, changed := text_edit_backspace("hello", 4, selection)
	defer delete(new_text)

	testing.expect(t, changed)
	testing.expect_value(t, new_text, "ho")
	testing.expect_value(t, caret, 1)
	testing.expect_value(t, new_sel.anchor, 1)
	testing.expect_value(t, new_sel.head, 1)
}

@(test)
text_edit_delete_removes_codepoint :: proc(t: ^testing.T) {
	new_text, caret, new_sel, changed := text_edit_delete("aβc", 1, {})
	defer delete(new_text)

	testing.expect(t, changed)
	testing.expect_value(t, new_text, "ac")
	testing.expect_value(t, caret, 1)
	testing.expect_value(t, new_sel.anchor, 1)
	testing.expect_value(t, new_sel.head, 1)
}

@(test)
text_edit_word_at_finds_alnum_run :: proc(t: ^testing.T) {
	sel := text_edit_word_at("one two", 5)

	testing.expect_value(t, sel.anchor, 4)
	testing.expect_value(t, sel.head, 7)
}

@(test)
text_edit_undo_push_pop_and_clear :: proc(t: ^testing.T) {
	stack: Text_Undo_Stack
	text_edit_undo_stack_init(&stack)
	defer text_edit_undo_clear(&stack)

	text_edit_undo_push(&stack, "one", 3, {}, 1)
	text_edit_undo_push(&stack, "two", 2, {anchor = 0, head = 2}, 2)

	entry, ok := text_edit_undo_pop(&stack)
	defer delete(entry.text)

	testing.expect(t, ok)
	testing.expect_value(t, entry.text, "two")
	testing.expect_value(t, entry.caret, 2)
	testing.expect_value(t, entry.selection.head, 2)

	entry2, ok2 := text_edit_undo_pop(&stack)
	defer delete(entry2.text)

	testing.expect(t, ok2)
	testing.expect_value(t, entry2.text, "one")

	text_edit_undo_clear(&stack)
	testing.expect_value(t, len(stack.entries), 0)
}

@(test)
text_edit_set_and_consume_command :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			text_edit_set_command(.COPY)
			cmd := text_edit_consume_command()

			testing.expect_value(t, cmd, Text_Edit_Command.COPY)
			testing.expect_value(t, text_edit_consume_command(), Text_Edit_Command.NONE)
		},
	)
}

@(test)
text_edit_take_command_requires_focus :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			text_edit_set_command(.PASTE)
			testing.expect_value(t, text_edit_take_command(false), Text_Edit_Command.NONE)
			testing.expect_value(t, text_edit_consume_command(), Text_Edit_Command.PASTE)

			text_edit_set_command(.CUT)
			testing.expect_value(t, text_edit_take_command(true), Text_Edit_Command.CUT)
			testing.expect_value(t, text_edit_take_command(true), Text_Edit_Command.NONE)
		},
	)
}

@(test)
text_edit_within_max_length_respects_limit :: proc(t: ^testing.T) {
	testing.expect(t, text_edit_within_max_length("abc", 5, "d"))
	testing.expect(t, !text_edit_within_max_length("abcd", 5, "de"))
	testing.expect(t, !text_edit_within_max_length("β", 1, "a"))
	testing.expect(t, text_edit_within_max_length("β", 2, "a"))
	testing.expect(t, text_edit_within_max_length("abcd", 4, "xy", {anchor = 1, head = 3}))
}

@(test)
text_edit_truncate_insert_for_max_length_by_runes :: proc(t: ^testing.T) {
	truncated := text_edit_truncate_insert_for_max_length("ab", {}, "cdef", 3)
	testing.expect_value(t, truncated, "c")

	over_selection := text_edit_truncate_insert_for_max_length(
		"abcd",
		{anchor = 1, head = 3},
		"βγδε",
		4,
	)
	testing.expect_value(t, over_selection, "βγ")
}

@(test)
text_edit_normalize_paste_strips_newlines_for_single_line :: proc(t: ^testing.T) {
	single := text_edit_normalize_paste("a\nb\r\nc\rd", false)
	testing.expect_value(t, single, "a b c d")

	multi := text_edit_normalize_paste("a\nb", true)
	testing.expect_value(t, multi, "a\nb")
}

@(test)
text_edit_word_prev_next_and_delete :: proc(t: ^testing.T) {
	text := "one two three"

	testing.expect_value(t, text_edit_word_prev(text, 5), 4)
	testing.expect_value(t, text_edit_word_prev(text, 4), 0)
	testing.expect_value(t, text_edit_word_next(text, 0), 4)
	testing.expect_value(t, text_edit_word_next(text, 4), 8)

	new_text, caret, sel, changed := text_edit_backspace_word(text, 7, {})
	defer delete(new_text)

	testing.expect(t, changed)
	testing.expect_value(t, new_text, "one  three")
	testing.expect_value(t, caret, 4)
	testing.expect_value(t, sel.anchor, 4)

	deleted, d_caret, _, d_changed := text_edit_delete_word("one two", 4, {})
	defer delete(deleted)

	testing.expect(t, d_changed)
	testing.expect_value(t, deleted, "one ")
	testing.expect_value(t, d_caret, 4)
}

@(test)
text_edit_undo_redo_round_trip :: proc(t: ^testing.T) {
	edit: Text_Edit_State
	text_edit_undo_stack_init(&edit.undo)
	text_edit_undo_stack_init(&edit.redo)
	defer text_edit_undo_clear(&edit.undo)
	defer text_edit_undo_clear(&edit.redo)

	edit.caret = 3
	text_edit_record_mutation(&edit, "one", 1)
	edit.caret = 3
	edit.selection = {}

	restored, ok := text_edit_apply_undo(&edit, "two", 2)
	defer delete(restored)

	testing.expect(t, ok)
	testing.expect_value(t, restored, "one")
	testing.expect_value(t, edit.caret, 3)
	testing.expect_value(t, len(edit.redo.entries), 1)

	redone, redo_ok := text_edit_apply_redo(&edit, restored, 3)
	defer delete(redone)

	testing.expect(t, redo_ok)
	testing.expect_value(t, redone, "two")
	testing.expect_value(t, len(edit.undo.entries), 1)
	testing.expect_value(t, len(edit.redo.entries), 0)
}

@(test)
text_edit_reset_blink_clears_phase :: proc(t: ^testing.T) {
	edit := Text_Edit_State {
		blink_phase = 1.25,
	}
	text_edit_reset_blink(&edit)
	testing.expect_value(t, edit.blink_phase, f32(0))
}

@(test)
text_edit_register_click_shift_extends_selection :: proc(t: ^testing.T) {
	glyphs := []Text_Edit_Glyph {
		{cluster = 0, x0 = 0, x1 = 8, line_index = 0},
		{cluster = 1, x0 = 8, x1 = 16, line_index = 0},
		{cluster = 2, x0 = 16, x1 = 24, line_index = 0},
		{cluster = 3, x0 = 24, x1 = 32, line_index = 0},
	}
	geo := text_edit_test_geometry("abcd", glyphs, 1)
	edit := Text_Edit_State {
		caret = 1,
		selection = {anchor = 1, head = 1},
	}
	layout_rect := Rect{0, 0, 100, 20}

	caret, sel := text_edit_register_click(
		&edit,
		{28, 4},
		1,
		&geo,
		layout_rect,
		"abcd",
		true,
	)

	testing.expect_value(t, caret, 3)
	testing.expect_value(t, sel.anchor, 1)
	testing.expect_value(t, sel.head, 3)
	testing.expect_value(t, edit.blink_phase, f32(0))
}

@(test)
text_edit_pointer_selection_drag_extends_from_caret :: proc(t: ^testing.T) {
	glyphs := []Text_Edit_Glyph {
		{cluster = 0, x0 = 0, x1 = 8, line_index = 0},
		{cluster = 1, x0 = 8, x1 = 16, line_index = 0},
		{cluster = 2, x0 = 16, x1 = 24, line_index = 0},
		{cluster = 3, x0 = 24, x1 = 32, line_index = 0},
	}
	geo := text_edit_test_geometry("abcd", glyphs, 1)
	layout_rect := Rect{0, 0, 100, 20}

	caret, sel := text_edit_pointer_selection(
		&geo,
		layout_rect,
		{28, 4},
		1,
		{anchor = 1, head = 1},
	)

	testing.expect_value(t, caret, 3)
	testing.expect_value(t, sel.anchor, 1)
	testing.expect_value(t, sel.head, 3)

	caret, sel = text_edit_pointer_selection(
		&geo,
		layout_rect,
		{4, 4},
		3,
		sel,
	)

	testing.expect_value(t, caret, 0)
	testing.expect_value(t, sel.anchor, 1)
	testing.expect_value(t, sel.head, 0)
}

@(test)
text_edit_handle_key_navigation_word_move :: proc(t: ^testing.T) {
	edit: Text_Edit_State
	text := "one two"

	caret, sel, handled := text_edit_handle_key_navigation(
		text,
		7,
		{},
		nil,
		.LEFT,
		false,
		true,
		false,
		1,
		&edit,
	)

	testing.expect(t, handled)
	testing.expect_value(t, caret, 4)
	testing.expect_value(t, sel.anchor, 4)
	testing.expect_value(t, edit.blink_phase, f32(0))
}

@(private)
text_edit_test_geometry :: proc(
	plain: string,
	glyphs: []Text_Edit_Glyph,
	line_count: int,
) -> Text_Edit_Geometry {
	line_height: f32 = 16
	origins := make([]Vec2, line_count, context.temp_allocator)

	for i in 0 ..< line_count {
		origins[i] = {0, f32(i) * line_height}
	}

	return Text_Edit_Geometry {
		plain        = plain,
		line_origins = origins,
		line_height  = line_height,
		glyphs       = glyphs,
	}
}

@(test)
text_edit_line_at_follows_trailing_newline :: proc(t: ^testing.T) {
	glyphs := []Text_Edit_Glyph {
		{cluster = 0, line_index = 0},
		{cluster = 1, line_index = 0},
		{cluster = 2, line_index = 0},
		{cluster = 3, line_index = 0},
		{cluster = 4, line_index = 0},
	}
	geo := text_edit_test_geometry("hello\n", glyphs[:], 2)

	testing.expect_value(t, text_edit_line_at(&geo, 5), 0)
	testing.expect_value(t, text_edit_line_at(&geo, 6), 1)
}

@(test)
text_edit_line_at_handles_blank_line :: proc(t: ^testing.T) {
	glyphs := []Text_Edit_Glyph {
		{cluster = 0, line_index = 0},
	}
	geo := text_edit_test_geometry("a\n\nc", glyphs[:], 3)

	testing.expect_value(t, text_edit_line_at(&geo, 2), 1)
}

@(test)
text_edit_offset_for_line_maps_blank_lines :: proc(t: ^testing.T) {
	testing.expect_value(t, text_edit_offset_for_line("hello\n", 0), 0)
	testing.expect_value(t, text_edit_offset_for_line("hello\n", 1), 6)
	testing.expect_value(t, text_edit_offset_for_line("a\n\nc", 1), 2)
}

@(test)
text_edit_offset_at_line_x_picks_nearest_cluster :: proc(t: ^testing.T) {
	glyphs := []Text_Edit_Glyph {
		{cluster = 0, line_index = 0, x0 = 0, x1 = 8},
		{cluster = 1, line_index = 0, x0 = 8, x1 = 16},
		{cluster = 0, line_index = 1, x0 = 0, x1 = 8},
		{cluster = 1, line_index = 1, x0 = 8, x1 = 16},
	}
	geo := text_edit_test_geometry("ab\ncd", glyphs[:], 2)

	testing.expect_value(t, text_edit_offset_at_line_x(&geo, 1, 12), 1)
	testing.expect_value(t, text_edit_offset_at_line_x(&geo, 0, -4), 0)
}

@(test)
text_edit_scroll_to_show_bounds_reveals_caret_below_viewport :: proc(t: ^testing.T) {
	glyphs := []Text_Edit_Glyph {
		{cluster = 0, line_index = 0, x0 = 0, x1 = 8},
	}
	geo := text_edit_test_geometry("a", glyphs[:], 1)
	scroll := Vec2{0, 0}
	ov_auto: Overflow = .AUTO
	layout_rect := Rect{0, 0, 80, 40}
	bounds := text_edit_caret_content_bounds(&geo, layout_rect, scroll, 0)
	bounds.y0 = 72
	bounds.y1 = 88

	text_edit_scroll_to_show_bounds(
		&scroll,
		{80, 40},
		{0, 80},
		bounds,
		TEXT_EDIT_SCROLL_MARGIN,
		text_edit_scroll_axes(ov_auto, ov_auto),
	)

	expect_close(t, scroll.y, 52)
}

@(test)
text_edit_caret_geometry_uses_padding_origin_without_double_scroll :: proc(t: ^testing.T) {
	glyphs := []Text_Edit_Glyph {
		{cluster = 0, line_index = 0, x0 = 18, x1 = 26},
	}
	origins := make([]Vec2, 1, context.temp_allocator)
	origins[0] = {8, 6}
	geo := Text_Edit_Geometry {
		plain        = "a",
		line_origins = origins,
		line_height  = 16,
		glyphs       = glyphs,
	}
	layout_rect := Rect{10, 20, 100, 40}
	caret := text_edit_caret_geometry(&geo, layout_rect, 0)

	expect_close(t, caret.x, 18)
	expect_close(t, caret.y, 26)
}

@(test)
text_edit_password_mask_maps_unicode_runes :: proc(t: ^testing.T) {
	value := "aβc"
	testing.expect_value(t, text_edit_password_value_to_mask_offset(value, 0), 0)
	testing.expect_value(t, text_edit_password_value_to_mask_offset(value, 1), 1)
	testing.expect_value(t, text_edit_password_value_to_mask_offset(value, 3), 2)
	testing.expect_value(t, text_edit_password_mask_to_value_offset(value, 2), 3)
	testing.expect_value(t, text_edit_password_mask_to_value_offset(value, 3), len(value))
}

@(test)
text_edit_ime_offset_mapping_round_trips :: proc(t: ^testing.T) {
	ime_at := 1
	ime_len := 3

	testing.expect_value(t, text_edit_ime_value_to_display_offset(ime_at, ime_len, 0), 0)
	testing.expect_value(t, text_edit_ime_value_to_display_offset(ime_at, ime_len, 1), 1)
	testing.expect_value(t, text_edit_ime_value_to_display_offset(ime_at, ime_len, 2), 5)

	testing.expect_value(t, text_edit_ime_display_to_value_offset(ime_at, ime_len, 0), 0)
	testing.expect_value(t, text_edit_ime_display_to_value_offset(ime_at, ime_len, 1), 1)
	testing.expect_value(t, text_edit_ime_display_to_value_offset(ime_at, ime_len, 2), 1)
	testing.expect_value(t, text_edit_ime_display_to_value_offset(ime_at, ime_len, 4), 1)
	testing.expect_value(t, text_edit_ime_display_to_value_offset(ime_at, ime_len, 5), 2)
}

@(test)
text_edit_ime_display_caret_uses_cursor_runes :: proc(t: ^testing.T) {
	ime := "あい"
	testing.expect_value(t, text_edit_ime_display_caret(1, ime, 0), 1)
	testing.expect_value(t, text_edit_ime_display_caret(1, ime, 1), 1 + len("あ"))
	testing.expect_value(t, text_edit_ime_display_caret(1, ime, 2), 1 + len(ime))
}

@(test)
text_edit_ime_underline_range_full_and_segment :: proc(t: ^testing.T) {
	ime := "あい"
	start, end := text_edit_ime_underline_range(2, ime, 0, 0)
	testing.expect_value(t, start, 2)
	testing.expect_value(t, end, 2 + len(ime))

	seg_start, seg_end := text_edit_ime_underline_range(2, ime, 1, 1)
	testing.expect_value(t, seg_start, 2 + len("あ"))
	testing.expect_value(t, seg_end, 2 + len(ime))
}

@(test)
text_edit_handle_key_navigation_moves_between_lines :: proc(t: ^testing.T) {
	glyphs := []Text_Edit_Glyph {
		{cluster = 0, line_index = 0, x0 = 0, x1 = 8},
		{cluster = 1, line_index = 0, x0 = 8, x1 = 16},
		{cluster = 3, line_index = 1, x0 = 0, x1 = 8},
		{cluster = 4, line_index = 1, x0 = 8, x1 = 16},
	}
	geo := text_edit_test_geometry("ab\ncd", glyphs[:], 2)
	edit: Text_Edit_State

	new_caret, _, handled := text_edit_handle_key_navigation(
		geo.plain,
		4,
		{},
		&geo,
		.UP,
		false,
		false,
		true,
		1,
		&edit,
	)

	testing.expect(t, handled)
	testing.expect_value(t, new_caret, 1)
}
