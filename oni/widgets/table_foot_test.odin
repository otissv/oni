package widgets

import o ".."
import "core:testing"
import set "../set"

@(test)
table_foot_theme_base_sets_kind_and_defaults :: proc(t: ^testing.T) {
	frame := Table_Foot_State{}
	base := table_foot_theme_base(&frame)
	testing.expect(t, base.kind == .TABLE_FOOT)
}

@(test)
table_foot_layout_registers_node_id_and_kind :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Table_Foot(
				{
					config = {
						id = "table_foot-1",
						width = set.Width(f32(80)),
						height = set.Height(f32(32)),
					},
				},
			)
			widget_test_finish_layout()

			expect_registered_id(t, "table_foot-1")
			expect_layout_kind(t, "table_foot-1", .TABLE_FOOT)
		},
	)
}

@(test)
table_foot_tabbable_registers_in_tab_order :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Table_Foot(
				{
					config = {
						id = "table_foot-tab",
						tabbable = set.Bool(true),
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
				},
			)
			expect_in_tab_order(t, "table_foot-tab", true)
			widget_test_finish_layout()
		},
	)
}

@(test)
table_foot_disabled_skips_tab_order :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Table_Foot(
				{
					config = {
						id = "table_foot-disabled",
						disabled = set.Bool(true),
						tabbable = set.Bool(true),
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
				},
			)
			expect_in_tab_order(t, "table_foot-disabled", false)
			widget_test_finish_layout()
		},
	)
}

@(test)
table_foot_unmount_skips_layout_node :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Table_Foot(
				{
					config = {
						id = "table_foot-gone",
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
					unmount = true,
					on_unmount = proc(frame_state: Table_Foot_State) -> o.Mount {
						_ = frame_state
						return .COMPLETED
					},
				},
			)
			_, ok := widget_test_layout_node("table_foot-gone")
			testing.expect(t, !ok)
			widget_test_finish_layout()
		},
	)
}

@(test)
table_foot_config_override_preserves_kind :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			props := Table_Foot_Props {
				config = {
					id = "table_foot-styled",
					background = set.Background(o.Color.PRIMARY),
				},
			}
			frame := Table_Foot_State{}
			config := widget_config(props, &frame, table_foot_theme_base)
			testing.expect(t, config.kind == .TABLE_FOOT)
			testing.expect_value(t, config.id, "table_foot-styled")
		},
	)
}
