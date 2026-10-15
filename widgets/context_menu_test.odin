package oni_widgets

import o ".."
import set "../set"
import "core:testing"

@(private)
context_menu_test_open := false

@(private)
context_menu_test_open_changes := 0

@(private)
context_menu_test_content_runs := 0

@(private)
context_menu_test_item_clicks := 0

@(private)
context_menu_test_user_contextmenus := 0

@(private)
context_menu_test_reset :: proc() {
	context_menu_test_open = false
	context_menu_test_open_changes = 0
	context_menu_test_content_runs = 0
	context_menu_test_item_clicks = 0
	context_menu_test_user_contextmenus = 0
}

@(private)
context_menu_test_tree :: proc() {
	Context_Menu({
		config = {id = "ctx-root", open = context_menu_test_open},
		on_open_change = proc(open: bool) {
			context_menu_test_open = open
			context_menu_test_open_changes += 1
		},
		child = proc(_: Context_Menu_State) {
			Context_Menu_Trigger({
				config = {
					id = "ctx-trigger",
					width = set.Width(f32(160)),
					height = set.Height(f32(40)),
				},
				on_contextmenu = proc(_: Context_Menu_Trigger_Event) {
					context_menu_test_user_contextmenus += 1
				},
			})
			Context_Menu_Content({
				config = {width = set.Width(f32(140)), height = set.Height(f32(80))},
				child = proc(_: Context_Menu_Content_Props_State) {
					context_menu_test_content_runs += 1
					Context_Menu_Item({
						config = {id = "ctx-item"},
						on_click = proc(_: Context_Menu_Item_Event) {
							context_menu_test_item_clicks += 1
						},
						child = proc(_: Context_Menu_Item_State) {},
					})
					Context_Menu_Separator({config = {id = "ctx-sep"}})
				},
			})
		},
	})
}

@(private)
context_menu_test_find_kind_under :: proc(
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
context_menu_test_count_kind :: proc(kind: o.Widget_Kind) -> int {
	count := 0

	for &n in o.state.ui.layout.nodes {
		if n.kind == kind {
			count += 1
		}
	}

	return count
}

@(test)
context_menu_theme_base_sets_kinds :: proc(t: ^testing.T) {
	root := Context_Menu_State{}
	testing.expect(t, context_menu_root_theme_base(&root).kind == .CONTEXT_MENU)

	trigger := Context_Menu_Trigger_State{}
	testing.expect(t, context_menu_trigger_theme_base(&trigger).kind == .CONTEXT_MENU_TRIGGER)

	content := Context_Menu_Content_Props_State{}
	testing.expect(t, context_menu_content_props_theme_base(&content).kind == .CONTEXT_MENU_CONTENT)

	item := Context_Menu_Item_State{}
	testing.expect(t, context_menu_item_theme_base(&item).kind == .CONTEXT_MENU_ITEM)

	sep := Context_Menu_Separator_State{}
	testing.expect(t, context_menu_separator_theme_base(&sep).kind == .CONTEXT_MENU_SEPARATOR)
}

@(test)
context_menu_root_layout_registers_kind :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Context_Menu({
			config = {id = "ctx-kind", open = false},
			child = proc(_: Context_Menu_State) {},
		})
		widget_test_finish_layout()

		expect_registered_id(t, "ctx-kind")
		expect_layout_kind(t, "ctx-kind", .CONTEXT_MENU)
	})
}

@(test)
context_menu_content_skips_layout_when_closed :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		context_menu_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		context_menu_test_tree()
		expect_registered_id(t, "ctx-trigger")
		expect_in_tab_order(t, "ctx-trigger", true)
		widget_test_finish_layout()

		root, root_ok := widget_test_layout_node("ctx-root")
		testing.expect(t, root_ok)

		if !root_ok {
			return
		}

		_, trigger_ok := context_menu_test_find_kind_under(root, .CONTEXT_MENU_TRIGGER)
		testing.expect(t, trigger_ok)
		testing.expect_value(t, context_menu_test_content_runs, 0)
		testing.expect_value(t, context_menu_test_count_kind(.CONTEXT_MENU_CONTENT), 0)
	})
}

@(test)
context_menu_content_layouts_when_open :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		context_menu_test_reset()
		context_menu_test_open = true
		widget_test_begin_layout()
		defer widget_test_end_frame()

		context_menu_test_tree()
		widget_test_finish_layout()

		found_popover := false

		for &n in o.state.ui.layout.nodes {
			if n.space == .POPOVER && n.kind == .RECT {
				found_popover = true
				break
			}
		}

		testing.expect(t, found_popover)
		testing.expect(t, context_menu_test_content_runs >= 1)
	})
}

@(test)
context_menu_trigger_opens_on_contextmenu :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		context_menu_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		context_menu_test_tree()
		widget_test_finish_layout()

		root, root_ok := widget_test_layout_node("ctx-root")
		testing.expect(t, root_ok)

		if !root_ok {
			return
		}

		trigger, trigger_ok := context_menu_test_find_kind_under(root, .CONTEXT_MENU_TRIGGER)
		testing.expect(t, trigger_ok)

		if !trigger_ok {
			return
		}

		trigger.rect = {10, 10, 160, 40}
		o.w_ctx.mouse_x = 40
		o.w_ctx.mouse_y = 25
		widget_test_begin_draw()

		o.w_ctx.right_mouse.pressed = true
		o.w_ctx.right_mouse.down = true
		context_menu_test_tree()

		testing.expect(t, context_menu_test_open)
		testing.expect(t, context_menu_test_open_changes >= 1)
		testing.expect(t, context_menu_test_user_contextmenus >= 1)
	})
}

@(test)
context_menu_escape_dismisses_when_open :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		context_menu_test_reset()
		context_menu_test_open = true
		widget_test_begin_layout()
		defer widget_test_end_frame()

		context_menu_test_tree()
		widget_test_finish_layout()
		widget_test_begin_draw()

		widget_test_press_shortcut(.ESCAPE)
		context_menu_test_tree()

		testing.expect(t, !context_menu_test_open)
		testing.expect(t, context_menu_test_open_changes >= 1)
	})
}

@(test)
context_menu_item_click_closes_menu :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		context_menu_test_reset()
		context_menu_test_open = true
		widget_test_begin_layout()
		defer widget_test_end_frame()

		context_menu_test_tree()
		widget_test_finish_layout()

		testing.expect(t, context_menu_test_count_kind(.CONTEXT_MENU_ITEM) >= 1)

		item: ^o.Layout_Node

		for i in 0 ..< len(o.state.ui.layout.nodes) {
			if o.state.ui.layout.nodes[i].kind == .CONTEXT_MENU_ITEM {
				item = &o.state.ui.layout.nodes[i]
				break
			}
		}

		testing.expect(t, item != nil)

		if item == nil {
			return
		}

		widget_test_begin_draw()
		o.w_ctx.mouse_x = item.rect.x + item.rect.w / 2
		o.w_ctx.mouse_y = item.rect.y + item.rect.h / 2
		o.w_ctx.left_mouse = {
			pressed  = true,
			released = true,
		}
		o.layout_resolve_pointer_hit()
		context_menu_test_tree()

		testing.expect_value(t, context_menu_test_item_clicks, 1)
		testing.expect(t, !context_menu_test_open)
	})
}

@(test)
context_menu_separator_layouts_when_open :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		context_menu_test_reset()
		context_menu_test_open = true
		widget_test_begin_layout()
		defer widget_test_end_frame()

		context_menu_test_tree()
		widget_test_finish_layout()

		testing.expect(t, context_menu_test_count_kind(.CONTEXT_MENU_SEPARATOR) >= 1)
		testing.expect(t, context_menu_test_count_kind(.CONTEXT_MENU_ITEM) >= 1)
	})
}

@(test)
context_menu_disabled_root_blocks_open :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		context_menu_test_reset()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Context_Menu({
			config = {
				id = "ctx-disabled",
				open = false,
				disabled = set.Disabled(true),
			},
			on_open_change = proc(open: bool) {
				context_menu_test_open = open
				context_menu_test_open_changes += 1
			},
			child = proc(_: Context_Menu_State) {
				Context_Menu_Trigger({
					config = {
						id = "ctx-disabled-trigger",
						width = set.Width(f32(100)),
						height = set.Height(f32(40)),
					},
				})
			},
		})
		widget_test_finish_layout()

		root, root_ok := widget_test_layout_node("ctx-disabled")
		testing.expect(t, root_ok)

		if !root_ok {
			return
		}

		trigger, trigger_ok := context_menu_test_find_kind_under(root, .CONTEXT_MENU_TRIGGER)
		testing.expect(t, trigger_ok)

		if !trigger_ok {
			return
		}

		trigger.rect = {0, 0, 100, 40}
		o.w_ctx.mouse_x = 20
		o.w_ctx.mouse_y = 20
		widget_test_begin_draw()

		o.w_ctx.right_mouse.pressed = true
		o.w_ctx.right_mouse.down = true
		Context_Menu({
			config = {
				id = "ctx-disabled",
				open = false,
				disabled = set.Disabled(true),
			},
			on_open_change = proc(open: bool) {
				context_menu_test_open = open
				context_menu_test_open_changes += 1
			},
			child = proc(_: Context_Menu_State) {
				Context_Menu_Trigger({
					config = {
						id = "ctx-disabled-trigger",
						width = set.Width(f32(100)),
						height = set.Height(f32(40)),
					},
				})
			},
		})

		testing.expect(t, !context_menu_test_open)
		testing.expect_value(t, context_menu_test_open_changes, 0)
	})
}

@(private)
context_menu_test_saw_open := false

@(test)
context_menu_is_open_helper_reads_ctx :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		context_menu_test_saw_open = false
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Context_Menu({
			config = {id = "ctx-helper", open = true},
			child = proc(_: Context_Menu_State) {
				context_menu_test_saw_open = Context_Menu_Is_Open()
			},
		})
		widget_test_finish_layout()
		testing.expect(t, context_menu_test_saw_open)
	})
}
