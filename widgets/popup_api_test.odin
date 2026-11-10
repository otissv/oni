#+test
package oni_widgets

import o ".."
import set "../set"
import "core:testing"

@(private)
popup_api_changes: int

@(private)
popup_api_on_change :: proc(_: bool) {
	popup_api_changes += 1
}

@(test)
popup_control_is_owned_idempotent_and_rejects_stale_handles :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer popover_shutdown()
		popup_api_changes = 0
		outer := popover_ctx_push({popover_key = "outer", on_open_change = popup_api_on_control_change})
		inner := popover_ctx_push({popover_key = "inner"})
		Popover_Set_Open(outer, true)
		Popover_Set_Open(outer, true)
		testing.expect(t, Popover_Is_Open(outer))
		testing.expect(t, !Popover_Is_Open(inner))
		testing.expect_value(t, popup_api_changes, 1)
		popover_ctx_pop()
		replacement := popover_ctx_push({popover_key = "replacement"})
		Popover_Set_Open(inner, true)
		testing.expect(t, !Popover_Is_Open(replacement))
		Popover_Toggle(outer)
		testing.expect(t, !Popover_Is_Open(outer))
		testing.expect_value(t, popup_api_changes, 2)
		popover_ctx_pop()
		popover_ctx_pop()
		Popover_Set_Open(outer, true)
		testing.expect_value(t, popup_api_changes, 2)
	})
}

@(test)
popup_dismissal_obeys_disabled_consumption_and_pointer_ownership :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer popover_shutdown()
		popup_api_changes = 0
		outer := popover_ctx_push({popover_key = "outer", open = true})
		inner := popover_ctx_push({popover_key = "inner", open = true, on_open_change = popup_api_on_control_change})
		Popover_Claim_Pointer(inner)
		o.w_ctx.left_mouse.pressed = true
		Popover_Process_Dismissal(inner)
		Popover_Process_Dismissal(outer)
		testing.expect(t, Popover_Is_Open(inner) && Popover_Is_Open(outer))
		o.w_ctx.left_mouse.pressed = false
		widget_test_press_shortcut(.ESCAPE)
		Popover_Process_Dismissal(outer)
		testing.expect(t, Popover_Is_Open(inner) && Popover_Is_Open(outer))
		Popover_Process_Dismissal(inner)
		Popover_Process_Dismissal(outer)
		testing.expect(t, !Popover_Is_Open(inner) && Popover_Is_Open(outer))
		testing.expect_value(t, popup_api_changes, 1)
		popover_ctx_pop()
		popover_ctx_pop()

		disabled := popover_ctx_push({popover_key = "disabled", open = true, disabled = true})
		widget_test_press_shortcut(.ESCAPE)
		Popover_Process_Dismissal(disabled)
		Popover_Toggle(disabled)
		testing.expect(t, Popover_Is_Open(disabled))
		testing.expect(t, !o.shortcut_key_consumed(.ESCAPE))
		popover_ctx_pop()
	})
}

@(test)
select_keyboard_escape_is_owned_by_shared_popup_dismissal :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer popover_shutdown()
		defer select_shutdown()
		select_ctx_push({select_key = "select", open = true, on_open_change = popup_api_on_change})
		defer select_ctx_pop()
		popup := popover_ctx_push({popover_key = "popup", open = true, on_open_change = select_on_popover_open_change})
		defer popover_ctx_pop()
		select_ctx_top().popup = popup
		popup_api_changes = 0
		widget_test_press_shortcut(.ESCAPE)
		select_handle_typing_keys()
		testing.expect(t, select_ctx_top().open)
		testing.expect(t, !o.shortcut_key_consumed(.ESCAPE))
		Popover_Process_Dismissal(popup)
		testing.expect(t, !select_ctx_top().open)
		testing.expect(t, o.shortcut_key_consumed(.ESCAPE))
		testing.expect_value(t, popup_api_changes, 1)
	})
}

@(test)
inline_select_never_controls_or_claims_enclosing_popup :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer popover_shutdown()
		defer select_shutdown()
		outer := popover_ctx_push({popover_key = "outer", open = true})
		defer popover_ctx_pop()
		select_ctx_push({listbox = true})
		defer select_ctx_pop()
		select_toggle_open()
		select_set_open(false)
		select_note_pointer()
		testing.expect(t, Popover_Is_Open(outer))
		testing.expect(t, !popover_ctx_top().pointer_owned)
	})
}

@(test)
context_menu_uses_shared_popup_control_and_right_press_dismissal :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer popover_shutdown()
		defer context_menu_shutdown()
		outer := popover_ctx_push({popover_key = "outer", open = true})
		context_menu_ctx_push({menu_key = "menu", open = true, on_open_change = popup_api_on_change})
		popup := context_menu_ctx_top().popup
		popup_api_changes = 0
		context_menu_note_pointer()
		o.w_ctx.right_mouse.pressed = true
		Popover_Process_Dismissal(popup)
		Popover_Process_Dismissal(outer)
		testing.expect(t, Popover_Is_Open(popup) && Popover_Is_Open(outer))
		o.w_ctx.right_mouse.pressed = false
		widget_test_press_shortcut(.ESCAPE)
		Popover_Process_Dismissal(popup)
		testing.expect(t, !context_menu_ctx_top().open)
		testing.expect_value(t, popup_api_changes, 1)
		context_menu_ctx_pop()
		Popover_Process_Dismissal(outer)
		testing.expect(t, Popover_Is_Open(outer))
		popover_ctx_pop()

		context_menu_ctx_push({menu_key = "menu", open = true})
		o.w_ctx.right_mouse.pressed = true
		Popover_Process_Dismissal(context_menu_ctx_top().popup)
		testing.expect(t, !context_menu_ctx_top().open)
		context_menu_ctx_pop()
	})
}

@(test)
date_picker_keyboard_escape_is_owned_by_shared_popup_dismissal :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer popover_shutdown()
		defer date_picker_shutdown()
		date_picker_ctx_push({picker_key = "date", open = true, on_open_change = popup_api_on_change})
		defer date_picker_ctx_pop()
		popup := popover_ctx_push({popover_key = "popup", open = true, on_open_change = date_picker_on_popover_open_change})
		defer popover_ctx_pop()
		date_picker_ctx_top().popup = popup
		popup_api_changes = 0
		widget_test_press_shortcut(.ESCAPE)
		date_picker_handle_keys()
		testing.expect(t, date_picker_ctx_top().open)
		testing.expect(t, !o.shortcut_key_consumed(.ESCAPE))
		Popover_Process_Dismissal(popup)
		testing.expect(t, !date_picker_ctx_top().open)
		testing.expect_value(t, popup_api_changes, 1)
	})
}

@(test)
popup_control_notifies_its_composite_owner_under_nested_selects :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer popover_shutdown()
		defer select_shutdown()
		select_ctx_push({select_key = "outer", on_open_change = popup_api_on_change})
		outer_ctx := select_ctx_top()
		outer := popover_ctx_push({on_open_change = select_on_popover_open_change})
		outer_ctx.popup = outer
		select_ctx_push({select_key = "inner"})
		inner := popover_ctx_push({on_open_change = select_on_popover_open_change})
		select_ctx_top().popup = inner
		popup_api_changes = 0
		Popover_Set_Open(outer, true)
		testing.expect(t, outer_ctx.open)
		testing.expect(t, !select_ctx_top().open)
		testing.expect_value(t, popup_api_changes, 1)
		popover_ctx_pop()
		select_ctx_pop()
		popover_ctx_pop()
		select_ctx_pop()
	})
}

@(test)
expired_popup_handles_cannot_claim_pointer_or_register_triggers :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		stale := popover_ctx_push({open = true})
		popover_shutdown()
		current := popover_ctx_push({open = true})
		Popover_Claim_Pointer(stale)
		popover_set_trigger(stale, "wrong", o.ui_id("wrong"), {})
		widget_test_press_shortcut(.ESCAPE)
		Popover_Process_Dismissal(stale)
		testing.expect(t, !o.shortcut_key_consumed(.ESCAPE))
		testing.expect(t, !popover_ctx_top().pointer_owned)
		testing.expect(t, !popover_ctx_top().has_trigger)
		testing.expect(t, Popover_Is_Open(current))
		popover_ctx_pop()
	})
}

@(private)
popup_api_on_control_change :: proc(_: Popover_Handle, open: bool) {
	popup_api_on_change(open)
}

@(private)
popup_api_outer_open, popup_api_menu_open, popup_api_select_open: bool

@(private)
popup_api_nested_tree :: proc() {
	Popover({
		config = {id = "popup-outer", open = popup_api_outer_open},
		on_open_change = proc(open: bool) { popup_api_outer_open = open },
		child = proc(_: Popover_State) {
			Context_Menu({
				config = {id = "popup-menu", open = popup_api_menu_open},
				on_open_change = proc(open: bool) { popup_api_menu_open = open },
				child = proc(_: Context_Menu_State) {
					Select({
						config = {id = "popup-select", open = popup_api_select_open},
						on_open_change = proc(open: bool) {
							popup_api_select_open = open
							popup_api_changes += 1
						},
						child = proc(_: Select_State) {
							Select_Trigger({
								config = {id = "popup-select-trigger", width = set.Width(f32(120)), height = set.Height(f32(30))},
							})
						},
						content = proc(_: Select_State) {
							Option({
								config = {id = "popup-option", value = "a", text = "A", width = set.Width(f32(100)), height = set.Height(f32(30))},
							})
						},
					})
				},
			})
		},
	})
}

@(test)
nested_popup_tree_escape_dismisses_only_select_once :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		popup_api_outer_open, popup_api_menu_open, popup_api_select_open = true, true, true
		popup_api_changes = 0
		widget_test_begin_layout()
		defer widget_test_end_frame()
		popup_api_nested_tree()
		widget_test_finish_layout()
		widget_test_begin_draw()
		widget_test_press_shortcut(.ESCAPE)
		popup_api_nested_tree()
		testing.expect(t, !popup_api_select_open)
		testing.expect(t, popup_api_menu_open && popup_api_outer_open)
		testing.expect_value(t, popup_api_changes, 1)
		testing.expect(t, o.shortcut_key_consumed(.ESCAPE))
		testing.expect_value(t, popover_ctx_depth, 0)
	})
}

@(test)
nested_popup_tree_option_hit_keeps_ancestor_popups_open :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		popup_api_outer_open, popup_api_menu_open, popup_api_select_open = true, true, true
		popup_api_changes = 0
		widget_test_begin_layout()
		defer widget_test_end_frame()
		popup_api_nested_tree()
		widget_test_finish_layout()
		option: ^o.Layout_Node
		for &node in o.state.ui.layout.nodes {
			if node.kind == .OPTION {
				option = &node
				break
			}
		}
		testing.expect(t, option != nil)
		if option == nil do return
		widget_test_begin_draw()
		o.w_ctx.mouse_x = option.rect.x + option.rect.w / 2
		o.w_ctx.mouse_y = option.rect.y + option.rect.h / 2
		o.layout_resolve_pointer_hit()
		o.w_ctx.left_mouse.pressed = true
		popup_api_nested_tree()
		testing.expect(t, popup_api_outer_open && popup_api_menu_open)
		testing.expect(t, popup_api_select_open)
		testing.expect_value(t, popup_api_changes, 0)
		testing.expect_value(t, popover_ctx_depth, 0)
	})
}

@(private)
popup_api_inline_preserved: bool

@(test)
inline_select_trigger_does_not_replace_enclosing_popup_anchor :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		popup_api_inline_preserved = false
		widget_test_begin_layout()
		defer widget_test_end_frame()
		Popover({
			config = {id = "inline-outer", open = true},
			child = proc(fs: Popover_State) {
				Popover_Trigger({config = {id = "inline-outer-trigger"}})
				Select({
					config = {id = "inline-list", size = 3},
					child = proc(_: Select_State) {
						Select_Trigger({config = {id = "inline-list-trigger"}})
					},
				})
				popup_api_inline_preserved = popover_context(fs.popup).trigger_key == "inline-outer-trigger"
			},
		})
		widget_test_finish_layout()
		testing.expect(t, popup_api_inline_preserved)
	})
}

@(test)
popup_consumed_escape_and_outside_press_policy_are_shared :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		popup := popover_ctx_push({open = true})
		widget_test_press_shortcut(.ESCAPE)
		o.state.shortcuts.consumed_keys[int(o.Scancode.ESCAPE)] = true
		Popover_Process_Dismissal(popup)
		testing.expect(t, Popover_Is_Open(popup))
		o.w_ctx.keys = {}
		o.w_ctx.right_mouse.pressed = true
		Popover_Process_Dismissal(popup)
		testing.expect(t, Popover_Is_Open(popup))
		o.w_ctx.left_mouse.pressed = true
		Popover_Process_Dismissal(popup)
		testing.expect(t, !Popover_Is_Open(popup))
		popover_ctx_pop()
	})
}

@(test)
context_menu_control_targets_outer_owner_and_cleans_its_anchor :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer context_menu_shutdown()
		context_menu_ctx_push({menu_key = "outer", open = true, on_open_change = popup_api_on_change})
		outer := context_menu_ctx_top()
		context_menu_store_anchor("outer", {1, 2})
		context_menu_ctx_push({menu_key = "inner", open = true})
		popup_api_changes = 0
		Popover_Set_Open(outer.popup, false)
		testing.expect(t, !outer.open)
		testing.expect(t, context_menu_ctx_top().open)
		_, anchored := context_menu_load_anchor("outer")
		testing.expect(t, !anchored)
		testing.expect_value(t, popup_api_changes, 1)
		context_menu_ctx_pop()
		context_menu_ctx_pop()
	})
}

@(test)
date_picker_control_targets_outer_owner :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		defer date_picker_shutdown()
		date_picker_ctx_push({picker_key = "outer", on_open_change = popup_api_on_change})
		outer := date_picker_ctx_top()
		outer.popup = popover_ctx_push({on_open_change = date_picker_on_popover_open_change})
		date_picker_ctx_push({picker_key = "inner"})
		inner := date_picker_ctx_top()
		inner.popup = popover_ctx_push({on_open_change = date_picker_on_popover_open_change})
		popup_api_changes = 0
		Popover_Set_Open(outer.popup, true)
		testing.expect(t, outer.open)
		testing.expect(t, !inner.open)
		testing.expect_value(t, popup_api_changes, 1)
		popover_ctx_pop()
		date_picker_ctx_pop()
		popover_ctx_pop()
		date_picker_ctx_pop()
	})
}
