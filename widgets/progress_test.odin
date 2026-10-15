package oni_widgets

import o ".."
import "core:testing"

@(private)
progress_test_value_text := ""

@(private)
progress_test_saw_status: Progress_Status

@(private)
progress_test_saw_indet := false

@(private)
progress_test_saw_ratio: f32

@(private)
progress_test_find_kind_under :: proc(
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

@(test)
progress_theme_base_sets_kinds :: proc(t: ^testing.T) {
	root := Progress_State{}
	testing.expect(t, progress_theme_base(&root).kind == .PROGRESS)

	track := Progress_Track_State{}
	testing.expect(t, progress_track_theme_base(&track, 8).kind == .PROGRESS_TRACK)

	label := Progress_Label_State{}
	testing.expect(t, progress_label_theme_base(&label).kind == .PROGRESS_LABEL)

	value := Progress_Value_State{}
	testing.expect(t, progress_value_theme_base(&value).kind == .PROGRESS_VALUE)

	indicator := progress_indicator_theme_base(&track, 8)
	testing.expect(t, indicator.kind == .PROGRESS_INDICATOR)
}

@(test)
progress_ratio_and_status_helpers :: proc(t: ^testing.T) {
	expect_close(t, Progress_Ratio(0, 0, 100), 0)
	expect_close(t, Progress_Ratio(50, 0, 100), 0.5)
	expect_close(t, Progress_Ratio(100, 0, 100), 1)
	expect_close(t, Progress_Ratio(25, 0, 50), 0.5)
	expect_close(t, Progress_Ratio(-10, 0, 100), 0)
	expect_close(t, Progress_Ratio(200, 0, 100), 1)

	testing.expect(t, Progress_Resolve_Status(50, 0, 100, false) == .PROGRESSING)
	testing.expect(t, Progress_Resolve_Status(100, 0, 100, false) == .COMPLETE)
	testing.expect(t, Progress_Resolve_Status(0, 0, 100, true) == .INDETERMINATE)

	track := o.Rect{x = 10, y = 20, w = 200, h = 8}
	fill := Progress_Indicator_Rect(track, 0.5, false, false)
	expect_close(t, fill.x, 10)
	expect_close(t, fill.w, 100)
	expect_close(t, fill.h, 8)

	inverted := Progress_Indicator_Rect(track, 0.25, false, true)
	expect_close(t, inverted.x, 10 + 150)
	expect_close(t, inverted.w, 50)

	indet := Progress_Indicator_Rect(track, 0, true, false)
	expect_close(t, indet.w, 200 * PROGRESS_INDETERMINATE_RATIO)

	testing.expect_value(t, Progress_Format_Default(56, 0, 100, false), "56%")
	testing.expect_value(t, Progress_Format_Default(0, 0, 100, true), "")
}

@(test)
progress_root_layout_registers_kind :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Progress({
			config = {id = "progress-kind", value = 33},
			child = proc(_: Progress_State) {},
		})
		widget_test_finish_layout()

		expect_registered_id(t, "progress-kind")
		expect_layout_kind(t, "progress-kind", .PROGRESS)
	})
}

@(test)
progress_default_parts_layout_track :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Progress({config = {id = "progress-default", value = 40}})
		widget_test_finish_layout()

		root, root_ok := widget_test_layout_node("progress-default")
		testing.expect(t, root_ok)

		if !root_ok {
			return
		}

		track, track_ok := progress_test_find_kind_under(root, .PROGRESS_TRACK)
		testing.expect(t, track_ok)

		if track_ok {
			testing.expect(t, track.kind == .PROGRESS_TRACK)
			expect_close(t, track.config.height.value, PROGRESS_DEFAULT_TRACK_THICKNESS)
		}
	})
}

@(private)
progress_test_compose_child :: proc(fs: Progress_State) {
	progress_test_saw_status = fs.status
	progress_test_saw_status = Progress_Current_Status()
	Progress_Label({config = {id = "progress-compose-label", text = "Upload progress"}})
	Progress_Value({
		config = {id = "progress-compose-value"},
		child = proc(vfs: Progress_Value_State) {
			progress_test_value_text = vfs.text
		},
	})
	Progress_Track({
		config = {id = "progress-compose-track"},
		child = proc(_: Progress_Track_State) {
			Progress_Indicator({config = {id = "progress-compose-indicator"}})
		},
	})
}

@(test)
progress_composed_label_value_track :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		progress_test_value_text = ""
		progress_test_saw_status = .INDETERMINATE
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Progress({
			config = {id = "progress-compose", value = 56},
			child = progress_test_compose_child,
		})
		widget_test_finish_layout()

		expect_registered_id(t, "progress-compose")
		expect_registered_id(t, "progress-compose-label")
		expect_registered_id(t, "progress-compose-value")
		expect_registered_id(t, "progress-compose-track")

		root, root_ok := widget_test_layout_node("progress-compose")
		testing.expect(t, root_ok)

		if !root_ok {
			return
		}

		_, label_ok := progress_test_find_kind_under(root, .PROGRESS_LABEL)
		testing.expect(t, label_ok)
		_, value_ok := progress_test_find_kind_under(root, .PROGRESS_VALUE)
		testing.expect(t, value_ok)
		_, track_ok := progress_test_find_kind_under(root, .PROGRESS_TRACK)
		testing.expect(t, track_ok)

		testing.expect_value(t, progress_test_value_text, "56%")
		testing.expect(t, progress_test_saw_status == .PROGRESSING)
	})
}

@(private)
progress_test_indet_child :: proc(_: Progress_State) {
	progress_test_saw_indet = Progress_Is_Indeterminate()
	progress_test_saw_status = Progress_Current_Status()
	progress_test_saw_ratio = Progress_Current_Ratio()
	Progress_Track({
		child = proc(_: Progress_Track_State) {
			Progress_Indicator({})
		},
	})
}

@(test)
progress_indeterminate_status_in_ctx :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		progress_test_saw_indet = false
		progress_test_saw_status = .PROGRESSING
		progress_test_saw_ratio = 1
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Progress({
			config = {id = "progress-indet", value = 10, indeterminate = true},
			child = progress_test_indet_child,
		})
		widget_test_finish_layout()

		testing.expect(t, progress_test_saw_indet)
		testing.expect(t, progress_test_saw_status == .INDETERMINATE)
		expect_close(t, progress_test_saw_ratio, 0)
	})
}

@(test)
progress_disabled_mutes_opacity :: proc(t: ^testing.T) {
	root := Progress_State {
		is_disabled = true,
	}
	base := progress_theme_base(&root)
	testing.expect(t, base.opacity.mode == .Value)
	expect_close(t, base.opacity.value.(f32), 0.5)
}

@(test)
progress_shutdown_clears_ctx_stack :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Progress({
			config = {id = "progress-shutdown", value = 1},
			child = proc(_: Progress_State) {},
		})
		widget_test_finish_layout()

		testing.expect(t, progress_ctx_depth >= 0)
		progress_shutdown()
		testing.expect_value(t, progress_ctx_depth, 0)
		testing.expect(t, !progress_ctx_ok())
	})
}

@(private)
progress_test_format_proc :: proc(value, min_v, max_v: f32, indeterminate: bool) -> string {
	_ = value
	_ = min_v
	_ = max_v
	_ = indeterminate

	return "custom"
}

@(private)
progress_test_format_child :: proc(_: Progress_State) {
	Progress_Value({
		format = progress_test_format_proc,
		child = proc(fs: Progress_Value_State) {
			progress_test_value_text = fs.text
		},
	})
}

@(test)
progress_custom_format :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		progress_test_value_text = ""
		widget_test_begin_layout()
		defer widget_test_end_frame()

		Progress({
			config = {id = "progress-format", value = 2, min = 0, max = 4},
			child = progress_test_format_child,
		})
		widget_test_finish_layout()

		testing.expect_value(t, progress_test_value_text, "custom")
	})
}
