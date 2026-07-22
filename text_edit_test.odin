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
