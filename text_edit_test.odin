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
	bounds := text_edit_caret_content_bounds(&geo, 0)
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
