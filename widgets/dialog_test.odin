package oni_widgets

import o ".."
import set "../set"
import "core:testing"

@(private)
dialog_test_panel :: proc(props: Dialog_Overlay_Panel_Props) {
	dialog_overlay_panel(props)
}

@(private)
dialog_test_open_root :: proc(child: proc(frame_state: Dialog_State)) {
	Dialog({
		config = {id = "dialog-root-open"},
		open = true,
		child = child,
	})
}

@(test)
dialog_overlay_panel_theme_base_sets_kind_and_overlay_space :: proc(t: ^testing.T) {
	frame := Dialog_Overlay_Panel_State{}
	base := dialog_overlay_panel_theme_base(&frame)
	testing.expect(t, base.kind == .RECT)
	testing.expect(t, base.space.mode == .Value)
	testing.expect(t, base.space.value.(o.Draw_Space) == .OVERLAY)
}

@(test)
dialog_overlay_panel_forces_overlay_space_over_user_override :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		dialog_test_panel(
			{
				config = {
					id = "dialog-forced-space",
					space = set.Space(.SCREEN),
					width = set.Width(f32(80)),
					height = set.Height(f32(40)),
				},
			},
		)
		widget_test_finish_layout()

		node, ok := widget_test_layout_node("dialog-forced-space")
		testing.expect(t, ok)
		if !ok do return
		testing.expect(t, node.space == .OVERLAY)
		testing.expect(t, node.config.space == .OVERLAY)
	})
}

@(private)
dialog_test_find_overlay_kind :: proc(kind: o.Widget_Kind) -> (^o.Layout_Node, bool) {
	for &node in o.state.ui.layout.nodes {
		if node.space == .OVERLAY && node.kind == kind {
			return &node, true
		}
	}

	return nil, false
}

@(test)
dialog_scrim_config_background_override :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		want := o.css_color_to_rgba(.RED_500)
		widget_test_begin_layout()
		defer widget_test_end_frame()

		dialog_test_open_root(proc(_: Dialog_State) {
			Dialog_Scrim({
				config = {
					id = "dialog-scrim-red",
					background = set.Background(.RED_500),
				},
			})
		})
		widget_test_finish_layout()
		widget_test_begin_draw()

		node, ok := dialog_test_find_overlay_kind(.DIALOG_SCRIM)
		testing.expect(t, ok)
		if !ok do return

		testing.expect(t, node.config.background_rgba_ok)
		if !node.config.background_rgba_ok do return

		testing.expect(t, node.config.background_rgba == want)
	})
}

@(test)
dialog_scrim_background_override_with_content :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		want := o.css_color_to_rgba(.RED_500)
		widget_test_begin_layout()
		defer widget_test_end_frame()

		dialog_test_open_root(proc(_: Dialog_State) {
			Dialog_Scrim({
				config = {
					id = "dialog-scrim-red-compound",
					background = set.Background(.RED_500),
				},
			})
			Dialog_Content({
				config = {width = set.Width(f32(240)), padding = set.Padding(f32(16))},
				child = proc(_: Dialog_Content_Props_State) {},
			})
		})
		widget_test_finish_layout()
		widget_test_begin_draw()

		node, ok := dialog_test_find_overlay_kind(.DIALOG_SCRIM)
		testing.expect(t, ok)
		if !ok do return

		testing.expect(t, node.config.background_rgba_ok)
		if !node.config.background_rgba_ok do return

		testing.expect(t, node.config.background_rgba == want)
	})
}

@(test)
dialog_content_host_is_transparent :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		dialog_test_open_root(proc(_: Dialog_State) {
			Dialog_Content({
				config = {width = set.Width(f32(200)), height = set.Height(f32(100))},
				child = proc(_: Dialog_Content_Props_State) {},
			})
		})
		widget_test_finish_layout()
		widget_test_begin_draw()

		vw := f32(o.state.dpi.logical_w)
		vh := f32(o.state.dpi.logical_h)
		found_host := false

		for &n in o.state.ui.layout.nodes {
			if n.space != .OVERLAY do continue
			if n.kind != .RECT do continue
			if n.rect.w != vw || n.rect.h != vh do continue

			testing.expect(t, n.config.background_rgba_ok)
			if !n.config.background_rgba_ok do return

			testing.expect(t, n.config.background_rgba.a == 0)
			found_host = true
		}

		testing.expect(t, found_host)
	})
}

@(test)
dialog_scrim_fixed_covers_viewport :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		dialog_test_open_root(proc(_: Dialog_State) {
			Dialog_Scrim({config = {id = "dialog-scrim-viewport"}})
		})
		widget_test_finish_layout()
		widget_test_begin_draw()

		node, ok := dialog_test_find_overlay_kind(.DIALOG_SCRIM)
		testing.expect(t, ok)
		if !ok do return
		testing.expect(t, node.space == .OVERLAY)
		testing.expect(t, node.kind == .DIALOG_SCRIM)
		expect_close(t, node.rect.x, 0)
		expect_close(t, node.rect.y, 0)
		expect_close(t, node.rect.w, f32(o.state.dpi.logical_w))
		expect_close(t, node.rect.h, f32(o.state.dpi.logical_h))
	})
}

@(test)
dialog_scrim_skips_layout_when_closed :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Dialog({
			config = {id = "dialog-closed"},
			open = false,
			child = proc(_: Dialog_State) {
				Dialog_Scrim({config = {id = "dialog-scrim-closed"}})
			},
		})
		widget_test_finish_layout()

		_, ok := widget_test_layout_node("dialog-scrim-closed")
		testing.expect(t, !ok)
	})
}

@(test)
dialog_content_skips_layout_when_closed :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Dialog({
			config = {id = "dialog-content-closed"},
			open = false,
			child = proc(_: Dialog_State) {
				Dialog_Content({
					config = {width = set.Width(f32(200)), height = set.Height(f32(120))},
				})
			},
		})
		widget_test_finish_layout()

		found_overlay_content := false
		for &n in o.state.ui.layout.nodes {
			if n.space == .OVERLAY && n.kind == .DIALOG_CONTENT {
				found_overlay_content = true
				break
			}
		}
		testing.expect(t, !found_overlay_content)
	})
}

@(test)
dialog_compound_overlay_layouts_when_open :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		dialog_test_open_root(proc(_: Dialog_State) {
			Dialog_Trigger({config = {id = "dialog-trigger"}})
			Dialog_Scrim({config = {id = "dialog-scrim"}})
			Dialog_Content({
				config = {width = set.Width(f32(240)), height = set.Height(f32(120))},
				child = proc(_: Dialog_Content_Props_State) {},
			})
		})
		widget_test_finish_layout()

		scrim_ok := false
		for &n in o.state.ui.layout.nodes {
			if n.space != .OVERLAY do continue
			if n.kind == .DIALOG_SCRIM do scrim_ok = true
		}
		testing.expect(t, scrim_ok)

		content_node, content_ok := dialog_test_find_overlay_kind(.DIALOG_CONTENT)
		testing.expect(t, content_ok)
		if content_ok {
			testing.expect(t, content_node.space == .OVERLAY)
		}
	})
}

@(private)
dialog_test_dismiss_open := true

@(private)
dialog_test_dismiss_tree :: proc() {
	Dialog({
		config = {id = "dialog-dismiss"},
		open = dialog_test_dismiss_open,
		on_open_change = proc(open: bool) {
			dialog_test_dismiss_open = open
		},
		child = proc(_: Dialog_State) {
			Dialog_Scrim({config = {id = "dialog-dismiss-scrim"}})
			Dialog_Content({
				config = {width = set.Width(f32(240)), height = set.Height(f32(120))},
				child = proc(_: Dialog_Content_Props_State) {},
			})
		},
	})
}

@(test)
dialog_content_click_does_not_dismiss :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		dialog_test_dismiss_open = true

		widget_test_begin_layout()
		defer widget_test_end_frame()

		dialog_test_dismiss_tree()
		widget_test_finish_layout()

		content, content_ok := dialog_test_find_overlay_kind(.DIALOG_CONTENT)
		testing.expect(t, content_ok)
		if !content_ok do return
		testing.expect(t, content.rect.w > 0 && content.rect.h > 0)

		o.w_ctx.mouse_x = content.rect.x + content.rect.w * 0.5
		o.w_ctx.mouse_y = content.rect.y + content.rect.h * 0.5
		widget_test_begin_draw()

		o.w_ctx.left_mouse.pressed = true
		o.w_ctx.left_mouse.down = true
		dialog_test_dismiss_tree()

		testing.expect(t, dialog_test_dismiss_open)
	})
}

@(test)
dialog_scrim_click_dismisses :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		dialog_test_dismiss_open = true

		widget_test_begin_layout()
		defer widget_test_end_frame()

		dialog_test_dismiss_tree()
		widget_test_finish_layout()

		content, content_ok := dialog_test_find_overlay_kind(.DIALOG_CONTENT)
		testing.expect(t, content_ok)
		if !content_ok do return

		// Corner of the viewport — outside the centered content panel.
		o.w_ctx.mouse_x = 2
		o.w_ctx.mouse_y = 2
		testing.expect(
			t,
			o.w_ctx.mouse_x < content.rect.x ||
			o.w_ctx.mouse_y < content.rect.y ||
			o.w_ctx.mouse_x >= content.rect.x + content.rect.w ||
			o.w_ctx.mouse_y >= content.rect.y + content.rect.h,
		)

		widget_test_begin_draw()

		o.w_ctx.left_mouse.pressed = true
		o.w_ctx.left_mouse.down = true
		dialog_test_dismiss_tree()

		testing.expect(t, !dialog_test_dismiss_open)
	})
}

@(private)
dialog_test_actions_open := true

@(private)
dialog_test_actions_clicked := 0

@(private)
dialog_test_cancel_override: proc(event: Button_Event)

@(private)
dialog_test_action_on_click :: proc(event: Button_Event) {
	_ = event
	dialog_test_actions_clicked += 1
}

@(private)
dialog_test_cancel_override_on_click :: proc(event: Button_Event) {
	_ = event
	dialog_test_actions_clicked += 1
}

@(private)
dialog_test_actions_content :: proc(_: Dialog_Content_Props_State) {
	Dialog_Cancel({
		config = {
			id = "dialog-actions-cancel",
			width = set.Width(f32(80)),
			height = set.Height(f32(28)),
			tabbable = set.Tabbable(true),
		},
		on_click = dialog_test_cancel_override,
	})
	Dialog_Action({
		config = {
			id = "dialog-actions-action",
			width = set.Width(f32(80)),
			height = set.Height(f32(28)),
			tabbable = set.Tabbable(true),
		},
		on_click = dialog_test_action_on_click,
	})
}

@(private)
dialog_test_actions_child :: proc(_: Dialog_State) {
	Dialog_Content({
		config = {width = set.Width(f32(280)), height = set.Height(f32(140))},
		child = dialog_test_actions_content,
	})
}

@(private)
dialog_test_actions_tree :: proc() {
	Dialog({
		config = {id = "dialog-actions"},
		open = dialog_test_actions_open,
		on_open_change = proc(open: bool) {
			dialog_test_actions_open = open
		},
		child = dialog_test_actions_child,
	})
}

@(test)
dialog_action_and_cancel_register_as_buttons :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		dialog_test_actions_open = true
		dialog_test_cancel_override = nil
		widget_test_begin_layout()
		defer widget_test_end_frame()

		dialog_test_actions_tree()
		widget_test_finish_layout()

		button_count := 0

		for &n in o.state.ui.layout.nodes {
			if n.kind == .BUTTON {
				button_count += 1
			}
		}

		testing.expect_value(t, button_count, 2)
		expect_registered_id(t, "dialog-actions-cancel")
		expect_registered_id(t, "dialog-actions-action")
	})
}

@(test)
dialog_cancel_closes_by_default :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		dialog_test_actions_open = true
		dialog_test_cancel_override = nil
		widget_test_begin_layout()
		defer widget_test_end_frame()

		dialog_test_actions_tree()
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("dialog-actions-cancel")
		o.w_ctx.keys[int(o.Scancode.RETURN)] = {down = true, pressed = true}
		dialog_test_actions_tree()

		testing.expect(t, !dialog_test_actions_open)
	})
}

@(test)
dialog_cancel_on_click_overrides_close :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		dialog_test_actions_open = true
		dialog_test_actions_clicked = 0
		dialog_test_cancel_override = dialog_test_cancel_override_on_click
		widget_test_begin_layout()
		defer widget_test_end_frame()

		dialog_test_actions_tree()
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("dialog-actions-cancel")
		o.w_ctx.keys[int(o.Scancode.RETURN)] = {down = true, pressed = true}
		dialog_test_actions_tree()

		testing.expect(t, dialog_test_actions_open)
		testing.expect_value(t, dialog_test_actions_clicked, 1)
	})
}

@(test)
dialog_action_does_not_close_by_default :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		dialog_test_actions_open = true
		dialog_test_actions_clicked = 0
		dialog_test_cancel_override = nil
		widget_test_begin_layout()
		defer widget_test_end_frame()

		dialog_test_actions_tree()
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("dialog-actions-action")
		o.w_ctx.keys[int(o.Scancode.RETURN)] = {down = true, pressed = true}
		dialog_test_actions_tree()

		testing.expect(t, dialog_test_actions_open)
		testing.expect_value(t, dialog_test_actions_clicked, 1)
	})
}

@(test)
dialog_overlay_panel_joins_paint_list_overlay :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Rectangle({config = {id = "screen-under", width = set.Width(f32(100)), height = set.Height(f32(100))}})
		dialog_test_panel(
			{config = {id = "dialog-paint", width = set.Width(f32(100)), height = set.Height(f32(100))}},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()

		node, ok := widget_test_layout_node("dialog-paint")
		testing.expect(t, ok)
		if !ok do return

		found := false
		for idx in o.state.ui.layout.paint_list_overlay {
			if &o.state.ui.layout.nodes[idx] == node {
				found = true
				break
			}
		}
		testing.expect(t, found)
	})
}
