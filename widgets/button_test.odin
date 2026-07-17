package oni_widgets

import o ".."
import set "../set"
import "core:testing"

@(test)
button_theme_base_sets_kind_and_defaults :: proc(t: ^testing.T) {
	frame := Button_State{}
	base := button_theme_base(&frame)
	testing.expect(t, base.kind == .BUTTON)
}

@(test)
button_layout_registers_node_id_and_kind :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Button(
			{config = {id = "button-1", width = set.Width(f32(80)), height = set.Height(f32(32))}},
		)
		widget_test_finish_layout()

		expect_registered_id(t, "button-1")
		expect_layout_kind(t, "button-1", .BUTTON)
	})
}

@(test)
button_tabbable_registers_in_tab_order :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Button(
			{
				config = {
					id = "button-tab",
					tabbable = set.Bool(true),
					width = set.Width(f32(40)),
					height = set.Height(f32(20)),
				},
			},
		)
		expect_in_tab_order(t, "button-tab", true)
		widget_test_finish_layout()
	})
}

@(test)
button_disabled_skips_tab_order :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Button(
			{
				config = {
					id = "button-disabled",
					disabled = set.Bool(true),
					tabbable = set.Bool(true),
					width = set.Width(f32(40)),
					height = set.Height(f32(20)),
				},
			},
		)
		expect_in_tab_order(t, "button-disabled", false)
		widget_test_finish_layout()
	})
}

@(test)
button_unmount_skips_layout_node :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Button({
			config = {
				id = "button-gone",
				width = set.Width(f32(40)),
				height = set.Height(f32(20)),
			},
			unmount = true,
			on_unmount = proc(frame_state: Button_State) -> o.Mount {
				_ = frame_state
				return .COMPLETED
			},
		})
		_, ok := widget_test_layout_node("button-gone")
		testing.expect(t, !ok)
		widget_test_finish_layout()
	})
}

@(test)
button_config_override_preserves_kind :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		props := Button_Props {
			config = {id = "button-styled", background = set.Background(o.Color.PRIMARY)},
		}
		frame := Button_State{}
		config := widget_config(props, &frame, button_theme_base)
		testing.expect(t, config.kind == .BUTTON)
		testing.expect_value(t, config.id, "button-styled")
	})
}
