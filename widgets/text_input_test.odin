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

		Text_Input({config = {id = "ti-center", text = "Hi", width = set.Width(f32(200)), height = set.Height(f32(48))}})
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

		Text_Input(
			{
				config = {
					id = "ti-readonly",
					text = "locked",
					readonly = true,
					width = set.Width(f32(160)),
				},
			},
		)
		widget_test_finish_layout()

		expect_registered_id(t, "ti-readonly")
		testing.expect(t, !o.shortcut_text_input_effective("ti-readonly"))
	})
}

@(test)
text_input_widget_draw_ctrl_a_selects_all :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		o.Shortcut_Install_Defaults()
		o.Shortcut_Install_Tool_Defaults()

		key := o.element_key("ti-shortcut")

		widget_test_begin_layout()

		Text_Input(
			{
				config = {
					id = "ti-shortcut",
					text = "hello",
					multiline = true,
					width = set.Width(f32(200)),
					height = set.Height(f32(80)),
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

		Text_Input(
			{
				config = {
					id = "ti-shortcut",
					text = "hello",
					multiline = true,
					width = set.Width(f32(200)),
					height = set.Height(f32(80)),
				},
			},
		)

		widget_test_end_frame()

		testing.expect_value(t, edit.selection.anchor, 0)
		testing.expect_value(t, edit.selection.head, len("hello"))
	})
}

@(test)
text_input_pointer_focus_survives_next_frame_prune :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		cfg := Text_Input_Config {
			id = "ti-focus",
			text = "hello",
			width = set.Width(f32(200)),
			height = set.Height(f32(40)),
		}

		widget_test_begin_layout()
		Text_Input({config = cfg})
		widget_test_finish_layout()

		node, ok := widget_test_layout_node("ti-focus")
		testing.expect(t, ok)
		if !ok do return

		o.w_ctx.mouse_x = node.rect.x + node.rect.w * 0.5
		o.w_ctx.mouse_y = node.rect.y + node.rect.h * 0.5
		widget_test_begin_draw()
		o.w_ctx.left_mouse.pressed = true
		o.w_ctx.left_mouse.down = true

		Text_Input({config = cfg})
		testing.expect_value(t, o.w_ctx.focused_id, "ti-focus")
		widget_test_end_frame()

		widget_test_begin_layout()
		Text_Input({config = cfg})
		widget_test_finish_layout()
		widget_test_begin_draw()

		testing.expect_value(t, o.w_ctx.focused_id, "ti-focus")
		testing.expect(t, widget_is_focused("ti-focus"))

		Text_Input({config = cfg})
		testing.expect(t, widget_is_focused("ti-focus"))
		widget_test_end_frame()
	})
}

@(test)
text_input_duplicate_id_later_instance_does_not_steal_focus :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		cfg_a := Text_Input_Config {
			id = "shared",
			text = "a",
			width = set.Width(f32(100)),
			height = set.Height(f32(40)),
			x = set.F32(0),
			y = set.F32(0),
			position = set.Position(.ABSOLUTE),
		}
		cfg_b := Text_Input_Config {
			id = "shared",
			text = "b",
			width = set.Width(f32(100)),
			height = set.Height(f32(40)),
			x = set.F32(0),
			y = set.F32(80),
			position = set.Position(.ABSOLUTE),
		}

		widget_test_begin_layout()
		Text_Input({config = cfg_a})
		Text_Input({config = cfg_b})
		widget_test_finish_layout()

		o.w_ctx.mouse_x = 20
		o.w_ctx.mouse_y = 20
		widget_test_begin_draw()
		o.w_ctx.left_mouse.pressed = true
		o.w_ctx.left_mouse.down = true

		Text_Input({config = cfg_a})
		testing.expect_value(t, o.w_ctx.focused_id, "shared")
		testing.expect(t, o.w_ctx.pointer_focus_claimed)

		Text_Input({config = cfg_b})
		testing.expect_value(t, o.w_ctx.focused_id, "shared")
		widget_test_end_frame()
	})
}
