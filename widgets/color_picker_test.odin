package oni_widgets

import o ".."
import set "../set"
import "core:strings"
import "core:testing"
import sdl "vendor:sdl3"

@(private)
color_picker_test_change_count: int

@(private)
color_picker_test_commit_count: int

@(private)
color_picker_test_last_value: o.RGBA

@(private)
color_picker_test_channel: o.Color_Picker_Channel

@(private)
color_picker_test_channel_count: int

@(private)
color_picker_test_value: o.RGBA = {255, 0, 0, 255}

@(private)
color_picker_test_previous: o.RGBA = {255, 0, 0, 255}

@(private)
color_picker_test_on_change :: proc(value: o.RGBA) {
	color_picker_test_change_count += 1
	color_picker_test_last_value = value
	color_picker_test_value = value
}

@(private)
color_picker_test_on_commit :: proc(value: o.RGBA) {
	color_picker_test_commit_count += 1
	color_picker_test_last_value = value
}

@(private)
color_picker_test_on_channel :: proc(channel: o.Color_Picker_Channel) {
	color_picker_test_channel_count += 1
	color_picker_test_channel = channel
}

@(private)
color_picker_test_reset :: proc() {
	color_picker_test_change_count = 0
	color_picker_test_commit_count = 0
	color_picker_test_last_value = {}
	color_picker_test_channel = .H
	color_picker_test_channel_count = 0
}

@(private)
color_picker_test_parts_child :: proc(_: Color_Picker_State) {
	Color_Picker_Field({config = {id = "color-picker-layout-field"}})
	Color_Picker_Slider({config = {id = "color-picker-layout-slider"}})
	Color_Picker_Alpha({config = {id = "color-picker-layout-alpha"}})
	Color_Picker_Type({config = {id = "color-picker-layout-rgb"}, color_type = .RGB})
	Color_Picker_Type({config = {id = "color-picker-layout-hsb"}, color_type = .HSB})
}

@(private)
color_picker_test_interactive_child :: proc(_: Color_Picker_State) {
	Color_Picker_Field({config = {id = "color-picker-keys-field"}})
}

@(private)
color_picker_test_channel_child :: proc(_: Color_Picker_State) {
	Color_Picker_Field({config = {id = "color-picker-channel-field"}})
	Color_Picker_Channels({config = {id = "color-picker-channel-list"}})
}

@(test)
color_picker_theme_base_sets_kind_and_tabbable :: proc(t: ^testing.T) {
	frame := Color_Picker_State{}
	base := color_picker_theme_base(&frame)

	testing.expect(t, base.kind == .COLOR_PICKER)
	testing.expect(t, o.cfg_style_bool(base.tabbable))
}

@(test)
color_picker_default_layout_field_and_slider :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		Color_Picker({
			config = {
				id = "color-picker-default-layout",
				width = set.Width(f32(480)),
				height = set.Height(f32(560)),
			},
			value = color_picker_test_value,
			channel = .H,
			previous = color_picker_test_previous,
			child = proc(_: Color_Picker_State) {
				Color_Picker_Default("color-picker-default-layout")
			},
		})
		widget_test_finish_layout()

		field := o.COLOR_PICKER_DEFAULT_FIELD_SIZE
		slider_w := o.COLOR_PICKER_DEFAULT_SLIDER_WIDTH
		testing.expect(t, widget_test_has_layout_size(field, field, 2))
		testing.expect(t, widget_test_has_layout_size(slider_w, field, 2))
	})
}

@(test)
color_picker_layout_registers_kind_and_tab_order :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		Color_Picker(
			{
				config = {id = "color-picker-layout"},
				value = color_picker_test_value,
				channel = .H,
				previous = color_picker_test_previous,
				child = color_picker_test_parts_child,
			},
		)
		widget_test_finish_layout()

		expect_registered_id(t, "color-picker-layout")
		expect_registered_id(t, "color-picker-layout-field")
		expect_layout_kind(t, "color-picker-layout", .COLOR_PICKER)
		expect_in_tab_order(t, "color-picker-layout", true)
	})
}

@(test)
color_picker_disabled_not_tabbable :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		Color_Picker(
			{
				config = {id = "color-picker-disabled"},
				value = {0, 255, 0, 255},
				channel = .H,
				previous = {0, 255, 0, 255},
				disabled = true,
				child = color_picker_test_parts_child,
			},
		)
		widget_test_finish_layout()

		expect_registered_id(t, "color-picker-disabled")
		expect_in_tab_order(t, "color-picker-disabled", false)
	})
}

@(test)
color_picker_keyboard_nudges_value :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		color_picker_test_reset()

		props := Color_Picker_Props {
			config = {id = "color-picker-keys"},
			value = color_picker_test_value,
			channel = .H,
			previous = color_picker_test_previous,
			on_value_change = color_picker_test_on_change,
			child = color_picker_test_interactive_child,
		}

		widget_test_begin_layout()
		defer widget_test_end_frame()
		Color_Picker(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("color-picker-keys")
		o.w_ctx.keys[int(sdl.Scancode.RIGHT)] = {
			down    = true,
			pressed = true,
		}
		Color_Picker(props)

		testing.expect(t, color_picker_test_change_count > 0)
	})
}

@(test)
color_picker_part_drag_field_updates_and_commits :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		color_picker_test_reset()

		pushed := color_picker_ctx_push(
			{
				active = true,
				key = "color-picker-part-drag",
				value = {255, 0, 0, 255},
				channel = .H,
				hsva = o.rgba_to_hsva({255, 0, 0, 255}),
				on_value_change = color_picker_test_on_change,
				on_value_commit = color_picker_test_on_commit,
			},
		)
		defer {
			if pushed {
				color_picker_ctx_pop()
			}
		}

		layout_id := o.ui_id("color-picker-part-drag-field")
		field_rect := o.Rect {
			x = 16,
			y = 24,
			w = 200,
			h = 200,
		}

		o.w_ctx.mouse_x = field_rect.x + field_rect.w * 0.35
		o.w_ctx.mouse_y = field_rect.y + field_rect.h * 0.65
		o.w_ctx.left_mouse = {
			down    = true,
			pressed = true,
		}
		color_picker_part_drag(layout_id, .FIELD, field_rect, true, true, false)

		drag := o.color_picker_drag_entry(layout_id)
		testing.expect(t, drag != nil && drag.active)
		testing.expect(t, drag.region == .FIELD)
		testing.expect(t, color_picker_test_change_count > 0)

		o.w_ctx.left_mouse = {
			released = true,
			down     = false,
		}
		color_picker_part_drag(layout_id, .FIELD, field_rect, true, true, false)
		testing.expect(t, color_picker_test_commit_count > 0)
	})
}

@(test)
color_picker_emit_invokes_commit_callback :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		color_picker_test_reset()

		pushed := color_picker_ctx_push(
			{
				active = true,
				key = "color-picker-emit-ctx",
				value = {255, 0, 0, 255},
				on_value_commit = color_picker_test_on_commit,
			},
		)
		defer {
			if pushed {
				color_picker_ctx_pop()
			}
		}

		color_picker_emit(color_picker_ctx_top(), {10, 20, 30, 255}, true)

		testing.expect(t, color_picker_test_commit_count == 1)
	})
}

@(test)
color_picker_set_channel_invokes_callback :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		color_picker_test_reset()

		pushed := color_picker_ctx_push(
			{
				active = true,
				key = "color-picker-channel-ctx",
				channel = .H,
				on_channel_change = color_picker_test_on_channel,
			},
		)
		defer {
			if pushed {
				color_picker_ctx_pop()
			}
		}

		color_picker_set_channel(color_picker_ctx_top(), .V)

		testing.expect(t, color_picker_test_channel_count == 1)
		testing.expect(t, color_picker_test_channel == .V)
	})
}

@(test)
color_picker_shutdown_clears_runtimes :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		Color_Picker(
			{
				config = {id = "color-picker-shutdown"},
				value = {10, 20, 30, 255},
				channel = .H,
				previous = {10, 20, 30, 255},
				child = color_picker_test_parts_child,
			},
		)
		widget_test_finish_layout()

		testing.expect(t, color_picker_runtimes != nil)
		testing.expect(t, len(color_picker_runtimes) > 0)

		color_picker_shutdown()
		testing.expect(t, color_picker_runtimes == nil)
	})
}

@(test)
color_picker_unmount_clears_runtime :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Color_Picker({
			config = {id = "color-picker-unmount"},
			value = {10, 20, 30, 255},
			channel = .H,
			previous = {10, 20, 30, 255},
			unmount = true,
			child = color_picker_test_parts_child,
			on_unmount = proc(_: Color_Picker_State) -> o.Mount {
				return .COMPLETED
			},
		})
		widget_test_finish_layout()

		_, ok := color_picker_runtimes["color-picker-unmount"]
		testing.expect(t, !ok)
	})
}

@(test)
color_picker_text_input_on_change_adopts_owned_strings :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		rt := color_picker_runtime_ensure("color-picker-adopt")
		testing.expect(t, rt != nil)

		pushed := color_picker_ctx_push(
			{
				active = true,
				key = "color-picker-adopt",
				runtime = rt,
				value = {255, 0, 0, 255},
				hsva = o.rgba_to_hsva({255, 0, 0, 255}),
				channel = .H,
			},
		)
		defer {
			if pushed {
				color_picker_ctx_pop()
			}
		}

		color_picker_hex_on_change({}, strings.clone("00ff00"))
		testing.expect(t, rt.hex == "00ff00")

		color_picker_type_on_change(.RGB, 0, strings.clone("12"))
		testing.expect(t, rt.type_drafts[int(o.Color_Picker_Color_Type.RGB)].text[0] == "12")

		// Inactive / invalid paths must free the Text_Input-owned clone.
		color_picker_ctx_pop()
		pushed = false
		color_picker_hex_on_change({}, strings.clone("leak-hex-inactive"))
		color_picker_type_on_change(.RGB, 0, strings.clone("leak-type-inactive"))
		color_picker_type_input_on_change(
			{frame_state = {config = {id = "not-a-type-input"}}},
			strings.clone("leak-type-id"),
		)
	})
}

@(test)
color_picker_style_defaults_from_unset :: proc(t: ^testing.T) {
	style: Color_Picker_Style
	testing.expect_value(
		t,
		color_picker_style_f32(style.field_size, o.COLOR_PICKER_DEFAULT_FIELD_SIZE),
		o.COLOR_PICKER_DEFAULT_FIELD_SIZE,
	)
}
