package oni_widgets

import o ".."
import set "../set"
import "core:testing"

@(test)
text_theme_base_sets_text_kind :: proc(t: ^testing.T) {
	frame := Text_Merged_State{}
	base := text_widget_decl(&frame)
	testing.expect(t, base.kind == .TEXT)
}

@(test)
text_refresh_merged_copies_display_string :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		props := Text_Props {
			config = {id = "label", text = "Hello"},
		}
		frame := Text_Merged_State{}
		event := text_refresh_merged(props, &frame)
		testing.expect_value(t, frame.text, "Hello")
		testing.expect(t, frame.style.kind == .TEXT)
		testing.expect_value(t, event.frame_state.text, "Hello")
	})
}

@(test)
text_layout_registers_node_and_measure_text :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		_ = Text(
			{
				config = {
					id = "txt",
					text = "Hi",
					width = set.Width(f32(100)),
					height = set.Height(f32(24)),
				},
			},
		)
		widget_test_finish_layout()

		expect_registered_id(t, "txt")
		expect_layout_kind(t, "txt", .TEXT)
		node, ok := widget_test_layout_node("txt")
		testing.expect(t, ok)
		if ok {
			testing.expect_value(t, node.measure.text, "Hi")
		}
	})
}

@(test)
text_tabbable_and_disabled_tab_order :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		_ = Text(
			{
				config = {
					id = "tab-txt",
					text = "A",
					tabbable = set.Bool(true),
					width = set.Width(f32(40)),
					height = set.Height(f32(20)),
				},
			},
		)
		expect_in_tab_order(t, "tab-txt", true)

		_ = Text(
			{
				config = {
					id = "dis-txt",
					text = "B",
					disabled = set.Bool(true),
					tabbable = set.Bool(true),
					width = set.Width(f32(40)),
					height = set.Height(f32(20)),
				},
			},
		)
		expect_in_tab_order(t, "dis-txt", false)
		widget_test_finish_layout()
	})
}

@(test)
text_unmount_skips_layout_node :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		_ = Text({
			config = {id = "txt-gone", text = "x"},
			unmount = true,
			on_unmount = proc(frame_state: Text_Merged_State) -> o.Mount {
				_ = frame_state
				return .COMPLETED
			},
		})
		_, ok := widget_test_layout_node("txt-gone")
		testing.expect(t, !ok)
		widget_test_finish_layout()
	})
}
