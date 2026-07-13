package widgets

import o ".."
import "core:testing"
import set "../set"
import sdl "vendor:sdl3"

@(private)
interaction_clicked: int
@(private)
interaction_entered: int
@(private)
interaction_key: o.Scancode

@(test)
widget_event_and_config_merge_theme_with_overrides :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			props := Rectangle_Props {
				config = {
					id = "panel",
					background = set.Background(o.Color.PRIMARY),
				},
			}
			frame := Rectangle_State{}
			config := widget_config(props, &frame, rect_theme_base)
			testing.expect(t, config.kind == .RECT)
			testing.expect_value(t, config.id, "panel")

			event := widget_event(frame, mouse_button = sdl.BUTTON_LEFT, key = o.Scancode.SPACE)
			testing.expect_value(t, event.mouse_button, sdl.BUTTON_LEFT)
			testing.expect(t, event.key == o.Scancode.SPACE)
		},
	)
}

@(test)
widget_dispatch_events_fires_click_on_pointer_release :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			interaction_clicked = 0
			interaction_entered = 0
			props := Rectangle_Props {
				on_click = proc(event: Rectangle_Event) {
					_ = event
					interaction_clicked += 1
				},
				on_mouse_enter = proc(event: Rectangle_Event) {
					_ = event
					interaction_entered += 1
				},
			}

			frame := Rectangle_State {
				is_hovered = true,
			}
			handlers := widget_lifecycle_handlers(props, Rectangle_State)
			event := widget_event(frame)

			o.w_ctx.left_mouse.pressed = true
			widget_dispatch_events(props, &frame, handlers, event, "rect", false, false)
			testing.expect_value(t, interaction_entered, 1)
			testing.expect_value(t, interaction_clicked, 0)

			o.w_ctx.left_mouse.pressed = false
			o.w_ctx.left_mouse.released = true
			widget_dispatch_events(props, &frame, handlers, event, "rect", false, false)
			testing.expect_value(t, interaction_clicked, 1)
		},
	)
}

@(test)
widget_dispatch_events_keyboard_click_when_focused :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			interaction_clicked = 0
			interaction_key = o.Scancode(0)
			props := Rectangle_Props {
				on_click = proc(event: Rectangle_Event) {
					interaction_clicked += 1
					interaction_key = event.key
				},
			}
			frame := Rectangle_State {
				is_focused = true,
			}
			handlers := widget_lifecycle_handlers(props, Rectangle_State)
			event := widget_event(frame)

			o.w_ctx.keys[int(sdl.Scancode.RETURN)].pressed = true
			widget_dispatch_events(props, &frame, handlers, event, "rect", false, false)
			testing.expect_value(t, interaction_clicked, 1)
			testing.expect(t, interaction_key == o.Scancode(sdl.Scancode.RETURN))
		},
	)
}

@(test)
widget_dispatch_events_skips_when_cannot_interact :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			interaction_clicked = 0
			props := Rectangle_Props {
				on_click = proc(event: Rectangle_Event) {
					_ = event
					interaction_clicked += 1
				},
			}
			frame := Rectangle_State {
				is_hovered = true,
				is_disabled = true,
			}
			handlers := widget_lifecycle_handlers(props, Rectangle_State)
			event := widget_event(frame)
			o.w_ctx.left_mouse.pressed = true
			o.w_ctx.left_mouse.released = true
			widget_dispatch_events(props, &frame, handlers, event, "rect", false, false)
			testing.expect_value(t, interaction_clicked, 0)
		},
	)
}

@(test)
widget_handle_interaction_sets_hover_and_click_flags :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			props := Rectangle_Props{}
			frame := Rectangle_State{}
			handlers := widget_lifecycle_handlers(props, Rectangle_State)
			config := o.Resolved_Widget_Config {
				space = .SCREEN,
				tabbable = true,
			}
			layout_id := o.UI_Id(1)
			rect := o.Rect{0, 0, 40, 40}

			widget_test_begin_layout()
			_ = o.layout_push_node(layout_id, {kind = .RECT, space = .SCREEN})
			o.layout_pop_node()
			idx := o.state.ui.layout.id_to_node[layout_id]
			o.state.ui.layout.nodes[idx].rect = rect
			o.layout_finalize_stack_order()
			widget_test_finish_layout()
			widget_test_begin_draw()

			o.w_ctx.mouse_x = 15
			o.w_ctx.mouse_y = 15
			o.w_ctx.left_mouse.pressed = true
			o.w_ctx.left_mouse.down = true
			o.layout_resolve_pointer_hit()

			got, lost := widget_handle_interaction(
				props,
				&frame,
				handlers,
				"hit",
				false,
				true,
				layout_id,
				rect,
				config,
			)
			testing.expect(t, frame.is_hovered)
			testing.expect(t, frame.is_pointer_target)
			testing.expect(t, frame.is_left_clicked)
			testing.expect(t, frame.is_Pressed)
			testing.expect(t, got && !lost)
			testing.expect(t, frame.is_focused)
		},
	)
}

@(private)
bubble_parent_clicks: int
@(private)
bubble_child_clicks: int

@(test)
widget_dispatch_events_respects_stop_propagation :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			interaction_clicked = 0
			child_props := Rectangle_Props {
				on_click = proc(event: Rectangle_Event) {
					_ = event
					interaction_clicked += 1
					o.stop_propagation()
				},
			}
			child_frame := Rectangle_State {
				is_hovered = true,
			}
			child_handlers := widget_lifecycle_handlers(child_props, Rectangle_State)
			child_event := widget_event(child_frame)

			o.w_ctx.left_mouse.pressed = true
			widget_dispatch_events(child_props, &child_frame, child_handlers, child_event, "child", false, false)
			o.w_ctx.left_mouse.pressed = false
			o.w_ctx.left_mouse.released = true
			widget_dispatch_events(child_props, &child_frame, child_handlers, child_event, "child", false, false)
			testing.expect_value(t, interaction_clicked, 1)
			testing.expect(t, o.w_ctx.pointer_propagation_stopped)

			interaction_clicked = 0
			parent_props := Rectangle_Props {
				on_click = proc(event: Rectangle_Event) {
					_ = event
					interaction_clicked += 1
				},
			}
			parent_frame := Rectangle_State {
				is_hovered = true,
			}
			parent_handlers := widget_lifecycle_handlers(parent_props, Rectangle_State)
			parent_event := widget_event(parent_frame)
			widget_dispatch_events(
				parent_props,
				&parent_frame,
				parent_handlers,
				parent_event,
				"parent",
				false,
				false,
			)
			testing.expect_value(t, interaction_clicked, 0)
		},
	)
}

@(test)
widget_parent_hovered_when_child_is_pointer_target :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			parent_id := o.UI_Id(1)
			child_id := o.UI_Id(2)
			_ = o.layout_push_node(
				parent_id,
				{kind = .RECT, space = .SCREEN, width = len_fixed(100), height = len_fixed(100)},
			)
			_ = o.layout_push_node(
				child_id,
				{kind = .RECT, space = .SCREEN, width = len_fixed(40), height = len_fixed(40)},
			)
			o.layout_pop_node()
			o.layout_pop_node()
			o.layout_finalize_stack_order()
			widget_test_finish_layout()

			parent_i := o.state.ui.layout.id_to_node[parent_id]
			child_i := o.state.ui.layout.id_to_node[child_id]
			o.state.ui.layout.nodes[parent_i].rect = {0, 0, 100, 100}
			o.state.ui.layout.nodes[child_i].rect = {10, 10, 40, 40}

			o.w_ctx.mouse_x = 20
			o.w_ctx.mouse_y = 20
			widget_test_begin_draw()

			parent_props := Rectangle_Props{}
			child_props := Rectangle_Props{}
			parent_frame := Rectangle_State{}
			child_frame := Rectangle_State{}
			parent_handlers := widget_lifecycle_handlers(parent_props, Rectangle_State)
			child_handlers := widget_lifecycle_handlers(child_props, Rectangle_State)
			config := o.Resolved_Widget_Config {
				space = .SCREEN,
			}

			_, _ = widget_handle_interaction(
				parent_props,
				&parent_frame,
				parent_handlers,
				"parent",
				false,
				false,
				parent_id,
				o.state.ui.layout.nodes[parent_i].rect,
				config,
			)
			_, _ = widget_handle_interaction(
				child_props,
				&child_frame,
				child_handlers,
				"child",
				false,
				false,
				child_id,
				o.state.ui.layout.nodes[child_i].rect,
				config,
			)

			testing.expect(t, child_frame.is_hovered)
			testing.expect(t, child_frame.is_pointer_target)
			testing.expect(t, parent_frame.is_hovered)
			testing.expect(t, !parent_frame.is_pointer_target)
		},
	)
}

@(test)
widget_click_bubbles_child_then_parent_unless_stopped :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			bubble_parent_clicks = 0
			bubble_child_clicks = 0

			child_props := Rectangle_Props {
				on_click = proc(event: Rectangle_Event) {
					_ = event
					bubble_child_clicks += 1
				},
			}
			parent_props := Rectangle_Props {
				on_click = proc(event: Rectangle_Event) {
					_ = event
					bubble_parent_clicks += 1
				},
			}
			child_frame := Rectangle_State {
				is_hovered = true,
			}
			parent_frame := Rectangle_State {
				is_hovered = true,
			}
			child_handlers := widget_lifecycle_handlers(child_props, Rectangle_State)
			parent_handlers := widget_lifecycle_handlers(parent_props, Rectangle_State)

			o.w_ctx.left_mouse.pressed = true
			widget_dispatch_events(
				child_props,
				&child_frame,
				child_handlers,
				widget_event(child_frame),
				"child",
				false,
				false,
			)
			widget_dispatch_events(
				parent_props,
				&parent_frame,
				parent_handlers,
				widget_event(parent_frame),
				"parent",
				false,
				false,
			)

			o.w_ctx.left_mouse.pressed = false
			o.w_ctx.left_mouse.released = true
			widget_dispatch_events(
				child_props,
				&child_frame,
				child_handlers,
				widget_event(child_frame),
				"child",
				false,
				false,
			)
			widget_dispatch_events(
				parent_props,
				&parent_frame,
				parent_handlers,
				widget_event(parent_frame),
				"parent",
				false,
				false,
			)

			testing.expect_value(t, bubble_child_clicks, 1)
			testing.expect_value(t, bubble_parent_clicks, 1)

			bubble_parent_clicks = 0
			bubble_child_clicks = 0
			o.w_ctx.pointer_propagation_stopped = false
			o.w_ctx.left_mouse.released = false

			stop_child_props := Rectangle_Props {
				on_click = proc(event: Rectangle_Event) {
					_ = event
					bubble_child_clicks += 1
					o.stop_propagation()
				},
			}
			stop_child_handlers := widget_lifecycle_handlers(stop_child_props, Rectangle_State)
			child_frame = Rectangle_State {
				is_hovered = true,
			}
			parent_frame = Rectangle_State {
				is_hovered = true,
			}

			o.w_ctx.left_mouse.pressed = true
			widget_dispatch_events(
				stop_child_props,
				&child_frame,
				stop_child_handlers,
				widget_event(child_frame),
				"child2",
				false,
				false,
			)
			widget_dispatch_events(
				parent_props,
				&parent_frame,
				parent_handlers,
				widget_event(parent_frame),
				"parent2",
				false,
				false,
			)
			o.w_ctx.left_mouse.pressed = false
			o.w_ctx.left_mouse.released = true
			widget_dispatch_events(
				stop_child_props,
				&child_frame,
				stop_child_handlers,
				widget_event(child_frame),
				"child2",
				false,
				false,
			)
			widget_dispatch_events(
				parent_props,
				&parent_frame,
				parent_handlers,
				widget_event(parent_frame),
				"parent2",
				false,
				false,
			)

			testing.expect_value(t, bubble_child_clicks, 1)
			testing.expect_value(t, bubble_parent_clicks, 0)
		},
	)
}

@(private)
hover_parent_enters: int
@(private)
hover_parent_leaves: int
@(private)
hover_child_a_enters: int
@(private)
hover_child_a_leaves: int
@(private)
hover_child_b_enters: int
@(private)
hover_child_b_leaves: int
@(private)
bubble_pressed: int
@(private)
bubble_moves: int
@(private)
bubble_contexts: int
@(private)
bubble_grand_clicks: int
@(private)
bubble_mid_clicks: int
@(private)
e2e_parent_clicks: int
@(private)
e2e_child_clicks: int
@(private)
e2e_child_stops: bool

@(private)
e2e_draw_parent_child_tree :: proc() {
	Rectangle(
		{
			config = {
				id = "e2e-parent",
				width = set.Width(f32(100)),
				height = set.Height(f32(100)),
			},
			on_click = proc(event: Rectangle_Event) {
				_ = event
				e2e_parent_clicks += 1
			},
			child = proc(_: Rectangle_State) {
				Rectangle(
					{
						config = {
							id = "e2e-child",
							width = set.Width(f32(40)),
							height = set.Height(f32(40)),
						},
						on_click = proc(event: Rectangle_Event) {
							_ = event
							e2e_child_clicks += 1
							if e2e_child_stops {
								o.stop_propagation()
							}
						},
					},
				)
			},
		},
	)
}

@(test)
widget_hover_enter_leave_parent_stable_across_child_switch :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			hover_parent_enters = 0
			hover_parent_leaves = 0
			hover_child_a_enters = 0
			hover_child_a_leaves = 0
			hover_child_b_enters = 0
			hover_child_b_leaves = 0

			parent_props := Rectangle_Props {
				on_mouse_enter = proc(event: Rectangle_Event) {
					_ = event
					hover_parent_enters += 1
				},
				on_mouse_leave = proc(event: Rectangle_Event) {
					_ = event
					hover_parent_leaves += 1
				},
			}
			child_a_props := Rectangle_Props {
				on_mouse_enter = proc(event: Rectangle_Event) {
					_ = event
					hover_child_a_enters += 1
				},
				on_mouse_leave = proc(event: Rectangle_Event) {
					_ = event
					hover_child_a_leaves += 1
				},
			}
			child_b_props := Rectangle_Props {
				on_mouse_enter = proc(event: Rectangle_Event) {
					_ = event
					hover_child_b_enters += 1
				},
				on_mouse_leave = proc(event: Rectangle_Event) {
					_ = event
					hover_child_b_leaves += 1
				},
			}

			parent_frame := Rectangle_State{is_hovered = true}
			child_a_frame := Rectangle_State{is_hovered = true}
			child_b_frame := Rectangle_State{}
			parent_handlers := widget_lifecycle_handlers(parent_props, Rectangle_State)
			child_a_handlers := widget_lifecycle_handlers(child_a_props, Rectangle_State)
			child_b_handlers := widget_lifecycle_handlers(child_b_props, Rectangle_State)

			// Enter via child A (parent + A hovered).
			widget_dispatch_events(
				child_a_props,
				&child_a_frame,
				child_a_handlers,
				widget_event(child_a_frame),
				"a",
				false,
				false,
			)
			widget_dispatch_events(
				parent_props,
				&parent_frame,
				parent_handlers,
				widget_event(parent_frame),
				"parent",
				false,
				false,
			)
			testing.expect_value(t, hover_child_a_enters, 1)
			testing.expect_value(t, hover_parent_enters, 1)

			// Switch to child B under same parent.
			child_a_frame.is_hovered = false
			child_b_frame.is_hovered = true
			widget_dispatch_events(
				child_a_props,
				&child_a_frame,
				child_a_handlers,
				widget_event(child_a_frame),
				"a",
				false,
				false,
			)
			widget_dispatch_events(
				child_b_props,
				&child_b_frame,
				child_b_handlers,
				widget_event(child_b_frame),
				"b",
				false,
				false,
			)
			widget_dispatch_events(
				parent_props,
				&parent_frame,
				parent_handlers,
				widget_event(parent_frame),
				"parent",
				false,
				false,
			)

			testing.expect_value(t, hover_child_a_leaves, 1)
			testing.expect_value(t, hover_child_b_enters, 1)
			testing.expect_value(t, hover_parent_enters, 1)
			testing.expect_value(t, hover_parent_leaves, 0)
		},
	)
}

@(test)
widget_enter_leave_ignore_stop_propagation :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			hover_parent_enters = 0
			hover_parent_leaves = 0
			o.w_ctx.pointer_propagation_stopped = true

			parent_props := Rectangle_Props {
				on_mouse_enter = proc(event: Rectangle_Event) {
					_ = event
					hover_parent_enters += 1
				},
				on_mouse_leave = proc(event: Rectangle_Event) {
					_ = event
					hover_parent_leaves += 1
				},
				on_click = proc(event: Rectangle_Event) {
					_ = event
					bubble_parent_clicks += 1
				},
			}
			parent_frame := Rectangle_State{is_hovered = true}
			handlers := widget_lifecycle_handlers(parent_props, Rectangle_State)

			bubble_parent_clicks = 0
			o.w_ctx.left_mouse.pressed = true
			widget_dispatch_events(
				parent_props,
				&parent_frame,
				handlers,
				widget_event(parent_frame),
				"p-enter",
				false,
				false,
			)
			o.w_ctx.left_mouse.pressed = false
			o.w_ctx.left_mouse.released = true
			widget_dispatch_events(
				parent_props,
				&parent_frame,
				handlers,
				widget_event(parent_frame),
				"p-enter",
				false,
				false,
			)

			testing.expect_value(t, hover_parent_enters, 1)
			testing.expect_value(t, bubble_parent_clicks, 0)

			parent_frame.is_hovered = false
			o.w_ctx.left_mouse.released = false
			widget_dispatch_events(
				parent_props,
				&parent_frame,
				handlers,
				widget_event(parent_frame),
				"p-enter",
				false,
				false,
			)
			testing.expect_value(t, hover_parent_leaves, 1)
		},
	)
}

@(test)
widget_non_click_pointer_events_bubble_unless_stopped :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			bubble_pressed = 0
			bubble_moves = 0
			bubble_contexts = 0

			child_props := Rectangle_Props {
				on_mouse_pressed = proc(event: Rectangle_Event) {
					_ = event
					bubble_pressed += 1
					o.stop_propagation()
				},
				on_mouse_move = proc(event: Rectangle_Event) {
					_ = event
					bubble_moves += 1
				},
				on_contextmenu = proc(event: Rectangle_Event) {
					_ = event
					bubble_contexts += 1
					o.stop_propagation()
				},
			}
			parent_props := Rectangle_Props {
				on_mouse_pressed = proc(event: Rectangle_Event) {
					_ = event
					bubble_pressed += 10
				},
				on_mouse_move = proc(event: Rectangle_Event) {
					_ = event
					bubble_moves += 10
				},
				on_contextmenu = proc(event: Rectangle_Event) {
					_ = event
					bubble_contexts += 10
				},
			}
			child_frame := Rectangle_State{is_hovered = true}
			parent_frame := Rectangle_State{is_hovered = true}
			child_handlers := widget_lifecycle_handlers(child_props, Rectangle_State)
			parent_handlers := widget_lifecycle_handlers(parent_props, Rectangle_State)

			o.w_ctx.left_mouse.pressed = true
			widget_dispatch_events(
				child_props,
				&child_frame,
				child_handlers,
				widget_event(child_frame),
				"c-press",
				false,
				false,
			)
			widget_dispatch_events(
				parent_props,
				&parent_frame,
				parent_handlers,
				widget_event(parent_frame),
				"p-press",
				false,
				false,
			)
			testing.expect_value(t, bubble_pressed, 1)

			o.w_ctx.pointer_propagation_stopped = false
			o.w_ctx.left_mouse.pressed = false
			o.w_ctx.mouse_moved = true
			widget_dispatch_events(
				child_props,
				&child_frame,
				child_handlers,
				widget_event(child_frame),
				"c-move",
				false,
				false,
			)
			widget_dispatch_events(
				parent_props,
				&parent_frame,
				parent_handlers,
				widget_event(parent_frame),
				"p-move",
				false,
				false,
			)
			testing.expect_value(t, bubble_moves, 11)

			o.w_ctx.mouse_moved = false
			o.w_ctx.right_mouse.pressed = true
			widget_dispatch_events(
				child_props,
				&child_frame,
				child_handlers,
				widget_event(child_frame),
				"c-ctx",
				false,
				false,
			)
			widget_dispatch_events(
				parent_props,
				&parent_frame,
				parent_handlers,
				widget_event(parent_frame),
				"p-ctx",
				false,
				false,
			)
			testing.expect_value(t, bubble_contexts, 1)
		},
	)
}

@(test)
widget_keyboard_click_ignores_stop_propagation :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			interaction_clicked = 0
			interaction_key = o.Scancode(0)
			o.w_ctx.pointer_propagation_stopped = true

			props := Rectangle_Props {
				on_click = proc(event: Rectangle_Event) {
					interaction_clicked += 1
					interaction_key = event.key
				},
			}
			frame := Rectangle_State {
				is_focused = true,
			}
			handlers := widget_lifecycle_handlers(props, Rectangle_State)

			o.w_ctx.keys[int(sdl.Scancode.SPACE)].pressed = true
			widget_dispatch_events(props, &frame, handlers, widget_event(frame), "kbd", false, false)
			testing.expect_value(t, interaction_clicked, 1)
			testing.expect(t, interaction_key == o.Scancode(sdl.Scancode.SPACE))
		},
	)
}

@(test)
widget_deep_click_bubble_stops_at_middle :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			bubble_grand_clicks = 0
			bubble_mid_clicks = 0
			bubble_child_clicks = 0

			child_props := Rectangle_Props {
				on_click = proc(event: Rectangle_Event) {
					_ = event
					bubble_child_clicks += 1
				},
			}
			mid_props := Rectangle_Props {
				on_click = proc(event: Rectangle_Event) {
					_ = event
					bubble_mid_clicks += 1
					o.stop_propagation()
				},
			}
			grand_props := Rectangle_Props {
				on_click = proc(event: Rectangle_Event) {
					_ = event
					bubble_grand_clicks += 1
				},
			}
			child_frame := Rectangle_State{is_hovered = true}
			mid_frame := Rectangle_State{is_hovered = true}
			grand_frame := Rectangle_State{is_hovered = true}
			child_handlers := widget_lifecycle_handlers(child_props, Rectangle_State)
			mid_handlers := widget_lifecycle_handlers(mid_props, Rectangle_State)
			grand_handlers := widget_lifecycle_handlers(grand_props, Rectangle_State)

			o.w_ctx.left_mouse.pressed = true
			widget_dispatch_events(
				child_props,
				&child_frame,
				child_handlers,
				widget_event(child_frame),
				"deep-c",
				false,
				false,
			)
			widget_dispatch_events(
				mid_props,
				&mid_frame,
				mid_handlers,
				widget_event(mid_frame),
				"deep-m",
				false,
				false,
			)
			widget_dispatch_events(
				grand_props,
				&grand_frame,
				grand_handlers,
				widget_event(grand_frame),
				"deep-g",
				false,
				false,
			)

			o.w_ctx.left_mouse.pressed = false
			o.w_ctx.left_mouse.released = true
			widget_dispatch_events(
				child_props,
				&child_frame,
				child_handlers,
				widget_event(child_frame),
				"deep-c",
				false,
				false,
			)
			widget_dispatch_events(
				mid_props,
				&mid_frame,
				mid_handlers,
				widget_event(mid_frame),
				"deep-m",
				false,
				false,
			)
			widget_dispatch_events(
				grand_props,
				&grand_frame,
				grand_handlers,
				widget_event(grand_frame),
				"deep-g",
				false,
				false,
			)

			testing.expect_value(t, bubble_child_clicks, 1)
			testing.expect_value(t, bubble_mid_clicks, 1)
			testing.expect_value(t, bubble_grand_clicks, 0)
		},
	)
}

@(test)
widget_rectangle_draw_click_bubbles_after_children :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			e2e_parent_clicks = 0
			e2e_child_clicks = 0
			e2e_child_stops = false

			widget_test_begin_layout()
			defer widget_test_end_frame()

			e2e_draw_parent_child_tree()
			widget_test_finish_layout()

			parent_node, child_node, found := widget_test_find_parent_child_nodes()
			testing.expect(t, found && child_node != nil)
			if !found || child_node == nil do return

			parent_node.rect = {0, 0, 100, 100}
			child_node.rect = {10, 10, 40, 40}

			o.w_ctx.mouse_x = 20
			o.w_ctx.mouse_y = 20
			widget_test_begin_draw()
			testing.expect(t, o.w_ctx.pointer_hit_valid)
			testing.expect(t, o.pointer_hits(parent_node.ui_id, parent_node.rect, .SCREEN))
			testing.expect(t, o.pointer_is_target(child_node.ui_id))

			o.w_ctx.left_mouse.pressed = true
			o.w_ctx.left_mouse.down = true
			e2e_draw_parent_child_tree()

			o.w_ctx.left_mouse.pressed = false
			o.w_ctx.left_mouse.down = false
			o.w_ctx.left_mouse.released = true
			e2e_draw_parent_child_tree()

			testing.expect_value(t, e2e_child_clicks, 1)
			testing.expect_value(t, e2e_parent_clicks, 1)

			e2e_child_clicks = 0
			e2e_parent_clicks = 0
			e2e_child_stops = true
			o.w_ctx.pointer_propagation_stopped = false
			o.w_ctx.left_mouse.released = false
			o.w_ctx.left_mouse.pressed = true
			o.w_ctx.left_mouse.down = true
			e2e_draw_parent_child_tree()

			o.w_ctx.left_mouse.pressed = false
			o.w_ctx.left_mouse.down = false
			o.w_ctx.left_mouse.released = true
			e2e_draw_parent_child_tree()

			testing.expect_value(t, e2e_child_clicks, 1)
			testing.expect_value(t, e2e_parent_clicks, 0)
		},
	)
}
