#+test
package oni_widgets

import o ".."
import set "../set"
import "core:testing"

@(private)
accordion_test_changes: int

@(private)
accordion_test_next: [8]string

@(private)
accordion_test_count: int

@(private)
accordion_test_change :: proc(value: []string) {
	accordion_test_changes += 1
	accordion_test_count = len(value)
	copy(accordion_test_next[:], value)
}

@(test)
accordion_selection_policy :: proc(t: ^testing.T) {
	values := [?]string{"", "a", "a", "b"}
	root := Accordion_Ctx {
		config = {value = values[:]},
		on_value_change = accordion_test_change,
	}

	root.value = accordion_normalize(root.config)
	testing.expect_value(t, len(root.value), 1)
	testing.expect_value(t, root.value[0], "a")
	accordion_test_changes = 0
	accordion_propose(&root, "b", true)
	testing.expect_value(t, accordion_test_changes, 1)
	testing.expect_value(t, accordion_test_count, 1)
	testing.expect_value(t, accordion_test_next[0], "b")
	testing.expect_value(t, root.value[0], "a")
	testing.expect_value(t, values[1], "a")
	root.config.prevent_collapse = true
	accordion_propose(&root, "a", false)
	testing.expect_value(t, accordion_test_changes, 1)
	root.config.prevent_collapse = false
	accordion_propose(&root, "a", false)
	testing.expect_value(t, accordion_test_changes, 2)
	testing.expect_value(t, accordion_test_count, 0)
	root.config.disabled = set.Disabled(true)
	accordion_propose(&root, "b", true)
	testing.expect_value(t, accordion_test_changes, 2)
}

@(test)
accordion_multiple_selection :: proc(t: ^testing.T) {
	values := [?]string{"a", "a", "b", ""}
	root := Accordion_Ctx {
		config = {value = values[:], multiple = true, prevent_collapse = true},
		on_value_change = accordion_test_change,
	}

	root.value = accordion_normalize(root.config)
	testing.expect_value(t, len(root.value), 2)
	accordion_test_changes = 0
	accordion_propose(&root, "c", true)
	testing.expect_value(t, accordion_test_count, 3)
	testing.expect_value(t, accordion_test_next[2], "c")
	accordion_propose(&root, "a", false)
	testing.expect_value(t, accordion_test_count, 1)
	testing.expect_value(t, accordion_test_next[0], "b")
	accordion_propose(&root, "a", true)
	accordion_propose(&root, "", true)
	testing.expect_value(t, accordion_test_changes, 2)
}

@(private)
accordion_test_tree :: proc() {
	Accordion({
		config = {id = "accordion", value = []string{"a"}},
		on_value_change = accordion_test_change,
		child = proc(_: Accordion_State) {
			Accordion_Item({
				config = {id = "item-a", value = "a"},
				child = proc(_: Accordion_Item_State) {
					Accordion_Trigger({config = {id = "trigger-a", width = set.Width(f32(100)), height = set.Height(f32(30))}})
					Accordion_Content({config = {id = "content-a", height = set.Height(f32(50))}})
				},
			})
			Accordion_Item({
				config = {id = "item-b", value = "b"},
				child = proc(_: Accordion_Item_State) {
					Accordion_Trigger({config = {id = "trigger-b", width = set.Width(f32(100)), height = set.Height(f32(30))}})
					Accordion_Content({config = {id = "content-b", height = set.Height(f32(50))}})
				},
			})
		},
	})
}

@(test)
accordion_layout_and_keyboard :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		accordion_test_changes = 0
		widget_test_begin_layout()
		defer widget_test_end_frame()
		accordion_test_tree()
		widget_test_finish_layout()
		expect_registered_id(t, "content-a")
		testing.expect_value(t, collapsible_test_count_kind(.ACCORDION_CONTENT), 1)
		expect_in_tab_order(t, "trigger-a", true)
		expect_in_tab_order(t, "trigger-b", true)
		o.widget_set_focused_id("trigger-a")
		widget_test_begin_draw()
		o.w_ctx.keys[int(o.Scancode.DOWN)].pressed = true
		accordion_test_tree()
		testing.expect_value(t, o.w_ctx.focused_id, "trigger-b")
		testing.expect_value(t, accordion_test_changes, 0)
		o.w_ctx.keys[int(o.Scancode.DOWN)].pressed = false
		o.w_ctx.keys[int(o.Scancode.SPACE)].pressed = true
		accordion_test_tree()
		testing.expect_value(t, accordion_test_changes, 1)
		testing.expect_value(t, accordion_test_next[0], "b")
		testing.expect(t, accordion_ctx == nil)
		testing.expect(t, accordion_item_ctx == nil)
	})
}

@(private)
accordion_test_selection: [2]string

@(private)
accordion_test_selection_count: int

@(private)
accordion_test_accept: bool

@(private)
accordion_test_disabled: bool

@(private)
accordion_test_item_disabled: bool

@(private)
accordion_test_content_runs: [2]int

@(private)
accordion_test_live_tree :: proc() {
	Accordion({
		config = {
			id = "live-root",
			value = accordion_test_selection[:accordion_test_selection_count],
			disabled = set.Disabled(accordion_test_disabled),
		},
		on_value_change = proc(value: []string) {
			accordion_test_change(value)

			if accordion_test_accept {
				accordion_test_selection_count = copy(accordion_test_selection[:], value)
			}
		},
		child = proc(_: Accordion_State) {
			Accordion_Item({
				config = {id = "live-a", value = "a", disabled = set.Disabled(accordion_test_item_disabled)},
				child = proc(_: Accordion_Item_State) {
					Accordion_Trigger({config = {id = "live-trigger-a", width = set.Width(f32(100)), height = set.Height(f32(30))}})
					Accordion_Content({
						config = {id = "live-content-a", width = set.Width(f32(100)), height = set.Height(f32(50))},
						child = proc(_: Accordion_Content_State) { accordion_test_content_runs[0] += 1 },
					})
				},
			})
			Accordion_Item({
				config = {id = "live-b", value = "b"},
				child = proc(_: Accordion_Item_State) {
					Accordion_Trigger({config = {id = "live-trigger-b", width = set.Width(f32(100)), height = set.Height(f32(30))}})
					Accordion_Content({
						config = {id = "live-content-b", height = set.Height(f32(50))},
						child = proc(_: Accordion_Content_State) { accordion_test_content_runs[1] += 1 },
					})
				},
			})
		},
	})
}

@(test)
accordion_draw_preserves_layout_for_accepted_and_rejected_changes :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		options := [?]bool{false, true}

		for accept in options {
			for initially_open in options {
				accordion_test_accept = accept
				accordion_test_disabled = false
				accordion_test_item_disabled = false
				accordion_test_selection = {"a", ""}
				accordion_test_selection_count = initially_open ? 1 : 0
				accordion_test_changes = 0
				accordion_test_content_runs = {}
				widget_test_begin_layout()
				accordion_test_live_tree()
				widget_test_finish_layout()
				accordion_test_content_runs = {}
				widget_test_begin_draw()
				o.widget_set_focused_id("live-trigger-a")
				o.w_ctx.keys[int(o.Scancode.SPACE)].pressed = true
				accordion_test_live_tree()
				testing.expect_value(t, accordion_test_changes, 1)
				testing.expect_value(t, accordion_test_content_runs[0], initially_open ? 1 : 0)
				testing.expect_value(t, accordion_test_content_runs[1], 0)
				widget_test_end_frame()
				accordion_test_content_runs = {}
				widget_test_begin_layout()
				accordion_test_live_tree()
				widget_test_finish_layout()
				expected_open := accept ? !initially_open : initially_open
				testing.expect_value(t, accordion_test_content_runs[0], expected_open ? 1 : 0)
				widget_test_end_frame()
			}
		}
	})
}

@(test)
accordion_pointer_and_disabled_items :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		for mode in 0 ..< 3 {
			accordion_test_accept = true
			accordion_test_disabled = mode == 1
			accordion_test_item_disabled = mode == 2
			accordion_test_selection_count = 0
			accordion_test_changes = 0
			widget_test_begin_layout()
			accordion_test_live_tree()
			widget_test_finish_layout()
			expect_in_tab_order(t, "live-trigger-a", mode == 0)
			root, root_ok := widget_test_layout_node("live-root")
			testing.expect(t, root_ok)
			first_item := &o.state.ui.layout.nodes[root.child_indices[0]]
			trigger, ok := collapsible_test_find_kind_under(first_item, .ACCORDION_TRIGGER)
			testing.expect(t, ok)

			if ok {
				trigger.rect = {0, 0, 100, 30}
				o.w_ctx.mouse_x = 10
				o.w_ctx.mouse_y = 10
				widget_test_begin_draw()
				o.w_ctx.left_mouse.pressed = true
				o.w_ctx.left_mouse.down = true
				accordion_test_live_tree()
				o.w_ctx.left_mouse.pressed = false
				o.w_ctx.left_mouse.down = false
				o.w_ctx.left_mouse.released = true
				accordion_test_live_tree()
				testing.expect_value(t, accordion_test_changes, mode == 0 ? 1 : 0)
			}

			widget_test_end_frame()
		}
	})
}

@(test)
accordion_selection_snapshot_does_not_alias_input :: proc(t: ^testing.T) {
	values := [?]string{"a", "b"}
	snapshot := accordion_normalize({value = values[:], multiple = true})
	values[0] = "changed"
	values[1] = ""
	testing.expect_value(t, snapshot[0], "a")
	testing.expect_value(t, snapshot[1], "b")
}

@(test)
accordion_switch_keeps_later_sibling_snapshot :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		accordion_test_accept = true
		accordion_test_disabled = false
		accordion_test_item_disabled = false
		accordion_test_selection = {"b", ""}
		accordion_test_selection_count = 1
		accordion_test_changes = 0
		widget_test_begin_layout()
		defer widget_test_end_frame()
		accordion_test_live_tree()
		widget_test_finish_layout()
		accordion_test_content_runs = {}
		widget_test_begin_draw()
		o.widget_set_focused_id("live-trigger-a")
		o.w_ctx.keys[int(o.Scancode.SPACE)].pressed = true
		accordion_test_live_tree()
		testing.expect_value(t, accordion_test_selection[0], "a")
		testing.expect_value(t, accordion_test_content_runs[0], 0)
		testing.expect_value(t, accordion_test_content_runs[1], 1)
	})
}

@(test)
accordion_nested_context_and_force_mount :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()
		Accordion({
			config = {id = "outer", value = []string{"outer-item"}},
			child = proc(_: Accordion_State) {
				Accordion_Item({
					config = {id = "outer-item", value = "outer-item"},
					child = proc(_: Accordion_Item_State) {
						assert(Accordion_Is_Open())
						Accordion({
							config = {id = "inner"},
							child = proc(_: Accordion_State) {
								assert(!Accordion_Is_Open())
								Accordion_Item({
									config = {id = "inner-item", value = "inner-item"},
									child = proc(_: Accordion_Item_State) {
										assert(!Accordion_Is_Open())
										Accordion_Content({config = {id = "inner-panel", force_mount = true}})
									},
								})
							},
						})
						assert(Accordion_Is_Open())
					},
				})
			},
		})
		widget_test_finish_layout()
		root, root_ok := widget_test_layout_node("outer")
		testing.expect(t, root_ok)
		panel, ok := collapsible_test_find_kind_under(root, .ACCORDION_CONTENT)
		testing.expect(t, ok)

		if ok {
			testing.expect(t, panel.config.visibility == .HIDDEN)
		}

		testing.expect(t, !Accordion_Is_Open())
		testing.expect(t, accordion_ctx == nil && accordion_item_ctx == nil)
	})
}

@(private)
accordion_test_focus_count: int

@(private)
accordion_test_blur_count: int

@(private)
accordion_test_focus_state_ok: bool

@(test)
accordion_navigation_wrap_home_end_and_focus_events :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		accordion_test_focus_count = 0
		accordion_test_blur_count = 0
		accordion_test_focus_state_ok = true
		root := Accordion_Ctx{}
		root.triggers = make([dynamic]Accordion_Trigger_Entry, 0, 3, context.temp_allocator)
		keys := [?]string{"first", "middle", "last"}

		for key in keys {
			append(&root.triggers, Accordion_Trigger_Entry{
				key = key,
				item = {root = &root, open = true},
				on_focus = proc(ev: Accordion_Trigger_Event) {
					accordion_test_focus_count += 1
					accordion_test_focus_state_ok = accordion_test_focus_state_ok && ev.frame_state.is_focused && Accordion_Is_Open()
				},
				on_blur = proc(ev: Accordion_Trigger_Event) {
					accordion_test_blur_count += 1
					accordion_test_focus_state_ok = accordion_test_focus_state_ok && !ev.frame_state.is_focused
				},
			})
		}

		previous := accordion_ctx
		accordion_ctx = &root
		defer { accordion_ctx = previous }
		o.widget_set_focused_id("first")
		steps := [?]struct{key: o.Scancode, target: string}{
			{.UP, "last"}, {.DOWN, "first"}, {.END, "last"}, {.HOME, "first"},
		}

		for step in steps {
			o.w_ctx.keys = {}
			o.state.shortcuts.consumed_keys = {}
			o.w_ctx.keys[int(step.key)].pressed = true
			accordion_keyboard(&root)
			testing.expect_value(t, o.w_ctx.focused_id, step.target)
			testing.expect(t, o.shortcut_key_consumed(step.key))
			accordion_keyboard(&root)
			testing.expect_value(t, o.w_ctx.focused_id, step.target)
		}

		testing.expect_value(t, accordion_test_focus_count, 4)
		testing.expect_value(t, accordion_test_blur_count, 4)
		testing.expect(t, accordion_test_focus_state_ok)
		testing.expect(t, accordion_item_ctx == nil)
	})
}

@(test)
accordion_shutdown_clears_ctx_pointers :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		Accordion({
			config = {id = "shutdown-root"},
			child = proc(_: Accordion_State) {
				Accordion_Item({
					config = {value = "a"},
					child = proc(_: Accordion_Item_State) {
						Accordion_Trigger({config = {id = "shutdown-trigger"}})
					},
				})
			},
		})
		testing.expect(t, accordion_ctx == nil)
		widget_test_finish_layout()
		widget_test_end_frame()

		accordion_ctx = &Accordion_Ctx{}
		accordion_item_ctx = &Accordion_Item_Ctx{}
		accordion_trigger_ctx = &Accordion_Trigger_Ctx{}
		accordion_shutdown()
		testing.expect(t, accordion_ctx == nil)
		testing.expect(t, accordion_item_ctx == nil)
		testing.expect(t, accordion_trigger_ctx == nil)
	})
}
