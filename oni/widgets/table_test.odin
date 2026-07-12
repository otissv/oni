package widgets

import o ".."
import "core:testing"
import set "../set"

@(test)
table_theme_base_sets_kind_and_defaults :: proc(t: ^testing.T) {
	frame := Table_State{}
	base := table_theme_base(&frame)
	testing.expect(t, base.kind == .TABLE)
	testing.expect(t, base.direction.mode == .Value)
}

@(test)
table_layout_registers_node_id_and_kind :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Table(
				{
					config = {
						id = "table-1",
						width = set.Width(f32(80)),
						height = set.Height(f32(32)),
					},
				},
			)
			widget_test_finish_layout()

			expect_registered_id(t, "table-1")
			expect_layout_kind(t, "table-1", .TABLE)
		},
	)
}

@(test)
table_tabbable_registers_in_tab_order :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Table(
				{
					config = {
						id = "table-tab",
						tabbable = set.Bool(true),
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
				},
			)
			expect_in_tab_order(t, "table-tab", true)
			widget_test_finish_layout()
		},
	)
}

@(test)
table_disabled_skips_tab_order :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Table(
				{
					config = {
						id = "table-disabled",
						disabled = set.Bool(true),
						tabbable = set.Bool(true),
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
				},
			)
			expect_in_tab_order(t, "table-disabled", false)
			widget_test_finish_layout()
		},
	)
}

@(test)
table_unmount_skips_layout_node :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Table(
				{
					config = {
						id = "table-gone",
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
					unmount = true,
					on_unmount = proc(frame_state: Table_State) -> o.Mount {
						_ = frame_state
						return .COMPLETED
					},
				},
			)
			_, ok := widget_test_layout_node("table-gone")
			testing.expect(t, !ok)
			widget_test_finish_layout()
		},
	)
}

@(test)
table_config_override_preserves_kind :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			props := Table_Props {
				config = {
					id = "table-styled",
					background = set.Background(o.Color.PRIMARY),
				},
			}
			frame := Table_State{}
			config := widget_config(props, &frame, table_theme_base)
			testing.expect(t, config.kind == .TABLE)
			testing.expect_value(t, config.id, "table-styled")
		},
	)
}
