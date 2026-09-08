package oni_widgets

import o ".."
import set "../set"
import "core:strings"
import "core:testing"

@(private)
rich_text_input_test_clear_edit :: proc(edit: ^o.Text_Edit_State) {
	if edit == nil do return

	o.text_edit_undo_clear(&edit.undo)
	o.text_edit_undo_clear(&edit.redo)
}

@(test)
rich_text_input_theme_base_sets_kind :: proc(t: ^testing.T) {
	frame := Rich_Text_Input_State{}
	base := rich_text_input_theme_base(&frame)
	testing.expect(t, base.kind == .RICH_TEXT_INPUT)
	testing.expect(t, base.accepts_text_input)
}

@(test)
rich_text_input_document_insert_preserves_style :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		key := o.element_key("rti-field")
		edit := o.widget_text_edit_ensure(key)
		testing.expect(t, edit != nil)
		defer rich_text_input_test_clear_edit(edit)

		edit.caret = 2
		edit.selection = {2, 2}

		tagged := "{b}ab{/b}c"
		opts := Text_Edit_Widget_Opts {
			widget_kind = .RICH_TEXT_INPUT,
			selectable  = true,
			editable    = true,
			caret       = true,
		}

		o.w_ctx.focused_id = key
		append(&o.state.input.text_input, 'Z')

		updated, changed := text_edit_widget_apply_document_edits(
			tagged,
			key,
			o.ui_id("rti-field"),
			{0, 0, 200, 24},
			nil,
			{},
			opts,
		)

		testing.expect(t, changed)
		defer delete(updated)
		delete(o.state.input.text_input)
		testing.expect_value(t, rich_text_input_plain(updated), "abZc")
		testing.expect(t, strings.contains(updated, "{b}"))
		testing.expect_value(t, edit.caret, 3)
	})
}

@(test)
rich_text_input_document_insert_demo_text_keeps_valid_tags :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		key := o.element_key("rti-demo-field")
		edit := o.widget_text_edit_ensure(key)
		testing.expect(t, edit != nil)
		defer rich_text_input_test_clear_edit(edit)

		tagged := "{c:accent}Accent{/c} {b}bold{/b} {i}italic{/i} — edit with inline tags"
		plain := rich_text_input_plain(tagged)
		edit.caret = len(plain)
		edit.selection = {edit.caret, edit.caret}

		opts := Text_Edit_Widget_Opts {
			widget_kind = .RICH_TEXT_INPUT,
			selectable  = true,
			editable    = true,
			caret       = true,
			multiline   = true,
		}

		o.w_ctx.focused_id = key
		append(&o.state.input.text_input, 'u')

		updated, changed := text_edit_widget_apply_document_edits(
			tagged,
			key,
			o.ui_id("rti-demo-field"),
			{0, 0, 520, 120},
			nil,
			{},
			opts,
		)

		testing.expect(t, changed)
		defer delete(updated)
		delete(o.state.input.text_input)

		parsed := o.text_tags_parse(updated, context.temp_allocator)
		testing.expect_value(t, len(parsed.diagnostics), 0)
		testing.expect_value(t, parsed.plain, "Accent bold italic — edit with inline tagsu")
		testing.expect_value(t, edit.caret, len(parsed.plain))
	})
}

@(test)
rich_text_input_document_select_all :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		key := o.element_key("rti-cmd")
		edit := o.widget_text_edit_ensure(key)
		testing.expect(t, edit != nil)
		defer rich_text_input_test_clear_edit(edit)

		edit.caret = 2
		edit.selection = {2, 2}

		tagged := "{b}hello{/b}"
		opts := Text_Edit_Widget_Opts {
			widget_kind = .RICH_TEXT_INPUT,
			selectable  = true,
			editable    = true,
			caret       = true,
		}

		o.w_ctx.focused_id = key
		o.text_edit_set_command(.SELECT_ALL)

		updated, changed := text_edit_widget_apply_document_edits(
			tagged,
			key,
			o.ui_id("rti-cmd"),
			{0, 0, 200, 24},
			nil,
			{},
			opts,
		)

		testing.expect(t, !changed)
		testing.expect_value(t, updated, tagged)
		testing.expect_value(t, edit.selection.anchor, 0)
		testing.expect_value(t, edit.selection.head, len("hello"))
	})
}

@(test)
rich_text_input_document_backspace :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		key := o.element_key("rti-bs")
		edit := o.widget_text_edit_ensure(key)
		testing.expect(t, edit != nil)
		defer rich_text_input_test_clear_edit(edit)

		edit.caret = 3
		edit.selection = {3, 3}

		tagged := "{b}abc{/b}"
		opts := Text_Edit_Widget_Opts {
			widget_kind = .RICH_TEXT_INPUT,
			selectable  = true,
			editable    = true,
			caret       = true,
		}

		o.w_ctx.focused_id = key
		o.text_edit_set_nav(.BACKSPACE, false, false)

		updated, changed := text_edit_widget_apply_document_edits(
			tagged,
			key,
			o.ui_id("rti-bs"),
			{0, 0, 200, 24},
			nil,
			{},
			opts,
		)

		testing.expect(t, changed)
		defer delete(updated)
		testing.expect_value(t, rich_text_input_plain(updated), "ab")
		testing.expect_value(t, edit.caret, 2)
	})
}

@(test)
rich_text_input_document_backspace_deletes_selection :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		key := o.element_key("rti-sel")
		edit := o.widget_text_edit_ensure(key)
		testing.expect(t, edit != nil)
		defer rich_text_input_test_clear_edit(edit)

		edit.caret = 5
		edit.selection = {0, 5}

		tagged := "{b}hello{/b}"
		opts := Text_Edit_Widget_Opts {
			widget_kind = .RICH_TEXT_INPUT,
			selectable  = true,
			editable    = true,
			caret       = true,
		}

		o.w_ctx.focused_id = key
		o.text_edit_set_nav(.BACKSPACE, false, false)

		updated, changed := text_edit_widget_apply_document_edits(
			tagged,
			key,
			o.ui_id("rti-sel"),
			{0, 0, 200, 24},
			nil,
			{},
			opts,
		)

		testing.expect(t, changed)
		defer delete(updated)
		testing.expect_value(t, rich_text_input_plain(updated), "")
		testing.expect_value(t, edit.caret, 0)
	})
}

@(private)
rich_text_input_test_owned_value: string
@(private)
rich_text_input_test_owned: bool

@(private)
rich_text_input_test_on_change :: proc(_: Rich_Text_Input_Event, tagged: string) {
	if rich_text_input_test_owned {
		delete(rich_text_input_test_owned_value)
	} else {
		rich_text_input_test_owned = true
	}

	rich_text_input_test_owned_value = tagged
}

@(test)
rich_text_input_widget_draw_typing_with_owned_on_change :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		rich_text_input_test_owned_value = strings.clone("{b}ab{/b}c")
		rich_text_input_test_owned = true
		defer {
			delete(rich_text_input_test_owned_value)
			rich_text_input_test_owned = false
		}

		widget_test_begin_layout()

		Rich_Text_Input(
			{
				config = {
					id = "rti-owned",
					text = rich_text_input_test_owned_value,
					width = set.Width(f32(220)),
					height = set.Height(f32(32)),
				},
				on_change = rich_text_input_test_on_change,
			},
		)

		widget_test_finish_layout()
		widget_test_begin_draw()

		o.w_ctx.focused_id = o.element_key("rti-owned")
		edit := o.widget_text_edit_ensure(o.element_key("rti-owned"))
		testing.expect(t, edit != nil)
		edit.caret = 2
		edit.selection = {2, 2}
		append(&o.state.input.text_input, 'Z')

		Rich_Text_Input(
			{
				config = {
					id = "rti-owned",
					text = rich_text_input_test_owned_value,
					width = set.Width(f32(220)),
					height = set.Height(f32(32)),
				},
				on_change = rich_text_input_test_on_change,
			},
		)

		delete(o.state.input.text_input)
		widget_test_end_frame()

		testing.expect_value(t, rich_text_input_plain(rich_text_input_test_owned_value), "abZc")
		testing.expect(t, strings.contains(rich_text_input_test_owned_value, "{b}"))
	})
}

@(test)
rich_text_input_widget_draw_ctrl_a_selects_all :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		o.Shortcut_Install_Defaults()
		o.Shortcut_Install_Tool_Defaults()

		key := o.element_key("rti-shortcut")

		widget_test_begin_layout()

		Rich_Text_Input(
			{
				config = {
					id = "rti-shortcut",
					text = "{b}hello{/b}",
					width = set.Width(f32(220)),
					height = set.Height(f32(32)),
				},
			},
		)

		widget_test_finish_layout()

		o.w_ctx.focused_id = key
		edit := o.widget_text_edit_ensure(key)
		testing.expect(t, edit != nil)
		edit.caret = 2
		edit.selection = {2, 2}
		widget_test_press_shortcut(.A, {ctrl = true})

		widget_test_begin_draw()

		Rich_Text_Input(
			{
				config = {
					id = "rti-shortcut",
					text = "{b}hello{/b}",
					width = set.Width(f32(220)),
					height = set.Height(f32(32)),
				},
			},
		)

		widget_test_end_frame()

		testing.expect_value(t, edit.selection.anchor, 0)
		testing.expect_value(t, edit.selection.head, len("hello"))
	})
}

@(test)
rich_text_input_layout_registers_rich_measure :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Rich_Text_Input(
			{
				config = {
					id = "rti-layout",
					text = "{c:accent}Edit{/c}",
					width = set.Width(f32(160)),
					height = set.Height(f32(32)),
				},
			},
		)
		widget_test_finish_layout()

		expect_registered_id(t, "rti-layout")
		expect_layout_kind(t, "rti-layout", .RICH_TEXT_INPUT)

		node, ok := widget_test_layout_node("rti-layout")
		testing.expect(t, ok)

		if ok {
			testing.expect(t, node.measure.rich)
			testing.expect_value(t, node.measure.edit_plain, "Edit")
		}
	})
}
