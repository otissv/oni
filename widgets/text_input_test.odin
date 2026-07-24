package oni_widgets

import o ".."
import set "../set"
import "core:testing"

@(test)
text_input_select_on_focus_defaults :: proc(t: ^testing.T) {
	testing.expect(t, text_input_select_on_focus({}))
	testing.expect(t, text_input_select_on_focus({select_on_focus = false}))
	testing.expect(t, !text_input_select_on_focus({multiline = true}))
	testing.expect(t, text_input_select_on_focus({multiline = true, select_on_focus = true}))
}

@(test)
text_input_theme_base_sets_kind :: proc(t: ^testing.T) {
	frame := Text_Input_State{}
	base := text_input_theme_base(&frame)
	testing.expect(t, base.kind == .TEXT_INPUT)
	testing.expect(t, base.accepts_text_input)
}

@(test)
text_input_readonly_blocks_insert_allows_select_copy :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		key := o.element_key("ro-field")
		edit := o.widget_text_edit_ensure(key)
		testing.expect(t, edit != nil)
		edit.caret = 5
		edit.selection = {0, 5}

		plain := "hello"
		opts := Text_Edit_Widget_Opts {
			selectable = true,
			editable   = false,
			caret      = true,
		}

		o.w_ctx.focused_id = key

		updated, changed := text_edit_widget_handle_keys(
			key,
			o.ui_id("ro-field"),
			{0, 0, 100, 24},
			nil,
			plain,
			{},
			opts,
		)
		testing.expect(t, !changed)
		testing.expect_value(t, updated, plain)

		o.text_edit_set_command(.SELECT_ALL)
		updated, changed = text_edit_widget_consume_commands(
			key,
			o.ui_id("ro-field"),
			{0, 0, 100, 24},
			nil,
			plain,
			{},
			opts,
		)
		testing.expect(t, !changed)
		testing.expect_value(t, edit.selection.anchor, 0)
		testing.expect_value(t, edit.selection.head, len(plain))

		o.text_edit_set_command(.CUT)
		updated, changed = text_edit_widget_consume_commands(
			key,
			o.ui_id("ro-field"),
			{0, 0, 100, 24},
			nil,
			plain,
			{},
			opts,
		)
		testing.expect(t, !changed)
		testing.expect_value(t, updated, plain)

		o.text_edit_set_command(.PASTE)
		updated, changed = text_edit_widget_consume_commands(
			key,
			o.ui_id("ro-field"),
			{0, 0, 100, 24},
			nil,
			plain,
			{},
			opts,
		)
		testing.expect(t, !changed)
		testing.expect_value(t, updated, plain)
	})
}

@(test)
text_input_select_on_focus_selects_all :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		key := o.element_key("sof-field")
		plain := "hello"
		cfg := Text_Input_Config {
			text = plain,
		}

		text_input_apply_select_on_focus(key, plain, cfg)
		edit := o.widget_text_edit_get(key)
		testing.expect(t, edit != nil)
		testing.expect_value(t, edit.selection.anchor, 0)
		testing.expect_value(t, edit.selection.head, len(plain))
		testing.expect_value(t, edit.caret, len(plain))
	})
}

@(test)
text_input_select_on_focus_skips_multiline_default :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		key := o.element_key("sof-multi")
		plain := "hello"
		edit := o.widget_text_edit_ensure(key)
		edit.caret = 2
		edit.selection = {2, 2}

		text_input_apply_select_on_focus(key, plain, {text = plain, multiline = true})
		testing.expect_value(t, edit.caret, 2)
		testing.expect_value(t, edit.selection.head, 2)

		text_input_apply_select_on_focus(
			key,
			plain,
			{text = plain, multiline = true, select_on_focus = true},
		)
		testing.expect_value(t, edit.selection.anchor, 0)
		testing.expect_value(t, edit.selection.head, len(plain))
	})
}

@(test)
text_input_layout_registers_and_centers_single_line :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Text_Input({
			config = {
				id = "ti-center",
				text = "Hi",
				width = set.Width(f32(200)),
				height = set.Height(f32(48)),
			},
		})
		widget_test_finish_layout()

		expect_registered_id(t, "ti-center")
		expect_layout_kind(t, "ti-center", .TEXT_INPUT)

		node, ok := widget_test_layout_node("ti-center")
		testing.expect(t, ok)
		if !ok do return

		testing.expect(t, node.config.justify.y == o.Justify_Align.CENTER)
		testing.expect(t, node.config.wrap == o.Text_Wrap_Kind.NONE)
	})
}

@(test)
text_input_readonly_clears_text_input_note :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Text_Input({
			config = {
				id = "ti-readonly",
				text = "locked",
				readonly = true,
				width = set.Width(f32(160)),
			},
		})
		widget_test_finish_layout()

		expect_registered_id(t, "ti-readonly")
		testing.expect(t, !o.shortcut_text_input_effective("ti-readonly"))
	})
}
