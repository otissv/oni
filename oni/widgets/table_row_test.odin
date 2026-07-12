package widgets

import o ".."
import "core:testing"
import set "../set"

@(test)
table_row_theme_base_sets_kind_and_defaults :: proc(t: ^testing.T) {
	frame := Table_Row_State{}
	base := table_row_theme_base(&frame)
	testing.expect(t, base.kind == .TABLE_ROW)
	testing.expect(t, base.justify.mode == .Value)
}

@(test)
table_row_layout_registers_node_id_and_kind :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Table_Row(
				{
					config = {
						id = "table_row-1",
						width = set.Width(f32(80)),
						height = set.Height(f32(32)),
					},
				},
			)
			widget_test_finish_layout()

			expect_registered_id(t, "table_row-1")
			expect_layout_kind(t, "table_row-1", .TABLE_ROW)
		},
	)
}

@(test)
table_row_tabbable_registers_in_tab_order :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Table_Row(
				{
					config = {
						id = "table_row-tab",
						tabbable = set.Bool(true),
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
				},
			)
			expect_in_tab_order(t, "table_row-tab", true)
			widget_test_finish_layout()
		},
	)
}

@(test)
table_row_disabled_skips_tab_order :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Table_Row(
				{
					config = {
						id = "table_row-disabled",
						disabled = set.Bool(true),
						tabbable = set.Bool(true),
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
				},
			)
			expect_in_tab_order(t, "table_row-disabled", false)
			widget_test_finish_layout()
		},
	)
}

@(test)
table_row_unmount_skips_layout_node :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Table_Row(
				{
					config = {
						id = "table_row-gone",
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
					unmount = true,
					on_unmount = proc(frame_state: Table_Row_State) -> o.Mount {
						_ = frame_state
						return .COMPLETED
					},
				},
			)
			_, ok := widget_test_layout_node("table_row-gone")
			testing.expect(t, !ok)
			widget_test_finish_layout()
		},
	)
}

@(test)
table_row_config_override_preserves_kind :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			props := Table_Row_Props {
				config = {
					id = "table_row-styled",
					background = set.Background(o.Color.PRIMARY),
				},
			}
			frame := Table_Row_State{}
			config := widget_config(props, &frame, table_row_theme_base)
			testing.expect(t, config.kind == .TABLE_ROW)
			testing.expect_value(t, config.id, "table_row-styled")
		},
	)
}
