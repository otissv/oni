package widgets

import o ".."
import "core:testing"
import set "../set"

@(test)
table_body_theme_base_sets_kind_and_defaults :: proc(t: ^testing.T) {
	frame := Table_Body_State{}
	base := table_body_theme_base(&frame)
	testing.expect(t, base.kind == .TABLE_BODY)
}

@(test)
table_body_layout_registers_node_id_and_kind :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Table_Body(
				{
					config = {
						id = "table_body-1",
						width = set.Width(f32(80)),
						height = set.Height(f32(32)),
					},
				},
			)
			widget_test_finish_layout()

			expect_registered_id(t, "table_body-1")
			expect_layout_kind(t, "table_body-1", .TABLE_BODY)
		},
	)
}

@(test)
table_body_tabbable_registers_in_tab_order :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Table_Body(
				{
					config = {
						id = "table_body-tab",
						tabbable = set.Bool(true),
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
				},
			)
			expect_in_tab_order(t, "table_body-tab", true)
			widget_test_finish_layout()
		},
	)
}

@(test)
table_body_disabled_skips_tab_order :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Table_Body(
				{
					config = {
						id = "table_body-disabled",
						disabled = set.Bool(true),
						tabbable = set.Bool(true),
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
				},
			)
			expect_in_tab_order(t, "table_body-disabled", false)
			widget_test_finish_layout()
		},
	)
}

@(test)
table_body_unmount_skips_layout_node :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Table_Body(
				{
					config = {
						id = "table_body-gone",
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
					unmount = true,
					on_unmount = proc(frame_state: Table_Body_State) -> o.Mount {
						_ = frame_state
						return .COMPLETED
					},
				},
			)
			_, ok := widget_test_layout_node("table_body-gone")
			testing.expect(t, !ok)
			widget_test_finish_layout()
		},
	)
}

@(test)
table_body_config_override_preserves_kind :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			props := Table_Body_Props {
				config = {
					id = "table_body-styled",
					background = set.Background(o.Color.PRIMARY),
				},
			}
			frame := Table_Body_State{}
			config := widget_config(props, &frame, table_body_theme_base)
			testing.expect(t, config.kind == .TABLE_BODY)
			testing.expect_value(t, config.id, "table_body-styled")
		},
	)
}
