package oni_widgets

import o ".."
import set "../set"
import "core:testing"

@(test)
rectangle_theme_base_sets_kind_and_defaults :: proc(t: ^testing.T) {
	frame := Rectangle_State{}
	base := rect_theme_base(&frame)
	testing.expect(t, base.kind == .RECT)
}

@(test)
rectangle_layout_registers_node_id_and_kind :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
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
	})
}

@(test)
rectangle_tabbable_registers_in_tab_order :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
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
	})
}

@(test)
rectangle_disabled_skips_tab_order :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
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
	})
}

@(test)
rectangle_unmount_skips_layout_node :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Rectangle({
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
		})
		_, ok := widget_test_layout_node("rectangle-gone")
		testing.expect(t, !ok)
		widget_test_finish_layout()
	})
}

@(test)
rectangle_visibility_none_excludes_from_flex :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Rectangle({
			config = {id = "none-row", direction = set.Direction(.HORIZONTAL), gap_x = set.Gap_X(u16(10)), width = set.Width(f32(400)), height = set.Height(f32(50))},
			child = proc(_: Rectangle_State) {
				Rectangle({config = {id = "none-a", width = set.Width(f32(100)), height = set.Height(f32(50))}})
				Rectangle({config = {id = "none-mid", visibility = set.Visibility(.NONE), width = set.Width(f32(100)), height = set.Height(f32(50))}})
				Rectangle({config = {id = "none-b", width = set.Width(f32(100)), height = set.Height(f32(50))}})
			},
		})
		widget_test_finish_layout()

		row, row_ok := widget_test_layout_node("none-row")
		testing.expect(t, row_ok)
		if !row_ok do return

		testing.expect_value(t, len(row.child_indices), 2)
		a := &o.state.ui.layout.nodes[row.child_indices[0]]
		b := &o.state.ui.layout.nodes[row.child_indices[1]]
		expect_close(t, a.rect.x, 0)
		expect_close(t, a.rect.w, 100)
		expect_close(t, b.rect.x, 110)
		expect_close(t, b.rect.w, 100)
		testing.expect_value(t, len(o.state.ui.layout.nodes), 3)
	})
}

@(test)
rectangle_config_override_preserves_kind :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		props := Rectangle_Props {
			config = {id = "rectangle-styled", background = set.Background(o.Color.PRIMARY)},
		}
		frame := Rectangle_State{}
		config := widget_config(props, &frame, rect_theme_base)
		testing.expect(t, config.kind == .RECT)
		testing.expect_value(t, config.id, "rectangle-styled")
	})
}
