package oni_widgets

import o ".."
import set "../set"
import "core:testing"

@(private)
collapsible_test_open := false

@(private)
collapsible_test_open_changes := 0

@(private)
collapsible_test_content_runs := 0

@(private)
collapsible_test_user_clicks := 0

@(private)
collapsible_test_saw_closed := false

@(private)
collapsible_test_saw_open := false

@(private)
collapsible_test_reset :: proc() {
	collapsible_test_open = false
	collapsible_test_open_changes = 0
	collapsible_test_content_runs = 0
	collapsible_test_user_clicks = 0
	collapsible_test_saw_closed = false
	collapsible_test_saw_open = false
}

@(private)
collapsible_test_tree :: proc() {
	Collapsible({
		config = {id = "collapse-root", open = collapsible_test_open},
		on_open_change = proc(open: bool) {
			collapsible_test_open = open
			collapsible_test_open_changes += 1
		},
		child = proc(_: Collapsible_State) {
			Collapsible_Trigger({
				config = {
					id = "collapse-trigger",
					width = set.Width(f32(120)),
					height = set.Height(f32(32)),
				},
				on_click = proc(_: Collapsible_Trigger_Event) {
					collapsible_test_user_clicks += 1
				},
			})
			Collapsible_Content({
				config = {
					id = "collapse-content",
					width = set.Width(f32(120)),
					height = set.Height(f32(48)),
				},
				child = proc(_: Collapsible_Content_State) {
					collapsible_test_content_runs += 1
				},
			})
		},
	})
}

@(private)
collapsible_test_find_kind_under :: proc(
	root: ^o.Layout_Node,
	kind: o.Widget_Kind,
) -> (
	node: ^o.Layout_Node,
	ok: bool,
) {
	if root == nil {
		return
	}

	stack: [64]int
	depth := 0

	for child_index in root.child_indices {
		if depth >= len(stack) {
			break
		}

		stack[depth] = child_index
		depth += 1
	}

	for depth > 0 {
		depth -= 1
		candidate := &o.state.ui.layout.nodes[stack[depth]]

		if candidate.kind == kind {
			return candidate, true
		}

		for child_index in candidate.child_indices {
			if depth >= len(stack) {
				break
			}

			stack[depth] = child_index
			depth += 1
		}
	}

	return
}

@(private)
collapsible_test_count_kind :: proc(kind: o.Widget_Kind) -> int {
	count := 0

	for &n in o.state.ui.layout.nodes {
		if n.kind == kind {
			count += 1
		}
	}

	return count
}

@(test)
collapsible_theme_base_sets_kinds :: proc(t: ^testing.T) {
	root := Collapsible_State{}
	testing.expect(t, collapsible_root_theme_base(&root).kind == .COLLAPSIBLE)

	trigger := Collapsible_Trigger_State{}
	testing.expect(t, collapsible_trigger_theme_base(&trigger).kind == .COLLAPSIBLE_TRIGGER)

	content_open := Collapsible_Content_State {
		open = true,
	}
	base_open := collapsible_content_theme_base(&content_open)
	testing.expect(t, base_open.kind == .COLLAPSIBLE_CONTENT)
	testing.expect(t, base_open.visibility.mode == .Value)
	testing.expect(t, base_open.visibility.value == .VISIBLE)

	content_closed := Collapsible_Content_State {
		open = false,
	}
	base_closed := collapsible_content_theme_base(&content_closed)
	testing.expect(t, base_closed.visibility.mode == .Value)
	testing.expect(t, base_closed.visibility.value == .NONE)
}

@(test)
collapsible_root_layout_registers_kind :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Collapsible({
			config = {id = "collapse-kind", open = false},
			child = proc(_: Collapsible_State) {},
		})
		widget_test_finish_layout()

		expect_registered_id(t, "collapse-kind")
		expect_layout_kind(t, "collapse-kind", .COLLAPSIBLE)
	})
}

@(test)
collapsible_content_skips_layout_when_closed :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		collapsible_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		collapsible_test_tree()
		expect_registered_id(t, "collapse-trigger")
		expect_in_tab_order(t, "collapse-trigger", true)
		widget_test_finish_layout()

		root, root_ok := widget_test_layout_node("collapse-root")
		testing.expect(t, root_ok)

		if !root_ok {
			return
		}

		_, trigger_ok := collapsible_test_find_kind_under(root, .COLLAPSIBLE_TRIGGER)
		testing.expect(t, trigger_ok)
		_, content_ok := collapsible_test_find_kind_under(root, .COLLAPSIBLE_CONTENT)
		testing.expect(t, !content_ok)
		testing.expect_value(t, collapsible_test_content_runs, 0)
		testing.expect_value(t, collapsible_test_count_kind(.COLLAPSIBLE_CONTENT), 0)
	})
}

@(test)
collapsible_content_layouts_when_open :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		collapsible_test_reset()
		collapsible_test_open = true
		widget_test_begin_layout()
		defer widget_test_end_frame()

		collapsible_test_tree()
		expect_registered_id(t, "collapse-content")
		widget_test_finish_layout()

		root, root_ok := widget_test_layout_node("collapse-root")
		testing.expect(t, root_ok)

		if !root_ok {
			return
		}

		content, content_ok := collapsible_test_find_kind_under(root, .COLLAPSIBLE_CONTENT)
		testing.expect(t, content_ok)

		if content_ok {
			testing.expect(t, content.kind == .COLLAPSIBLE_CONTENT)
		}

		testing.expect_value(t, collapsible_test_content_runs, 1)
	})
}

@(test)
collapsible_content_force_mount_keeps_closed_panel :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		collapsible_test_content_runs = 0
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Collapsible({
			config = {id = "collapse-force", open = false},
			child = proc(_: Collapsible_State) {
				Collapsible_Content({
					config = {
						id = "collapse-force-content",
						force_mount = true,
						width = set.Width(f32(80)),
						height = set.Height(f32(40)),
					},
					child = proc(_: Collapsible_Content_State) {
						collapsible_test_content_runs += 1
					},
				})
			},
		})
		expect_registered_id(t, "collapse-force-content")
		widget_test_finish_layout()

		root, root_ok := widget_test_layout_node("collapse-force")
		testing.expect(t, root_ok)

		if !root_ok {
			return
		}

		content, content_ok := collapsible_test_find_kind_under(root, .COLLAPSIBLE_CONTENT)
		testing.expect(t, content_ok)

		if content_ok {
			testing.expect(t, content.config.visibility == .HIDDEN)
		}

		testing.expect_value(t, collapsible_test_content_runs, 1)
	})
}

@(test)
collapsible_content_outside_root_stays_closed :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Collapsible_Content({
			config = {
				id = "orphan-content",
				width = set.Width(f32(80)),
				height = set.Height(f32(40)),
			},
		})
		widget_test_finish_layout()

		testing.expect_value(t, collapsible_test_count_kind(.COLLAPSIBLE_CONTENT), 0)
	})
}

@(test)
collapsible_trigger_click_toggles_open :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		collapsible_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		collapsible_test_tree()
		widget_test_finish_layout()

		root, root_ok := widget_test_layout_node("collapse-root")
		testing.expect(t, root_ok)

		if !root_ok {
			return
		}

		trigger, trigger_ok := collapsible_test_find_kind_under(root, .COLLAPSIBLE_TRIGGER)
		testing.expect(t, trigger_ok)

		if !trigger_ok {
			return
		}

		trigger.rect = {0, 0, 120, 32}
		o.w_ctx.mouse_x = 20
		o.w_ctx.mouse_y = 10
		widget_test_begin_draw()

		o.w_ctx.left_mouse.pressed = true
		o.w_ctx.left_mouse.down = true
		collapsible_test_tree()

		o.w_ctx.left_mouse.pressed = false
		o.w_ctx.left_mouse.down = false
		o.w_ctx.left_mouse.released = true
		collapsible_test_tree()

		testing.expect(t, collapsible_test_open)
		testing.expect_value(t, collapsible_test_open_changes, 1)
		testing.expect_value(t, collapsible_test_user_clicks, 1)
	})
}

@(test)
collapsible_disabled_root_blocks_toggle :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		collapsible_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		disabled_tree :: proc() {
			Collapsible({
				config = {
					id = "collapse-disabled",
					open = false,
					disabled = set.Disabled(true),
				},
				on_open_change = proc(open: bool) {
					collapsible_test_open = open
					collapsible_test_open_changes += 1
				},
				child = proc(_: Collapsible_State) {
					Collapsible_Trigger({
						config = {
							id = "collapse-disabled-trigger",
							width = set.Width(f32(100)),
							height = set.Height(f32(28)),
						},
					})
				},
			})
		}

		disabled_tree()
		widget_test_finish_layout()

		root, root_ok := widget_test_layout_node("collapse-disabled")
		testing.expect(t, root_ok)

		if !root_ok {
			return
		}

		trigger, trigger_ok := collapsible_test_find_kind_under(root, .COLLAPSIBLE_TRIGGER)
		testing.expect(t, trigger_ok)

		if !trigger_ok {
			return
		}

		trigger.rect = {0, 0, 100, 28}
		o.w_ctx.mouse_x = 10
		o.w_ctx.mouse_y = 10
		widget_test_begin_draw()

		o.w_ctx.left_mouse.pressed = true
		o.w_ctx.left_mouse.down = true
		disabled_tree()

		o.w_ctx.left_mouse.pressed = false
		o.w_ctx.left_mouse.down = false
		o.w_ctx.left_mouse.released = true
		disabled_tree()

		testing.expect(t, !collapsible_test_open)
		testing.expect_value(t, collapsible_test_open_changes, 0)
	})
}

@(test)
collapsible_set_open_and_is_open_helpers :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		collapsible_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Collapsible({
			config = {id = "collapse-helpers", open = false},
			on_open_change = proc(open: bool) {
				collapsible_test_open = open
				collapsible_test_open_changes += 1
			},
			child = proc(_: Collapsible_State) {
				collapsible_test_saw_closed = !Collapsible_Is_Open()
				Collapsible_Set_Open(true)
				collapsible_test_saw_open = Collapsible_Is_Open()
			},
		})
		widget_test_finish_layout()

		testing.expect(t, collapsible_test_saw_closed)
		testing.expect(t, collapsible_test_saw_open)
		testing.expect(t, collapsible_test_open)
		testing.expect_value(t, collapsible_test_open_changes, 1)
	})
}

@(test)
collapsible_nested_roots_share_independent_open :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Collapsible({
			config = {id = "outer", open = true},
			child = proc(_: Collapsible_State) {
				Collapsible_Content({
					config = {
						id = "outer-content",
						width = set.Width(f32(100)),
						height = set.Height(f32(80)),
					},
					child = proc(_: Collapsible_Content_State) {
						Collapsible({
							config = {id = "inner", open = false},
							child = proc(_: Collapsible_State) {
								Collapsible_Content({
									config = {
										id = "inner-content",
										width = set.Width(f32(80)),
										height = set.Height(f32(40)),
									},
								})
							},
						})
					},
				})
			},
		})
		expect_registered_id(t, "outer-content")
		widget_test_finish_layout()

		outer, outer_ok := widget_test_layout_node("outer")
		testing.expect(t, outer_ok)

		if !outer_ok {
			return
		}

		_, outer_content_ok := collapsible_test_find_kind_under(outer, .COLLAPSIBLE_CONTENT)
		testing.expect(t, outer_content_ok)

		// Outer content + closed inner (no content node) => exactly one content kind.
		testing.expect_value(t, collapsible_test_count_kind(.COLLAPSIBLE_CONTENT), 1)
		testing.expect_value(t, collapsible_test_count_kind(.COLLAPSIBLE), 2)
	})
}

@(test)
collapsible_shutdown_clears_ctx_stack :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		Collapsible({
			config = {id = "shutdown-root", open = true},
			child = proc(_: Collapsible_State) {},
		})
		testing.expect(t, collapsible_ctx_depth == 0)
		widget_test_finish_layout()
		widget_test_end_frame()

		collapsible_ctx_push({open = true})
		testing.expect_value(t, collapsible_ctx_depth, 1)
		collapsible_shutdown()
		testing.expect_value(t, collapsible_ctx_depth, 0)
	})
}

@(test)
collapsible_trigger_tabbable_by_default :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Collapsible({
			config = {id = "tab-root", open = false},
			child = proc(_: Collapsible_State) {
				Collapsible_Trigger({
					config = {
						id = "tab-trigger",
						width = set.Width(f32(80)),
						height = set.Height(f32(24)),
					},
				})
			},
		})
		expect_in_tab_order(t, "tab-trigger", true)
		widget_test_finish_layout()
	})
}
