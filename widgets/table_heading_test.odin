package oni_widgets

import o ".."
import set "../set"
import "core:testing"

@(test)
table_heading_theme_base_sets_kind_and_defaults :: proc(t: ^testing.T) {
	frame := Table_Heading_State{}
	base := table_heading_theme_base(&frame)
	testing.expect(t, base.kind == .TABLE_HEADING)
	testing.expect(t, base.min_h.mode == .Value)
}

@(test)
table_heading_layout_registers_node_id_and_kind :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Table_Heading(
			{
				config = {
					id = "table_heading-1",
					width = set.Width(f32(80)),
					height = set.Height(f32(32)),
				},
			},
		)
		widget_test_finish_layout()

		expect_registered_id(t, "table_heading-1")
		expect_layout_kind(t, "table_heading-1", .TABLE_HEADING)
	})
}

@(test)
table_heading_tabbable_registers_in_tab_order :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Table_Heading(
			{
				config = {
					id = "table_heading-tab",
					tabbable = set.Bool(true),
					width = set.Width(f32(40)),
					height = set.Height(f32(20)),
				},
			},
		)
		expect_in_tab_order(t, "table_heading-tab", true)
		widget_test_finish_layout()
	})
}

@(test)
table_heading_disabled_skips_tab_order :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Table_Heading(
			{
				config = {
					id = "table_heading-disabled",
					disabled = set.Bool(true),
					tabbable = set.Bool(true),
					width = set.Width(f32(40)),
					height = set.Height(f32(20)),
				},
			},
		)
		expect_in_tab_order(t, "table_heading-disabled", false)
		widget_test_finish_layout()
	})
}

@(test)
table_heading_unmount_skips_layout_node :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Table_Heading({
			config = {
				id = "table_heading-gone",
				width = set.Width(f32(40)),
				height = set.Height(f32(20)),
			},
			unmount = true,
			on_unmount = proc(frame_state: Table_Heading_State) -> o.Mount {
				_ = frame_state
				return .COMPLETED
			},
		})
		_, ok := widget_test_layout_node("table_heading-gone")
		testing.expect(t, !ok)
		widget_test_finish_layout()
	})
}

@(test)
table_heading_config_override_preserves_kind :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		props := Table_Heading_Props {
			config = {id = "table_heading-styled", background = set.Background(o.Color.PRIMARY)},
		}
		frame := Table_Heading_State{}
		config := widget_config(props, &frame, table_heading_theme_base)
		testing.expect(t, config.kind == .TABLE_HEADING)
		testing.expect_value(t, config.id, "table_heading-styled")
	})
}
