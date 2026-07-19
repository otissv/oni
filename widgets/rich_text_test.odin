package oni_widgets

import o ".."
import set "../set"
import "core:testing"

@(test)
rich_text_theme_base_sets_kind :: proc(t: ^testing.T) {
	frame := Rich_Text_Merged_State{}
	base := rich_text_widget_decl(&frame)
	testing.expect(t, base.kind == .RICH_TEXT)
}

@(test)
rich_text_refresh_parses_tags :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		props := Rich_Text_Props {
			config = {
				id = "rich",
				text = "{c:accent}Hi{/c}",
			},
		}
		frame := Rich_Text_Merged_State{}
		_ = rich_text_refresh_merged(props, &frame)
		testing.expect_value(t, frame.plain, "Hi")
		testing.expect(t, len(frame.runs) == 1)
		testing.expect(t, o.text_run_style_has(frame.runs[0].style, .color))
		testing.expect(t, frame.runs[0].style.color == o.Color.ACCENT)
		testing.expect(t, len(frame.layout_runs) == 1)
	})
}

@(test)
rich_text_layout_registers_rich_measure :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		_ = RichText(
			{
				config = {
					id = "rich-layout",
					text = "{c:foreground}A{/c}",
					width = set.Width(f32(120)),
					height = set.Height(f32(24)),
				},
			},
		)
		widget_test_finish_layout()

		expect_registered_id(t, "rich-layout")
		expect_layout_kind(t, "rich-layout", .RICH_TEXT)
		node, ok := widget_test_layout_node("rich-layout")
		testing.expect(t, ok)

		if ok {
			testing.expect_value(t, node.measure.text, "A")
			testing.expect(t, node.measure.rich)
			testing.expect(t, len(node.measure.runs) == 1)
		}
	})
}
