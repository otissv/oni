package widgets

import o ".."
import "core:testing"
import set "../set"

@(test)
rectangle_theme_base_sets_kind_and_defaults :: proc(t: ^testing.T) {
	frame := Rectangle_State{}
	base := rect_theme_base(&frame)
	testing.expect(t, base.kind == .RECT)
}

@(test)
rectangle_layout_registers_node_id_and_kind :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Rectangle(
				{
					config = {
						id = "rectangle-1",
						width = set.Width(f32(80)),
						height = set.Height(f32(32)),
					},
				},
			)
			widget_test_finish_layout()

			expect_registered_id(t, "rectangle-1")
			expect_layout_kind(t, "rectangle-1", .RECT)
		},
	)
}

@(test)
rectangle_tabbable_registers_in_tab_order :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Rectangle(
				{
					config = {
						id = "rectangle-tab",
						tabbable = set.Bool(true),
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
				},
			)
			expect_in_tab_order(t, "rectangle-tab", true)
			widget_test_finish_layout()
		},
	)
}

@(test)
rectangle_disabled_skips_tab_order :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Rectangle(
				{
					config = {
						id = "rectangle-disabled",
						disabled = set.Bool(true),
						tabbable = set.Bool(true),
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
				},
			)
			expect_in_tab_order(t, "rectangle-disabled", false)
			widget_test_finish_layout()
		},
	)
}

@(test)
rectangle_unmount_skips_layout_node :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Rectangle(
				{
					config = {
						id = "rectangle-gone",
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
					unmount = true,
					on_unmount = proc(frame_state: Rectangle_State) -> o.Mount {
						_ = frame_state
						return .COMPLETED
					},
				},
			)
			_, ok := widget_test_layout_node("rectangle-gone")
			testing.expect(t, !ok)
			widget_test_finish_layout()
		},
	)
}

@(test)
rectangle_config_override_preserves_kind :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			props := Rectangle_Props {
				config = {
					id = "rectangle-styled",
					background = set.Background(o.Color.PRIMARY),
				},
			}
			frame := Rectangle_State{}
			config := widget_config(props, &frame, rect_theme_base)
			testing.expect(t, config.kind == .RECT)
			testing.expect_value(t, config.id, "rectangle-styled")
		},
	)
}
