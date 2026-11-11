#+test
package oni_widgets

import o ".."
import set "../set"
import "core:testing"
import "core:reflect"

@(private) menubar_test_value: string
@(private) menubar_test_changes: int
@(private) menubar_test_actions: int
@(private) menubar_test_checked: bool
@(private) menubar_test_radio: string
@(private) menubar_test_config: Menubar_Config
@(private) menubar_test_cancel: bool
@(private) menubar_test_content_config: Menubar_Content_Config

@(test)
menubar_configs_are_data_and_props_contain_only_config_and_procedures :: proc(t: ^testing.T) {
	for T in ([]typeid {
		Menubar_Config, Menubar_Menu_Config, Menubar_Sub_Config, Menubar_Content_Config,
		Menubar_Item_Config, Menubar_Radio_Group_Config, Menubar_Group_Config, Menubar_Label_Config,
	}) {
		for field in reflect.struct_fields_zipped(T) {
			testing.expect(t, !reflect.is_procedure(field.type), field.name)
		}
	}
	for T in ([]typeid {
		Menubar_Props, Menubar_Menu_Props, Menubar_Sub_Props, Menubar_Content_Props,
		Menubar_Item_Props, Menubar_Radio_Group_Props, Menubar_Group_Props, Menubar_Label_Props,
	}) {
		for field in reflect.struct_fields_zipped(T) {
			if field.name == "config" do continue
			testing.expect(t, reflect.is_procedure(field.type), field.name)
		}
	}
}

@(test)
menubar_typeahead_matches_unicode_case_without_byte_length_assumptions :: proc(t: ^testing.T) {
	testing.expect(t, menubar_prefix_matches("Édition", "éD"))
	testing.expect(t, menubar_prefix_matches("Kelvin", "ke"))
	testing.expect(t, menubar_prefix_matches("共有", "共"))
	testing.expect(t, !menubar_prefix_matches("A", "Alice"))
	testing.expect(t, !menubar_prefix_matches("File", "Edit"))
}

@(private)
menubar_test_tree :: proc() {
	cfg := menubar_test_config
	cfg.id = "bar"
	cfg.value = menubar_test_value
	Menubar({
		config = cfg,
		on_value_change = proc(value: string) {
			menubar_test_value = value
			menubar_test_changes += 1
		},
		child = proc(_: Menubar_State) {
			Menubar_Menu({config = {value = "file"}, child = proc(_: Menubar_Menu_State) {
				Menubar_Trigger({config = {id = "file", text_value = "File"}})
				content_cfg := menubar_test_content_config
				content_cfg.id = "file_panel"
				Menubar_Content({config = content_cfg, child = proc(_: Menubar_Content_State) {
					Menubar_Item({config = {id = "new", text_value = "New"}, on_select = proc(_: Menubar_Item_Event) -> bool {
						menubar_test_actions += 1
						return !menubar_test_cancel
					}})
					Menubar_Item({config = {id = "disabled", text_value = "Disabled", disabled = set.Disabled(true)}})
					Menubar_Checkbox_Item({config = {id = "check", text_value = "Toolbar", checked = menubar_test_checked, close_on_select = set.Bool(false)}, on_checked_change = proc(checked: bool) {
						menubar_test_checked = checked
					}})
					Menubar_Sub({config = {id = "share"}, child = proc(_: Menubar_Sub_State) {
						Menubar_Sub_Trigger({config = {id = "share_trigger", text_value = "Share"}})
						Menubar_Sub_Content({config = {id = "share_panel"}, child = proc(_: Menubar_Content_State) {
							Menubar_Item({config = {id = "email", text_value = "Email"}})
						}})
					}})
					Menubar_Radio_Group({config = {value = menubar_test_radio}, on_value_change = proc(value: string) {
						menubar_test_radio = value
					}, child = proc(_: Menubar_Radio_Group_State) {
						Menubar_Radio_Item({config = {id = "radio_a", value = "a", text_value = "Alice"}})
						Menubar_Radio_Item({config = {id = "radio_b", value = "b", text_value = "Bob"}})
					}})
				}})
			}})
			Menubar_Menu({config = {value = "edit"}, child = proc(_: Menubar_Menu_State) {
				Menubar_Trigger({config = {id = "edit", text_value = "Edit"}})
				Menubar_Content({config = {id = "edit_panel"}, child = proc(_: Menubar_Content_State) {
					Menubar_Item({config = {id = "undo", text_value = "Undo"}})
				}})
			}})
		},
	})
}

@(test)
menubar_keyboard_reveals_items_in_scrollable_content :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_content_config.height = set.Height(f32(80))
		defer menubar_test_content_config = {}
		menubar_test_value = "file"
		menubar_test_layout()
		FocusElement("new")
		widget_test_press_shortcut(.END)
		menubar_test_draw()
		testing.expectf(t, o.widget_scroll_get("file_panel").y > 0, "scroll=%v", o.widget_scroll_get("file_panel"))
		o.w_ctx.keys = {}
		menubar_test_layout()
		menubar_test_draw()
		id := menubar_test_entry_id("radio_b")
		rect := o.ui_layout_rect(id)
		clip := o.ui_layout_clip_rect(id)
		testing.expectf(t, rect.y >= clip.y && rect.y + rect.h <= clip.y + clip.h + 0.01, "rect=%v clip=%v", rect, clip)
	})
}

@(test)
menubar_popup_focus_is_allowed_inside_its_modal_scope :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_value = "file"
		widget_test_begin_layout()
		Button({config = {id = "background", tabbable = set.Tabbable(true)}})
		scope := o.widget_focus_scope_begin("modal")
		menubar_test_tree()
		o.widget_focus_scope_end(scope)
		widget_test_finish_layout()
		widget_test_begin_draw()
		menubar_test_tree()
		testing.expect(t, FocusElement("new"))
		testing.expect(t, !FocusElement("background"))
		widget_test_end_frame()
		menubar_test_layout()
		menubar_test_draw()
	})
}

@(test)
menubar_scoped_value_is_inert_outside_root :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		value, ok := Menubar_Get_Value()
		testing.expect(t, !ok && value == "")
		widget_test_begin_layout()
		Menubar_Item({config = {id = "orphan", text_value = "Ignored"}})
		Menubar_Content({config = {id = "orphan_panel"}})
		widget_test_finish_layout()
		testing.expect_value(t, len(o.state.ui.layout.nodes), 0)
		widget_test_begin_draw()
		widget_test_end_frame()
	})
}

@(private)
menubar_test_entry_id :: proc(key: string) -> o.UI_Id {
	for _, runtime in o.w_ctx.menubars {
		for entry in runtime.entries {
			if entry.key == key do return entry.id
		}
	}

	return 0
}

@(test)
menubar_rtl_reverses_arrows_and_layout :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_config.navigation_direction = .RTL
		defer menubar_test_config = {}
		menubar_test_value = ""
		menubar_test_layout()
		FocusElement("file")
		widget_test_press_shortcut(.LEFT)
		menubar_test_draw()
		key, _ := GetElementById("edit")
		testing.expect_value(t, o.w_ctx.focused_id, key)
		testing.expect_value(t, menubar_test_value, "")
		node, found := widget_test_layout_node("bar")
		testing.expect(t, found)
		if found do testing.expect_value(t, node.config.direction, o.Direction_Layout.HORIZONTAL_REVERSE)
	})
}

@(test)
menubar_loop_off_stops_at_edge :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_config.loop = .OFF
		defer menubar_test_config = {}
		menubar_test_value = ""
		menubar_test_layout()
		FocusElement("edit")
		widget_test_press_shortcut(.RIGHT)
		menubar_test_draw()
		key, _ := GetElementById("edit")
		testing.expect_value(t, o.w_ctx.focused_id, key)
	})
}

@(test)
menubar_cancelled_selection_keeps_menu_open :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_cancel = true
		defer menubar_test_cancel = false
		menubar_test_value = "file"
		menubar_test_layout()
		FocusElement("new")
		widget_test_press_shortcut(.RETURN)
		menubar_test_draw()
		testing.expect_value(t, menubar_test_value, "file")
		key, _ := GetElementById("new")
		testing.expect_value(t, o.w_ctx.focused_id, key)
	})
}

@(test)
menubar_disabled_root_has_no_tab_stop_or_popup :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_config.disabled = set.Disabled(true)
		defer menubar_test_config = {}
		menubar_test_value = "file"
		menubar_test_layout()
		expect_in_tab_order(t, "file", false)
		expect_in_tab_order(t, "edit", false)
		testing.expect_value(t, len(o.state.ui.layout.popup_anchors), 0)
		menubar_test_draw()
	})
}

@(test)
menubar_top_trigger_hover_switches_only_while_open :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_value = "file"
		menubar_test_layout()
		edit := o.ui_layout_rect(menubar_test_entry_id("edit"))
		o.w_ctx.mouse_x = edit.x + edit.w * 0.5
		o.w_ctx.mouse_y = edit.y + edit.h * 0.5
		o.w_ctx.mouse_moved = true
		menubar_test_draw()
		testing.expect_value(t, menubar_test_value, "edit")
	})
}

@(test)
menubar_popup_remains_inside_viewport :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_value = "file"
		menubar_test_layout()
		menubar_test_draw()
		rect := o.ui_layout_rect(o.state.ui.layout.popup_anchors[0].floating_id)
		testing.expect(t, rect.w >= 192 && rect.h > 0)
		testing.expectf(t, rect.x >= 8 && rect.y >= 8, "popup rect=%v anchors=%v", rect, o.state.ui.layout.popup_anchors[:])
		testing.expect(t, rect.x + rect.w <= 792 && rect.y + rect.h <= 592)
	})
}

@(test)
menubar_radio_selection_is_controlled :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_value = "file"
		menubar_test_radio = "a"
		menubar_test_layout()
		FocusElement("radio_b")
		widget_test_press_shortcut(.RETURN)
		menubar_test_draw()
		testing.expect_value(t, menubar_test_radio, "b")
		testing.expect_value(t, menubar_test_value, "")
	})
}

@(test)
menubar_arrows_switch_top_menus_and_wrap :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_value = "file"
		menubar_test_layout()
		FocusElement("new")
		widget_test_press_shortcut(.RIGHT)
		menubar_test_draw()
		testing.expect_value(t, menubar_test_value, "edit")
		o.w_ctx.keys = {}
		menubar_test_layout()
		menubar_test_draw()
		key, _ := GetElementById("undo")
		testing.expect_value(t, o.w_ctx.focused_id, key)
		menubar_test_layout()
		widget_test_press_shortcut(.RIGHT)
		menubar_test_draw()
		testing.expect_value(t, menubar_test_value, "file")
	})
}

@(test)
menubar_escape_root_restores_trigger :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_value = "file"
		menubar_test_layout()
		FocusElement("new")
		widget_test_press_shortcut(.ESCAPE)
		menubar_test_draw()
		testing.expect_value(t, menubar_test_value, "")
		key, _ := GetElementById("file")
		testing.expect_value(t, o.w_ctx.focused_id, key)
		testing.expect(t, o.shortcut_key_consumed(.ESCAPE))
	})
}

@(test)
menubar_typeahead_and_home_end :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_value = "file"
		menubar_test_layout()
		FocusElement("new")
		o.state.input.text_input = make([dynamic]u8)
		defer delete(o.state.input.text_input)
		append(&o.state.input.text_input, u8('t'))
		menubar_test_draw()
		key, _ := GetElementById("check")
		testing.expect_value(t, o.w_ctx.focused_id, key)
		clear(&o.state.input.text_input)
		menubar_test_layout()
		widget_test_press_shortcut(.END)
		menubar_test_draw()
		key, _ = GetElementById("radio_b")
		testing.expect_value(t, o.w_ctx.focused_id, key)
	})
}

@(test)
menubar_tab_leaves_popup_for_following_control :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_value = "file"
		widget_test_begin_layout()
		Button({config = {id = "before", tabbable = set.Tabbable(true)}})
		menubar_test_tree()
		Button({config = {id = "after", tabbable = set.Tabbable(true)}})
		widget_test_finish_layout()
		FocusElement("new")
		widget_test_press_shortcut(.TAB)
		widget_test_begin_draw()
		Button({config = {id = "before", tabbable = set.Tabbable(true)}})
		menubar_test_tree()
		Button({config = {id = "after", tabbable = set.Tabbable(true)}})
		widget_test_end_frame()
		key, _ := GetElementById("after")
		testing.expect_value(t, o.w_ctx.focused_id, key)
		testing.expect_value(t, menubar_test_value, "")
	})
}

@(test)
menubar_outside_press_closes_without_stealing_focus :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_value = "file"
		menubar_test_layout()
		FocusElement("new")
		widget_test_begin_draw()
		o.w_ctx.mouse_x = 790
		o.w_ctx.mouse_y = 590
		o.w_ctx.left_mouse.pressed = true
		menubar_test_tree()
		widget_test_end_frame()
		testing.expect_value(t, menubar_test_value, "")
	})
}

@(test)
menubar_unmounted_roots_release_runtime :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_value = "file"
		menubar_test_layout()
		menubar_test_draw()
		testing.expect_value(t, len(o.w_ctx.menubars), 1)
		for _ in 0 ..< 2 {
			widget_test_begin_layout()
			widget_test_finish_layout()
			widget_test_begin_draw()
			widget_test_end_frame()
		}
		testing.expect_value(t, len(o.w_ctx.menubars), 0)
	})
}

@(private)
menubar_test_layout :: proc() {
	widget_test_begin_layout()
	menubar_test_tree()
	widget_test_finish_layout()
}

@(private)
menubar_test_draw :: proc() {
	widget_test_begin_draw()
	menubar_test_tree()
	widget_test_end_frame()
}

@(test)
menubar_closed_has_one_tab_stop :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_value = ""
		menubar_test_layout()
		expect_in_tab_order(t, "file", true)
		expect_in_tab_order(t, "edit", false)
		testing.expect_value(t, len(o.state.ui.layout.popup_anchors), 0)
		menubar_test_draw()
	})
}

@(test)
menubar_keyboard_opens_and_skips_disabled :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_value = ""
		menubar_test_changes = 0
		menubar_test_layout()
		FocusElement("file")
		widget_test_press_shortcut(.DOWN)
		menubar_test_draw()
		testing.expect_value(t, menubar_test_value, "file")
		testing.expect_value(t, menubar_test_changes, 1)
		o.w_ctx.keys = {}
		menubar_test_layout()
		menubar_test_draw()
		key, _ := GetElementById("new")
		testing.expect_value(t, o.w_ctx.focused_id, key)
		menubar_test_layout()
		widget_test_press_shortcut(.DOWN)
		menubar_test_draw()
		key, _ = GetElementById("check")
		testing.expect_value(t, o.w_ctx.focused_id, key)
	})
}

@(test)
menubar_selection_closes_and_restores_focus :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_value = "file"
		menubar_test_actions = 0
		menubar_test_layout()
		FocusElement("new")
		widget_test_press_shortcut(.RETURN)
		menubar_test_draw()
		testing.expect_value(t, menubar_test_actions, 1)
		testing.expect_value(t, menubar_test_value, "")
		key, _ := GetElementById("file")
		testing.expect_value(t, o.w_ctx.focused_id, key)
	})
}

@(test)
menubar_checkbox_is_controlled_and_can_stay_open :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_value = "file"
		menubar_test_checked = false
		menubar_test_layout()
		FocusElement("check")
		widget_test_press_shortcut(.SPACE)
		menubar_test_draw()
		testing.expect(t, menubar_test_checked)
		testing.expect_value(t, menubar_test_value, "file")
	})
}

@(test)
menubar_submenu_escape_closes_one_level :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		menubar_test_value = "file"
		menubar_test_layout()
		FocusElement("share_trigger")
		widget_test_press_shortcut(.RIGHT)
		menubar_test_draw()
		o.w_ctx.keys = {}
		menubar_test_layout()
		menubar_test_draw()
		key, _ := GetElementById("email")
		testing.expect_value(t, o.w_ctx.focused_id, key)
		menubar_test_layout()
		widget_test_press_shortcut(.ESCAPE)
		menubar_test_draw()
		testing.expect_value(t, menubar_test_value, "file")
		key, _ = GetElementById("share_trigger")
		testing.expect_value(t, o.w_ctx.focused_id, key)
	})
}
