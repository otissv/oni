package oni_widgets

import o ".."
import set "../set"
import "core:testing"
import sdl "vendor:sdl3"

@(private)
checkbox_test_changed: Checkbox_Value

@(private)
checkbox_test_change_count: int

@(private)
checkbox_test_click_count: int

@(private)
checkbox_test_click_key: o.Scancode

@(private)
checkbox_test_child_count: int

@(private)
checkbox_test_value: Checkbox_Value

@(private)
checkbox_test_on_change :: proc(checked: Checkbox_Value) {
	checkbox_test_changed = checked
	checkbox_test_change_count += 1
	checkbox_test_value = checked
}

@(private)
checkbox_test_on_click :: proc(event: Checkbox_Event) {
	checkbox_test_click_count += 1
	checkbox_test_click_key = event.key
}

@(private)
checkbox_test_child :: proc(_: Checkbox_State) {
	checkbox_test_child_count += 1
}

@(private)
checkbox_test_reset_events :: proc() {
	checkbox_test_changed = .FALSE
	checkbox_test_change_count = 0
	checkbox_test_click_count = 0
	checkbox_test_click_key = o.Scancode(0)
	checkbox_test_child_count = 0
	checkbox_test_value = .FALSE
}

@(test)
checkbox_next_value_covers_all_states :: proc(t: ^testing.T) {
	testing.expect(t, Checkbox_Next_Value(.FALSE) == .TRUE)
	testing.expect(t, Checkbox_Next_Value(.TRUE) == .FALSE)
	testing.expect(t, Checkbox_Next_Value(.INDETERMINATE) == .TRUE)
}

@(test)
checkbox_theme_base_sets_defaults :: proc(t: ^testing.T) {
	frame := Checkbox_State {
		checked = .FALSE,
	}
	base := checkbox_theme_base(&frame)

	testing.expect(t, base.kind == .CHECKBOX)
	testing.expect(t, o.cfg_style_bool(base.tabbable))
	testing.expect(t, base.border.mode == .Value)
	testing.expect(t, base.radius.mode == .Value)
}

@(test)
checkbox_layout_registers_kind_and_tab_order :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Checkbox({config = {id = "checkbox-layout"}, checked = .FALSE})
		widget_test_finish_layout()

		expect_registered_id(t, "checkbox-layout")
		expect_layout_kind(t, "checkbox-layout", .CHECKBOX)
		expect_in_tab_order(t, "checkbox-layout", true)
	})
}

@(test)
checkbox_disabled_is_not_tabbable :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Checkbox({config = {id = "checkbox-disabled"}, checked = .FALSE, disabled = true})
		expect_in_tab_order(t, "checkbox-disabled", false)
		widget_test_finish_layout()
	})
}

@(test)
checkbox_config_disabled_blocks_activation :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		checkbox_test_reset_events()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		props := Checkbox_Props {
			config = {id = "checkbox-config-disabled", disabled = set.Disabled(true)},
			checked = .FALSE,
			on_checked_change = checkbox_test_on_change,
		}
		Checkbox(props)
		expect_in_tab_order(t, "checkbox-config-disabled", false)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("checkbox-config-disabled")
		o.w_ctx.keys[int(sdl.Scancode.SPACE)] = {
			down    = true,
			pressed = true,
		}
		Checkbox(props)

		testing.expect_value(t, checkbox_test_change_count, 0)
	})
}

@(test)
checkbox_keyboard_activation_reports_next_value :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		checkbox_test_reset_events()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		props := Checkbox_Props {
			config = {id = "checkbox-keyboard"},
			checked = .FALSE,
			on_checked_change = checkbox_test_on_change,
			on_click = checkbox_test_on_click,
		}
		Checkbox(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("checkbox-keyboard")
		o.w_ctx.keys[int(sdl.Scancode.SPACE)] = {
			down    = true,
			pressed = true,
		}
		Checkbox(props)

		testing.expect_value(t, checkbox_test_change_count, 1)
		testing.expect(t, checkbox_test_changed == .TRUE)
		testing.expect_value(t, checkbox_test_click_count, 1)
		testing.expect(t, checkbox_test_click_key == o.Scancode(sdl.Scancode.SPACE))
	})
}

@(test)
checkbox_activation_only_reports_change :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		checkbox_test_reset_events()
		checked := Checkbox_Value.INDETERMINATE
		widget_test_begin_layout()
		defer widget_test_end_frame()

		props := Checkbox_Props {
			config = {id = "checkbox-report"},
			checked = checked,
			on_checked_change = checkbox_test_on_change,
		}
		Checkbox(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("checkbox-report")
		o.w_ctx.keys[int(sdl.Scancode.SPACE)] = {
			down    = true,
			pressed = true,
		}
		Checkbox(props)

		testing.expect(t, checked == .INDETERMINATE)
		testing.expect_value(t, checkbox_test_change_count, 1)
		testing.expect(t, checkbox_test_changed == .TRUE)
	})
}

@(test)
checkbox_enter_does_not_activate :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		checkbox_test_reset_events()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		props := Checkbox_Props {
			config = {id = "checkbox-enter"},
			checked = .FALSE,
			on_checked_change = checkbox_test_on_change,
			on_click = checkbox_test_on_click,
		}
		Checkbox(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("checkbox-enter")
		o.w_ctx.keys[int(sdl.Scancode.RETURN)] = {
			down    = true,
			pressed = true,
		}
		Checkbox(props)

		testing.expect_value(t, checkbox_test_change_count, 0)
		testing.expect_value(t, checkbox_test_click_count, 0)
	})
}

@(test)
checkbox_pointer_release_activates_once :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		checkbox_test_reset_events()
		props := Checkbox_Props {
			config = {id = "checkbox-pointer"},
			checked = .FALSE,
			on_checked_change = checkbox_test_on_change,
			on_click = checkbox_test_on_click,
		}

		widget_test_begin_layout()
		Checkbox(props)
		widget_test_finish_layout()
		o.w_ctx.mouse_x = 8
		o.w_ctx.mouse_y = 8
		widget_test_begin_draw()
		o.w_ctx.left_mouse = {
			down    = true,
			pressed = true,
		}
		Checkbox(props)
		widget_test_end_frame()

		widget_test_begin_layout()
		Checkbox(props)
		widget_test_finish_layout()
		o.w_ctx.mouse_x = 8
		o.w_ctx.mouse_y = 8
		widget_test_begin_draw()
		o.w_ctx.left_mouse = {
			released = true,
		}
		Checkbox(props)
		widget_test_end_frame()

		testing.expect_value(t, checkbox_test_change_count, 1)
		testing.expect(t, checkbox_test_changed == .TRUE)
		testing.expect_value(t, checkbox_test_click_count, 1)
	})
}

@(test)
checkbox_disabled_blocks_keyboard_activation :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		checkbox_test_reset_events()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		props := Checkbox_Props {
			config = {id = "checkbox-disabled-keyboard"},
			checked = .FALSE,
			disabled = true,
			on_checked_change = checkbox_test_on_change,
		}
		Checkbox(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("checkbox-disabled-keyboard")
		o.w_ctx.keys[int(sdl.Scancode.SPACE)] = {
			down    = true,
			pressed = true,
		}
		Checkbox(props)

		testing.expect_value(t, checkbox_test_change_count, 0)
	})
}

@(test)
checkbox_mounting_blocks_activation_by_default :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		checkbox_test_reset_events()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		props := Checkbox_Props {
			config = {id = "checkbox-mounting"},
			checked = .FALSE,
			on_mount = proc(_: Checkbox_State) -> o.Mount {
				return .RUNNING
			},
			on_checked_change = checkbox_test_on_change,
		}
		Checkbox(props)
		expect_in_tab_order(t, "checkbox-mounting", false)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("checkbox-mounting")
		o.w_ctx.keys[int(sdl.Scancode.SPACE)] = {
			down    = true,
			pressed = true,
		}
		Checkbox(props)

		testing.expect_value(t, checkbox_test_change_count, 0)
	})
}

@(test)
checkbox_custom_indicator_only_runs_for_non_false_state :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		checkbox_test_reset_events()
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Checkbox(
			{
				config = {id = "checkbox-false-child"},
				checked = .FALSE,
				child = checkbox_test_child,
			},
		)
		Checkbox(
			{config = {id = "checkbox-true-child"}, checked = .TRUE, child = checkbox_test_child},
		)
		Checkbox(
			{
				config = {id = "checkbox-indeterminate-child"},
				checked = .INDETERMINATE,
				child = checkbox_test_child,
			},
		)
		widget_test_finish_layout()
		widget_test_begin_draw()
		Checkbox(
			{
				config = {id = "checkbox-false-child"},
				checked = .FALSE,
				child = checkbox_test_child,
			},
		)
		Checkbox(
			{config = {id = "checkbox-true-child"}, checked = .TRUE, child = checkbox_test_child},
		)
		Checkbox(
			{
				config = {id = "checkbox-indeterminate-child"},
				checked = .INDETERMINATE,
				child = checkbox_test_child,
			},
		)

		testing.expect_value(t, checkbox_test_child_count, 4)
	})
}

@(test)
checkbox_builtin_indicators_emit_expected_geometry :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			widget_test_begin_layout()
			defer widget_test_end_frame()

			Checkbox({config = {id = "checkbox-check"}, checked = .TRUE})
			Checkbox({config = {id = "checkbox-minus"}, checked = .INDETERMINATE})
			widget_test_finish_layout()
			widget_test_begin_draw()
			Checkbox({config = {id = "checkbox-check"}, checked = .TRUE})
			check_vertices := len(o.batch_current().vertices)
			Checkbox({config = {id = "checkbox-minus"}, checked = .INDETERMINATE})
			minus_vertices := len(o.batch_current().vertices) - check_vertices

			// Background + two check lines + border.
			testing.expect_value(t, check_vertices, 16)
			// Background + one indeterminate line + border.
			testing.expect_value(t, minus_vertices, 12)
		},
	)
}

@(test)
checkbox_unmount_skips_layout_node :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Checkbox({
			config = {id = "checkbox-unmount"},
			checked = .TRUE,
			unmount = true,
			on_unmount = proc(_: Checkbox_State) -> o.Mount {
				return .COMPLETED
			},
		})
		_, ok := widget_test_layout_node("checkbox-unmount")
		testing.expect(t, !ok)
		widget_test_finish_layout()
	})
}

@(test)
checkbox_caller_updates_value_after_change :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		checkbox_test_reset_events()

		props := Checkbox_Props {
			config = {id = "checkbox-caller-owned"},
			checked = checkbox_test_value,
			on_checked_change = checkbox_test_on_change,
		}

		widget_test_begin_layout()
		Checkbox(props)
		widget_test_finish_layout()
		widget_test_begin_draw()
		o.widget_set_focused_id("checkbox-caller-owned")
		o.w_ctx.keys[int(sdl.Scancode.SPACE)] = {
			down    = true,
			pressed = true,
		}
		Checkbox(props)
		widget_test_end_frame()

		testing.expect(t, checkbox_test_value == .TRUE)

		props.checked = checkbox_test_value
		widget_test_begin_layout()
		Checkbox(props)
		widget_test_finish_layout()
		expect_layout_kind(t, "checkbox-caller-owned", .CHECKBOX)
		widget_test_end_frame()
	})
}

@(test)
checkbox_config_override_preserves_kind :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		props := Checkbox_Props {
			config = {id = "checkbox-styled", background = set.Background(o.Color.ACCENT)},
			checked = .FALSE,
		}
		frame := Checkbox_State{}
		config := widget_config(props, &frame, checkbox_theme_base)

		testing.expect(t, config.kind == .CHECKBOX)
		testing.expect_value(t, config.id, "checkbox-styled")
	})
}

@(private)
checkbox_for_id_tree_label_first :: proc(props: Checkbox_Props) {
	_ = Text(
		{
			config = {
				id = "checkbox-for-label",
				text = "Remember me",
				for_id = "checkbox-for-target",
				width = set.Width(f32(120)),
				height = set.Height(f32(20)),
			},
		},
	)
	Checkbox(props)
}

@(private)
checkbox_for_id_tree_control_first :: proc(props: Checkbox_Props) {
	Checkbox(props)
	_ = Text(
		{
			config = {
				id = "checkbox-for-label",
				text = "Remember me",
				for_id = "checkbox-for-target",
				width = set.Width(f32(120)),
				height = set.Height(f32(20)),
			},
		},
	)
}

@(test)
checkbox_label_for_id_click_activates_when_label_first :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		checkbox_test_reset_events()
		props := Checkbox_Props {
			config = {id = "checkbox-for-target"},
			checked = .FALSE,
			on_checked_change = checkbox_test_on_change,
			on_click = checkbox_test_on_click,
		}

		widget_test_begin_layout()
		checkbox_for_id_tree_label_first(props)
		widget_test_finish_layout()

		label, label_ok := widget_test_layout_node("checkbox-for-label")
		target, target_ok := widget_test_layout_node("checkbox-for-target")
		testing.expect(t, label_ok && target_ok)

		if !label_ok || !target_ok {
			return
		}

		label.rect = {0, 0, 120, 20}
		target.rect = {0, 40, 16, 16}

		o.w_ctx.mouse_x = 10
		o.w_ctx.mouse_y = 10
		widget_test_begin_draw()
		o.w_ctx.left_mouse = {
			down    = true,
			pressed = true,
		}
		checkbox_for_id_tree_label_first(props)
		testing.expect_value(t, o.w_ctx.focused_id, "checkbox-for-target")
		testing.expect_value(t, checkbox_test_change_count, 0)
		widget_test_end_frame()

		widget_test_begin_layout()
		checkbox_for_id_tree_label_first(props)
		widget_test_finish_layout()
		label, label_ok = widget_test_layout_node("checkbox-for-label")
		target, target_ok = widget_test_layout_node("checkbox-for-target")
		testing.expect(t, label_ok && target_ok)

		if label_ok {
			label.rect = {0, 0, 120, 20}
		}

		if target_ok {
			target.rect = {0, 40, 16, 16}
		}

		o.w_ctx.mouse_x = 10
		o.w_ctx.mouse_y = 10
		widget_test_begin_draw()
		o.w_ctx.left_mouse = {
			released = true,
		}
		checkbox_for_id_tree_label_first(props)

		testing.expect_value(t, checkbox_test_change_count, 1)
		testing.expect(t, checkbox_test_changed == .TRUE)
		testing.expect_value(t, checkbox_test_click_count, 1)
		testing.expect_value(t, o.w_ctx.focused_id, "checkbox-for-target")
	})
}

@(test)
checkbox_label_for_id_click_activates_when_control_first :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			checkbox_test_reset_events()
			props := Checkbox_Props {
				config = {id = "checkbox-for-target"},
				checked = .FALSE,
				on_checked_change = checkbox_test_on_change,
				on_click = checkbox_test_on_click,
			}

			widget_test_begin_layout()
			checkbox_for_id_tree_control_first(props)
			widget_test_finish_layout()

			label, label_ok := widget_test_layout_node("checkbox-for-label")
			target, target_ok := widget_test_layout_node("checkbox-for-target")
			testing.expect(t, label_ok && target_ok)

			if !label_ok || !target_ok {
				return
			}

			label.rect = {20, 0, 120, 20}
			target.rect = {0, 0, 16, 16}

			o.w_ctx.mouse_x = 40
			o.w_ctx.mouse_y = 10
			widget_test_begin_draw()
			o.w_ctx.left_mouse = {
				down    = true,
				pressed = true,
			}
			checkbox_for_id_tree_control_first(props)
			testing.expect_value(t, o.w_ctx.focused_id, "checkbox-for-target")
			testing.expect_value(t, checkbox_test_change_count, 0)
			widget_test_end_frame()

			widget_test_begin_layout()
			checkbox_for_id_tree_control_first(props)
			widget_test_finish_layout()
			label, label_ok = widget_test_layout_node("checkbox-for-label")
			target, target_ok = widget_test_layout_node("checkbox-for-target")
			testing.expect(t, label_ok && target_ok)

			if label_ok {
				label.rect = {20, 0, 120, 20}
			}

			if target_ok {
				target.rect = {0, 0, 16, 16}
			}

			o.w_ctx.mouse_x = 40
			o.w_ctx.mouse_y = 10
			widget_test_begin_draw()
			o.w_ctx.left_mouse = {
				released = true,
			}
			checkbox_for_id_tree_control_first(props)
			// Control ran before the label queued activation this frame.
			testing.expect_value(t, checkbox_test_change_count, 0)
			testing.expect_value(t, o.w_ctx.label_activate_id, "checkbox-for-target")
			widget_test_end_frame()

			widget_test_begin_layout()
			checkbox_for_id_tree_control_first(props)
			widget_test_finish_layout()
			widget_test_begin_draw()
			checkbox_for_id_tree_control_first(props)

			testing.expect_value(t, checkbox_test_change_count, 1)
			testing.expect(t, checkbox_test_changed == .TRUE)
			testing.expect_value(t, checkbox_test_click_count, 1)
			testing.expect_value(t, o.w_ctx.label_activate_id, "")
		},
	)
}

@(test)
checkbox_label_for_id_ignores_disabled_target :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		checkbox_test_reset_events()
		props := Checkbox_Props {
			config = {id = "checkbox-for-target"},
			checked = .FALSE,
			disabled = true,
			on_checked_change = checkbox_test_on_change,
			on_click = checkbox_test_on_click,
		}

		widget_test_begin_layout()
		checkbox_for_id_tree_label_first(props)
		widget_test_finish_layout()

		label, label_ok := widget_test_layout_node("checkbox-for-label")
		testing.expect(t, label_ok)

		if !label_ok {
			return
		}

		label.rect = {0, 0, 120, 20}
		o.w_ctx.mouse_x = 10
		o.w_ctx.mouse_y = 10
		widget_test_begin_draw()
		o.w_ctx.left_mouse = {
			down    = true,
			pressed = true,
		}
		checkbox_for_id_tree_label_first(props)
		widget_test_end_frame()

		widget_test_begin_layout()
		checkbox_for_id_tree_label_first(props)
		widget_test_finish_layout()
		label, label_ok = widget_test_layout_node("checkbox-for-label")

		if label_ok {
			label.rect = {0, 0, 120, 20}
		}

		o.w_ctx.mouse_x = 10
		o.w_ctx.mouse_y = 10
		widget_test_begin_draw()
		o.w_ctx.left_mouse = {
			released = true,
		}
		checkbox_for_id_tree_label_first(props)

		testing.expect_value(t, checkbox_test_change_count, 0)
		testing.expect_value(t, checkbox_test_click_count, 0)
	})
}
