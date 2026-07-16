package widgets

import o ".."
import "core:testing"
import set "../set"

@(private)
popover_clicks: int
@(private)
popover_enters: int
@(private)
popover_child_seen: int
@(private)
popover_mounts: int
@(private)
popover_unmounts: int
@(private)
popover_focuses: int
@(private)
popover_blurs: int

@(test)
popover_theme_base_sets_kind_and_popover_space :: proc(t: ^testing.T) {
	frame := Popover_State{}
	base := popover_theme_base(&frame)
	testing.expect(t, base.kind == .RECT)
	testing.expect(t, base.space.mode == .Value)
	testing.expect(t, base.space.value.(o.Draw_Space) == .POPOVER)
}

@(test)
popover_forces_popover_space_over_user_override :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Popover(
				{
					config = {
						id = "popover-forced-space",
						space = set.Space(.SCREEN),
						width = set.Width(f32(80)),
						height = set.Height(f32(40)),
					},
				},
			)
			widget_test_finish_layout()

			node, ok := widget_test_layout_node("popover-forced-space")
			testing.expect(t, ok)
			if !ok do return
			testing.expect(t, node.space == .POPOVER)
			testing.expect(t, node.config.space == .POPOVER)
			testing.expect(t, node.kind == .RECT)
		},
	)
}

@(test)
popover_layout_registers_node_id_and_kind :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Popover(
				{
					config = {
						id = "popover-1",
						width = set.Width(f32(80)),
						height = set.Height(f32(32)),
					},
				},
			)
			widget_test_finish_layout()

			expect_registered_id(t, "popover-1")
			expect_layout_kind(t, "popover-1", .RECT)
		},
	)
}

@(test)
popover_joins_paint_list_popover :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Rectangle(
				{
					config = {
						id = "screen-under",
						width = set.Width(f32(100)),
						height = set.Height(f32(100)),
					},
				},
			)
			Popover(
				{
					config = {
						id = "popover-paint",
						width = set.Width(f32(100)),
						height = set.Height(f32(100)),
					},
				},
			)
			widget_test_finish_layout()
			widget_test_begin_draw()

			node, ok := widget_test_layout_node("popover-paint")
			testing.expect(t, ok)
			if !ok do return

			found := false
			for idx in o.state.ui.layout.paint_list_popover {
				if &o.state.ui.layout.nodes[idx] == node {
					found = true
					break
				}
			}
			testing.expect(t, found)
		},
	)
}

@(test)
popover_tabbable_registers_in_tab_order :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Popover(
				{
					config = {
						id = "popover-tab",
						tabbable = set.Bool(true),
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
				},
			)
			expect_in_tab_order(t, "popover-tab", true)
			widget_test_finish_layout()
		},
	)
}

@(test)
popover_disabled_skips_tab_order :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Popover(
				{
					config = {
						id = "popover-disabled",
						disabled = set.Bool(true),
						tabbable = set.Bool(true),
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
				},
			)
			expect_in_tab_order(t, "popover-disabled", false)
			widget_test_finish_layout()
		},
	)
}

@(test)
popover_unmount_skips_layout_node :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			popover_unmounts = 0
			Popover(
				{
					config = {
						id = "popover-gone",
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
					unmount = true,
					on_unmount = proc(frame_state: Popover_State) -> o.Mount {
						_ = frame_state
						popover_unmounts += 1
						return .COMPLETED
					},
				},
			)
			_, ok := widget_test_layout_node("popover-gone")
			testing.expect(t, !ok)
			testing.expect_value(t, popover_unmounts, 1)
			widget_test_finish_layout()
		},
	)
}

@(test)
popover_draw_skips_without_layout_node :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Popover(
				{
					config = {
						id = "popover-draw-gone",
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
					unmount = true,
					on_unmount = proc(frame_state: Popover_State) -> o.Mount {
						_ = frame_state
						return .COMPLETED
					},
				},
			)
			widget_test_finish_layout()
			widget_test_begin_draw()

			popover_clicks = 0
			Popover(
				{
					config = {
						id = "popover-draw-gone",
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
					unmount = true,
					on_click = proc(event: Popover_Event) {
						_ = event
						popover_clicks += 1
					},
				},
			)
			testing.expect_value(t, popover_clicks, 0)
		},
	)
}

@(test)
popover_visibility_none_excludes_from_flex :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Popover(
				{
					config = {
						id = "none-row",
						direction = set.Direction(.HORIZONTAL),
						gap_x = set.Gap_X(u16(10)),
						width = set.Width(f32(400)),
						height = set.Height(f32(50)),
					},
					child = proc(_: Popover_State) {
						Popover(
							{
								config = {
									id = "none-a",
									width = set.Width(f32(100)),
									height = set.Height(f32(50)),
								},
							},
						)
						Popover(
							{
								config = {
									id = "none-mid",
									visibility = set.Visibility(.NONE),
									width = set.Width(f32(100)),
									height = set.Height(f32(50)),
								},
							},
						)
						Popover(
							{
								config = {
									id = "none-b",
									width = set.Width(f32(100)),
									height = set.Height(f32(50)),
								},
							},
						)
					},
				},
			)
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
		},
	)
}

@(test)
popover_children_inherit_popover_space :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Popover(
				{
					config = {
						id = "popover-parent",
						width = set.Width(f32(120)),
						height = set.Height(f32(80)),
					},
					child = proc(_: Popover_State) {
						Rectangle(
							{
								config = {
									id = "popover-child",
									width = set.Width(f32(40)),
									height = set.Height(f32(20)),
								},
							},
						)
					},
				},
			)
			widget_test_finish_layout()

			parent, parent_ok := widget_test_layout_node("popover-parent")
			testing.expect(t, parent_ok)
			if !parent_ok do return
			testing.expect(t, parent.space == .POPOVER)
			testing.expect_value(t, len(parent.child_indices), 1)
			if len(parent.child_indices) == 0 do return

			child := &o.state.ui.layout.nodes[parent.child_indices[0]]
			testing.expect(t, child.space == .POPOVER)
		},
	)
}

@(test)
popover_draw_runs_chrome_and_child :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			popover_child_seen = 0

			widget_test_begin_layout()
			defer widget_test_end_frame()

			Popover(
				{
					config = {
						id = "popover-draw",
						width = set.Width(f32(100)),
						height = set.Height(f32(60)),
						background = set.Background(o.Color.PRIMARY),
						border = set.Border(f32(2)),
						border_color = set.Colors(o.Color.BLACK),
						radius = set.Radius(8),
						opacity = set.F32(0.9),
					},
					child = proc(_: Popover_State) {
						popover_child_seen += 1
					},
				},
			)
			widget_test_finish_layout()
			widget_test_begin_draw()

			Popover(
				{
					config = {
						id = "popover-draw",
						width = set.Width(f32(100)),
						height = set.Height(f32(60)),
						background = set.Background(o.Color.PRIMARY),
						border = set.Border(f32(2)),
						border_color = set.Colors(o.Color.BLACK),
						radius = set.Radius(8),
						opacity = set.F32(0.9),
					},
					child = proc(_: Popover_State) {
						popover_child_seen += 1
					},
				},
			)

			testing.expect_value(t, popover_child_seen, 2)
		},
	)
}

@(test)
popover_draw_skips_rectangle_when_paint_skip :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			popover_child_seen = 0

			widget_test_begin_layout()
			defer widget_test_end_frame()

			Popover(
				{
					config = {
						id = "popover-paint-skip",
						width = set.Width(f32(50)),
						height = set.Height(f32(30)),
						background = set.Background(o.Color.PRIMARY),
					},
					child = proc(_: Popover_State) {
						popover_child_seen += 1
					},
				},
			)
			widget_test_finish_layout()

			node, ok := widget_test_layout_node("popover-paint-skip")
			testing.expect(t, ok)
			if !ok do return
			node.paint_skip = true

			widget_test_begin_draw()
			Popover(
				{
					config = {
						id = "popover-paint-skip",
						width = set.Width(f32(50)),
						height = set.Height(f32(30)),
						background = set.Background(o.Color.PRIMARY),
					},
					child = proc(_: Popover_State) {
						popover_child_seen += 1
					},
				},
			)
			testing.expect_value(t, popover_child_seen, 2)
		},
	)
}

@(test)
popover_auto_focus_applies_focus :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Popover(
				{
					config = {
						id = "popover-af",
						auto_focus = set.Bool(true),
						tabbable = set.Bool(true),
						width = set.Width(f32(60)),
						height = set.Height(f32(30)),
					},
				},
			)

			key, ok := GetElementById("popover-af")
			testing.expect(t, ok)
			if ok {
				testing.expect_value(t, o.w_ctx.auto_focused_id, key)
				testing.expect_value(t, o.w_ctx.focused_id, key)
			}
			widget_test_finish_layout()
		},
	)
}

@(test)
popover_click_interaction_on_draw :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			popover_clicks = 0
			popover_enters = 0

			widget_test_begin_layout()
			defer widget_test_end_frame()

			popover_draw_interactive()
			widget_test_finish_layout()

			node, ok := widget_test_layout_node("popover-click")
			testing.expect(t, ok)
			if !ok do return
			node.rect = {0, 0, 80, 40}

			o.w_ctx.mouse_x = 20
			o.w_ctx.mouse_y = 10
			widget_test_begin_draw()

			o.w_ctx.left_mouse.pressed = true
			o.w_ctx.left_mouse.down = true
			popover_draw_interactive()

			o.w_ctx.left_mouse.pressed = false
			o.w_ctx.left_mouse.down = false
			o.w_ctx.left_mouse.released = true
			popover_draw_interactive()

			testing.expect(t, popover_enters >= 1)
			testing.expect_value(t, popover_clicks, 1)
		},
	)
}

@(private)
popover_draw_interactive :: proc() {
	Popover(
		{
			config = {
				id = "popover-click",
				width = set.Width(f32(80)),
				height = set.Height(f32(40)),
			},
			on_mouse_enter = proc(event: Popover_Event) {
				_ = event
				popover_enters += 1
			},
			on_click = proc(event: Popover_Event) {
				_ = event
				popover_clicks += 1
			},
		},
	)
}

@(test)
popover_hits_above_screen_sibling :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Rectangle(
				{
					config = {
						id = "hit-screen",
						width = set.Width(f32(100)),
						height = set.Height(f32(100)),
					},
				},
			)
			Popover(
				{
					config = {
						id = "hit-popover",
						width = set.Width(f32(100)),
						height = set.Height(f32(100)),
					},
				},
			)
			widget_test_finish_layout()

			screen, screen_ok := widget_test_layout_node("hit-screen")
			popover, popover_ok := widget_test_layout_node("hit-popover")
			testing.expect(t, screen_ok && popover_ok)
			if !screen_ok || !popover_ok do return
			screen.rect = {0, 0, 100, 100}
			popover.rect = {0, 0, 100, 100}

			o.w_ctx.mouse_x = 40
			o.w_ctx.mouse_y = 40
			widget_test_begin_draw()

			testing.expect(t, o.w_ctx.pointer_hit_valid)
			testing.expect(t, o.w_ctx.pointer_hit_ui_id == popover.ui_id)
		},
	)
}

@(test)
popover_mount_lifecycle :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			popover_mounts = 0

			widget_test_begin_layout()
			defer widget_test_end_frame()

			Popover(
				{
					config = {
						id = "popover-mount",
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
					on_mount = proc(frame_state: Popover_State) -> o.Mount {
						_ = frame_state
						popover_mounts += 1
						return .COMPLETED
					},
				},
			)
			testing.expect_value(t, popover_mounts, 1)
			expect_registered_id(t, "popover-mount")
			widget_test_finish_layout()
		},
	)
}

@(test)
popover_empty_id_still_layouts :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			before := len(o.state.ui.layout.nodes)
			Popover(
				{
					config = {
						width = set.Width(f32(40)),
						height = set.Height(f32(20)),
					},
				},
			)
			widget_test_finish_layout()
			testing.expect(t, len(o.state.ui.layout.nodes) > before)

			found_popover := false
			for &node in o.state.ui.layout.nodes {
				if node.space == .POPOVER {
					found_popover = true
					break
				}
			}
			testing.expect(t, found_popover)
		},
	)
}

@(test)
popover_config_override_keeps_kind :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			props := Popover_Props {
				config = {
					id = "popover-styled",
					background = set.Background(o.Color.PRIMARY),
					space = set.Space(.ARTBOARD),
				},
			}
			props.config.space = set.Space(.POPOVER)
			frame := Popover_State{}
			config := widget_config(props, &frame, popover_theme_base)
			testing.expect(t, config.kind == .RECT)
			testing.expect(t, config.space == .POPOVER)
			testing.expect_value(t, config.id, "popover-styled")
		},
	)
}

@(test)
popover_tab_focus_and_blur_handlers :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			popover_focuses = 0
			popover_blurs = 0

			widget_test_begin_layout()
			defer widget_test_end_frame()

			Popover(
				{
					config = {
						id = "popover-tab-focus",
						tabbable = set.Bool(true),
						width = set.Width(f32(60)),
						height = set.Height(f32(30)),
					},
					on_focus = proc(event: Popover_Event) {
						_ = event
						popover_focuses += 1
					},
					on_blur = proc(event: Popover_Event) {
						_ = event
						popover_blurs += 1
					},
				},
			)
			key, ok := GetElementById("popover-tab-focus")
			testing.expect(t, ok)
			if !ok do return

			widget_test_finish_layout()
			widget_test_begin_draw()

			o.w_ctx.tab_focus_changed = true
			o.w_ctx.focused_id = key
			o.w_ctx.tab_focus_previous_id = "other"

			Popover(
				{
					config = {
						id = "popover-tab-focus",
						tabbable = set.Bool(true),
						width = set.Width(f32(60)),
						height = set.Height(f32(30)),
					},
					on_focus = proc(event: Popover_Event) {
						_ = event
						popover_focuses += 1
					},
					on_blur = proc(event: Popover_Event) {
						_ = event
						popover_blurs += 1
					},
				},
			)
			testing.expect_value(t, popover_focuses, 1)

			o.w_ctx.tab_focus_changed = true
			o.w_ctx.focused_id = "other"
			o.w_ctx.tab_focus_previous_id = key

			Popover(
				{
					config = {
						id = "popover-tab-focus",
						tabbable = set.Bool(true),
						width = set.Width(f32(60)),
						height = set.Height(f32(30)),
					},
					on_focus = proc(event: Popover_Event) {
						_ = event
						popover_focuses += 1
					},
					on_blur = proc(event: Popover_Event) {
						_ = event
						popover_blurs += 1
					},
				},
			)
			testing.expect_value(t, popover_blurs, 1)
		},
	)
}
