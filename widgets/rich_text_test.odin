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
rich_text_prepare_layout_input_parses_tags :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		props := Rich_Text_Props {
			config = {
				id = "rich",
				text = "{c:accent}Hi{/c}",
			},
		}
		frame := Rich_Text_Merged_State{}
		input := rich_text_prepare_layout_input(props, &frame)
		testing.expect_value(t, input.measure_text, "Hi")
		testing.expect(t, input.rich)
		testing.expect(t, len(input.layout_runs) == 1)
		testing.expect(t, o.text_run_style_has(input.layout_runs[0].style, .color))
		testing.expect(t, input.layout_runs[0].style.color == o.Color.ACCENT)

		widget_test_finish_layout()
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

@(test)
rich_text_parses_tags_only_on_layout_pass :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		o.Test_Text_Tags_Parse_Call_Count_Reset()

		widget_test_begin_layout()

		_ = RichText({
			config = {
				id = "rich-once",
				text = "{c:accent}Once{/c}",
				width = set.Width(f32(120)),
				height = set.Height(f32(24)),
			},
		})

		widget_test_finish_layout()
		testing.expect_value(t, o.Test_Text_Tags_Parse_Call_Count(), 1)

		widget_test_begin_draw()

		_ = RichText({
			config = {
				id = "rich-once",
				text = "{c:accent}Once{/c}",
				width = set.Width(f32(120)),
				height = set.Height(f32(24)),
			},
		})

		widget_test_end_frame()
		testing.expect_value(t, o.Test_Text_Tags_Parse_Call_Count(), 1)
	})
}

@(test)
rich_text_layout_runs_survive_to_draw_pass :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()

		_ = RichText({
			config = {
				id = "rich-draw",
				text = "{c:accent}Paint{/c}",
				width = set.Width(f32(120)),
				height = set.Height(f32(24)),
			},
		})

		widget_test_finish_layout()

		node, ok := widget_test_layout_node("rich-draw")
		testing.expect(t, ok)

		if ok {
			testing.expect(t, node.measure.rich)
			testing.expect(t, len(node.measure.runs) == 1)
			testing.expect(t, node.measure.runs[0].style.color == o.Color.ACCENT)
		}

		widget_test_begin_draw()

		_ = RichText({
			config = {
				id = "rich-draw",
				text = "{c:accent}Paint{/c}",
				width = set.Width(f32(120)),
				height = set.Height(f32(24)),
			},
		})

		widget_test_end_frame()
	})
}
