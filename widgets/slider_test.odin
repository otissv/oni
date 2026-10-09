package oni_widgets

import o ".."
import set "../set"
import sdl "vendor:sdl3"
import "core:fmt"
import "core:testing"

@(private)
slider_test_values: [o.SLIDER_MAX_THUMBS]f32

@(private)
slider_test_count: int

@(private)
slider_test_change_count: int

@(private)
slider_test_commit_count: int

@(private)
slider_test_last_change: [o.SLIDER_MAX_THUMBS]f32

@(private)
slider_test_last_change_count: int

@(private)
slider_test_on_change :: proc(values: []f32) {
	slider_test_change_count += 1
	slider_test_last_change_count = len(values)

	for i in 0 ..< len(values) {
		if i < o.SLIDER_MAX_THUMBS {
			slider_test_last_change[i] = values[i]
			slider_test_values[i] = values[i]
		}
	}

	slider_test_count = len(values)
}

@(private)
slider_test_on_commit :: proc(values: []f32) {
	slider_test_commit_count += 1
	_ = values
}

@(private)
slider_test_thumb_calls: int

@(private)
slider_test_thumb_indexes: [o.SLIDER_MAX_THUMBS]int

@(private)
slider_test_thumb_values: [o.SLIDER_MAX_THUMBS]f32

@(private)
slider_test_custom_thumb :: proc(frame_state: Slider_Thumb_State) {
	if slider_test_thumb_calls < o.SLIDER_MAX_THUMBS {
		slider_test_thumb_indexes[slider_test_thumb_calls] = frame_state.index
		slider_test_thumb_values[slider_test_thumb_calls] = frame_state.value
	}

	slider_test_thumb_calls += 1
	Rectangle({
		config = {
			id = fmt.tprintf("slider-test-thumb-visual-%d", frame_state.index),
			width = set.Width(f32(10)),
			height = set.Height(f32(10)),
			background = set.Background(o.Color.PRIMARY),
		},
	})
}

@(private)
slider_test_reset :: proc() {
	slider_test_values = {}
	slider_test_count = 0
	slider_test_change_count = 0
	slider_test_commit_count = 0
	slider_test_last_change = {}
	slider_test_last_change_count = 0
	slider_test_thumb_calls = 0
	slider_test_thumb_indexes = {}
	slider_test_thumb_values = {}
}

@(test)
slider_theme_base_sets_kind_and_tabbable :: proc(t: ^testing.T) {
	frame := Slider_State {
		orientation = .HORIZONTAL,
	}
	base := slider_theme_base(&frame)

	testing.expect(t, base.kind == .SLIDER)
	testing.expect(t, o.cfg_style_bool(base.tabbable))
}

@(test)
slider_layout_registers_kind_and_tab_order :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		values := [1]f32{40}
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Slider({
			config = {id = "slider-layout"},
			values = values[:],
		})
		widget_test_finish_layout()

		expect_registered_id(t, "slider-layout")
		expect_layout_kind(t, "slider-layout", .SLIDER)
		expect_in_tab_order(t, "slider-layout", true)
	})
}

@(test)
slider_disabled_is_not_tabbable :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		values := [1]f32{40}
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Slider({
			config = {id = "slider-disabled"},
			values = values[:],
			disabled = true,
		})
		expect_in_tab_order(t, "slider-disabled", false)
		widget_test_finish_layout()
	})
}

@(test)
slider_empty_values_are_not_tabbable :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Slider({config = {id = "slider-empty"}, values = {}})
		expect_in_tab_order(t, "slider-empty", false)
		widget_test_finish_layout()
	})
}

@(test)
slider_keyboard_arrow_reports_stepped_value :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		slider_test_reset()
		values := [1]f32{40}
		slider_test_values[0] = 40

		props := Slider_Props {
			config = {id = "slider-keyboard"},
			values = values[:],
			min = 0,
			max = 100,
			step = 5,
			on_value_change = slider_test_on_change,
		}

		widget_test_begin_layout()
		defer widget_test_end_frame()
		Slider(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("slider-keyboard")
		o.w_ctx.keys[int(sdl.Scancode.RIGHT)] = {down = true, pressed = true}
		Slider(props)

		testing.expect_value(t, slider_test_change_count, 1)
		expect_close(t, slider_test_last_change[0], 45)
		testing.expect(t, o.shortcut_key_consumed(.RIGHT))
		testing.expect(t, abs(values[0] - 40) < 1e-4)
	})
}

@(test)
slider_keyboard_home_end :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		slider_test_reset()
		values := [1]f32{40}

		props := Slider_Props {
			config = {id = "slider-home"},
			values = values[:],
			min = 10,
			max = 90,
			step = 1,
			on_value_change = slider_test_on_change,
		}

		widget_test_begin_layout()
		defer widget_test_end_frame()
		Slider(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("slider-home")
		o.w_ctx.keys[int(sdl.Scancode.HOME)] = {down = true, pressed = true}
		Slider(props)
		expect_close(t, slider_test_last_change[0], 10)

		widget_test_end_frame()
		values[0] = slider_test_last_change[0]
		props.values = values[:]
		slider_test_reset()

		widget_test_begin_layout()
		Slider(props)
		widget_test_finish_layout()
		widget_test_begin_draw()
		o.widget_set_focused_id("slider-home")
		o.w_ctx.keys[int(sdl.Scancode.END)] = {down = true, pressed = true}
		Slider(props)
		expect_close(t, slider_test_last_change[0], 90)
	})
}

@(test)
slider_disabled_blocks_keyboard :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		slider_test_reset()
		values := [1]f32{40}
		props := Slider_Props {
			config = {id = "slider-key-disabled"},
			values = values[:],
			disabled = true,
			on_value_change = slider_test_on_change,
		}

		widget_test_begin_layout()
		defer widget_test_end_frame()
		Slider(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("slider-key-disabled")
		o.w_ctx.keys[int(sdl.Scancode.RIGHT)] = {down = true, pressed = true}
		Slider(props)

		testing.expect_value(t, slider_test_change_count, 0)
	})
}

@(test)
slider_track_press_jumps_and_commits_on_release :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		slider_test_reset()
		values := [1]f32{0}
		props := Slider_Props {
			config = {
				id = "slider-track",
				width = set.Width(f32(200)),
				height = set.Height(f32(20)),
			},
			values = values[:],
			min = 0,
			max = 100,
			step = 1,
			on_value_change = slider_test_on_change,
			on_value_commit = slider_test_on_commit,
		}

		widget_test_begin_layout()
		Slider(props)
		widget_test_finish_layout()

		rect := o.ui_layout_rect(o.ui_id("slider-track"))
		testing.expect(t, rect.w > 0)

		widget_test_begin_draw()
		o.w_ctx.mouse_x = rect.x + rect.w * 0.75
		o.w_ctx.mouse_y = rect.y + rect.h * 0.5
		o.w_ctx.left_mouse.pressed = true
		o.w_ctx.left_mouse.down = true
		o.layout_resolve_pointer_hit()
		Slider(props)
		widget_test_end_frame()

		testing.expect(t, slider_test_change_count >= 1)
		testing.expect(t, slider_test_last_change[0] > 50)

		values[0] = slider_test_last_change[0]
		props.values = values[:]
		change_before_release := slider_test_change_count

		widget_test_begin_layout()
		Slider(props)
		widget_test_finish_layout()
		widget_test_begin_draw()
		o.w_ctx.mouse_x = rect.x + rect.w * 0.75
		o.w_ctx.mouse_y = rect.y + rect.h * 0.5
		o.w_ctx.left_mouse.released = true
		o.w_ctx.left_mouse.down = false
		o.layout_resolve_pointer_hit()
		Slider(props)
		widget_test_end_frame()

		testing.expect_value(t, slider_test_commit_count, 1)
		testing.expect(t, slider_test_change_count >= change_before_release)
	})
}

@(test)
slider_drag_updates_while_held :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		slider_test_reset()
		values := [1]f32{0}
		props := Slider_Props {
			config = {
				id = "slider-drag",
				width = set.Width(f32(200)),
				height = set.Height(f32(20)),
			},
			values = values[:],
			min = 0,
			max = 100,
			step = 1,
			on_value_change = slider_test_on_change,
		}

		widget_test_begin_layout()
		Slider(props)
		widget_test_finish_layout()
		rect := o.ui_layout_rect(o.ui_id("slider-drag"))

		widget_test_begin_draw()
		o.w_ctx.mouse_x = rect.x + 8
		o.w_ctx.mouse_y = rect.y + rect.h * 0.5
		o.state.input.mouse_left = true
		o.w_ctx.left_mouse = {down = true, pressed = true}
		o.layout_resolve_pointer_hit()
		Slider(props)

		layout_id := o.ui_id("slider-drag")
		drag := o.slider_drag_entry(layout_id)
		testing.expect(t, drag != nil && drag.active)
		widget_test_end_frame()

		values[0] = slider_test_last_change[0]
		props.values = values[:]
		first := slider_test_last_change[0]

		o.state.input.mouse_left = true
		widget_test_begin_layout()
		Slider(props)
		widget_test_finish_layout()
		layout_id = o.ui_id("slider-drag")
		widget_test_begin_draw()
		o.w_ctx.mouse_x = rect.x + rect.w - 8
		o.w_ctx.mouse_y = rect.y + rect.h * 0.5
		o.w_ctx.left_mouse = {down = true}
		o.layout_resolve_pointer_hit()
		Slider(props)

		testing.expect(t, slider_test_last_change[0] > first)
		drag = o.slider_drag_entry(layout_id)
		testing.expect(t, drag != nil && drag.active)
		widget_test_end_frame()
	})
}

@(test)
slider_range_keyboard_moves_active_thumb :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		slider_test_reset()
		values := [2]f32{20, 80}
		props := Slider_Props {
			config = {id = "slider-range"},
			values = values[:],
			min = 0,
			max = 100,
			step = 5,
			min_steps_between_thumbs = 1,
			on_value_change = slider_test_on_change,
		}

		widget_test_begin_layout()
		defer widget_test_end_frame()
		Slider(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		drag := o.slider_drag_entry(o.ui_id("slider-range"))
		testing.expect(t, drag != nil)
		drag.thumb_index = 1

		o.widget_set_focused_id("slider-range")
		o.w_ctx.keys[int(sdl.Scancode.LEFT)] = {down = true, pressed = true}
		Slider(props)

		testing.expect_value(t, slider_test_change_count, 1)
		expect_close(t, slider_test_last_change[0], 20)
		expect_close(t, slider_test_last_change[1], 75)
	})
}

@(test)
slider_vertical_keyboard_uses_up_down :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		slider_test_reset()
		values := [1]f32{40}
		props := Slider_Props {
			config = {id = "slider-vertical"},
			values = values[:],
			min = 0,
			max = 100,
			step = 10,
			orientation = .VERTICAL,
			on_value_change = slider_test_on_change,
		}

		widget_test_begin_layout()
		defer widget_test_end_frame()
		Slider(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("slider-vertical")
		o.w_ctx.keys[int(sdl.Scancode.UP)] = {down = true, pressed = true}
		Slider(props)

		expect_close(t, slider_test_last_change[0], 50)
	})
}

@(test)
slider_inverted_reverses_arrow_direction :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		slider_test_reset()
		values := [1]f32{40}
		props := Slider_Props {
			config = {id = "slider-inverted"},
			values = values[:],
			min = 0,
			max = 100,
			step = 10,
			inverted = true,
			on_value_change = slider_test_on_change,
		}

		widget_test_begin_layout()
		defer widget_test_end_frame()
		Slider(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("slider-inverted")
		o.w_ctx.keys[int(sdl.Scancode.RIGHT)] = {down = true, pressed = true}
		Slider(props)

		expect_close(t, slider_test_last_change[0], 30)
	})
}

@(test)
slider_shift_arrow_uses_large_step :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		slider_test_reset()
		values := [1]f32{40}
		props := Slider_Props {
			config = {id = "slider-shift"},
			values = values[:],
			min = 0,
			max = 100,
			step = 1,
			on_value_change = slider_test_on_change,
		}

		widget_test_begin_layout()
		defer widget_test_end_frame()
		Slider(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.state.input.modifiers = {shift = true}
		o.widget_set_focused_id("slider-shift")
		o.w_ctx.keys[int(sdl.Scancode.RIGHT)] = {down = true, pressed = true}
		Slider(props)

		expect_close(t, slider_test_last_change[0], 50)
	})
}

@(test)
slider_caller_owned_values_are_not_mutated :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		slider_test_reset()
		values := [1]f32{25}
		props := Slider_Props {
			config = {id = "slider-owned"},
			values = values[:],
			min = 0,
			max = 100,
			step = 5,
			on_value_change = slider_test_on_change,
		}

		widget_test_begin_layout()
		defer widget_test_end_frame()
		Slider(props)
		widget_test_finish_layout()
		widget_test_begin_draw()

		o.widget_set_focused_id("slider-owned")
		o.w_ctx.keys[int(sdl.Scancode.RIGHT)] = {down = true, pressed = true}
		Slider(props)

		expect_close(t, values[0], 25)
		expect_close(t, slider_test_last_change[0], 30)
	})
}

@(test)
slider_ui_shutdown_releases_drag_map :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		values := [1]f32{50}
		widget_test_begin_layout()
		Slider({
			config = {
				id = "slider-shutdown",
				width = set.Width(f32(200)),
				height = set.Height(f32(20)),
			},
			values = values[:],
		})
		widget_test_finish_layout()
		rect := o.ui_layout_rect(o.ui_id("slider-shutdown"))

		widget_test_begin_draw()
		o.w_ctx.mouse_x = rect.x + rect.w * 0.5
		o.w_ctx.mouse_y = rect.y + rect.h * 0.5
		o.w_ctx.left_mouse.pressed = true
		o.w_ctx.left_mouse.down = true
		o.layout_resolve_pointer_hit()
		Slider({
			config = {
				id = "slider-shutdown",
				width = set.Width(f32(200)),
				height = set.Height(f32(20)),
			},
			values = values[:],
			on_value_change = slider_test_on_change,
		})
		testing.expect(t, o.state.ui.slider_drags != nil)
		widget_test_end_frame()
	})
}

@(test)
slider_custom_thumb_runs_once_per_thumb :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		slider_test_reset()
		values := [2]f32{20, 80}
		props := Slider_Props {
			config = {
				id = "slider-custom-thumb",
				width = set.Width(f32(200)),
				height = set.Height(f32(20)),
			},
			values = values[:],
			min = 0,
			max = 100,
			step = 1,
			thumb = slider_test_custom_thumb,
		}

		widget_test_begin_layout()
		Slider(props)
		testing.expect_value(t, slider_test_thumb_calls, 2)
		widget_test_finish_layout()

		slider_test_thumb_calls = 0
		widget_test_begin_draw()
		Slider(props)
		testing.expect_value(t, slider_test_thumb_calls, 2)
		testing.expect_value(t, slider_test_thumb_indexes[0], 0)
		testing.expect_value(t, slider_test_thumb_indexes[1], 1)
		expect_close(t, slider_test_thumb_values[0], 20)
		expect_close(t, slider_test_thumb_values[1], 80)

		expect_registered_id(t, "slider-custom-thumb/thumb-0")
		expect_registered_id(t, "slider-custom-thumb/thumb-1")
		widget_test_end_frame()
	})
}

@(test)
slider_without_custom_thumb_skips_thumb_hosts :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		values := [1]f32{40}
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Slider({
			config = {
				id = "slider-default-thumb",
				width = set.Width(f32(200)),
				height = set.Height(f32(20)),
			},
			values = values[:],
		})
		widget_test_finish_layout()

		_, ok := GetElementById("slider-default-thumb/thumb-0")
		testing.expect(t, !ok)
	})
}
