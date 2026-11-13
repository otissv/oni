#+test
package oni_widgets

import o ".."
import set "../set"
import "core:testing"

@(private)
file_drop_test_callbacks, file_drop_test_children: int
@(private)
file_drop_test_status: o.File_Drop_Status
@(private)
file_drop_test_error: o.File_Drop_Error

@(private)
file_drop_widget_test_props :: proc() -> File_Drop_Target_Props {
	return {
		config = {id = "drop-target", width = set.Width(200), height = set.Height(100)},
		child = proc(_: File_Drop_Target_State) { file_drop_test_children += 1 },
		on_drop = proc(event: File_Drop_Event) {
			file_drop_test_callbacks += 1
			file_drop_test_status = event.status
			file_drop_test_error = event.error_code
		},
	}
}

@(private)
file_drop_widget_test_enqueue :: proc() {
	_ = o.file_drop_process_event({commonEvent = {type = .DROP_FILE}, windowID = 1, data = "/tmp/image.png", x = 30, y = 20}, 1, {800, 600})
	_ = o.file_drop_process_event({commonEvent = {type = .DROP_COMPLETE}, windowID = 1, x = 30, y = 20}, 1, {800, 600})
}

@(test)
file_drop_target_is_composable_and_delivers_only_on_draw_once :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		file_drop_test_callbacks, file_drop_test_children = 0, 0
		file_drop_widget_test_enqueue()
		widget_test_begin_layout()
		props := file_drop_widget_test_props()
		File_Drop_Target(props)
		testing.expect_value(t, file_drop_test_callbacks, 0)
		widget_test_finish_layout()
		widget_test_begin_draw()
		File_Drop_Target(props)
		testing.expect_value(t, file_drop_test_children, 2)
		testing.expect_value(t, file_drop_test_callbacks, 1)
		testing.expect_value(t, file_drop_test_status, .Selected)
		File_Drop_Target(props)
		testing.expect_value(t, file_drop_test_callbacks, 1)
		widget_test_end_frame()
	})
}

@(test)
file_drop_target_reports_policy_rejection_and_releases_paths :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		file_drop_test_callbacks = 0
		file_drop_widget_test_enqueue()
		widget_test_begin_layout()
		props := file_drop_widget_test_props()
		props.accept = proc(_: []string) -> bool { return false }
		File_Drop_Target(props)
		widget_test_finish_layout()
		widget_test_begin_draw()
		File_Drop_Target(props)
		testing.expect_value(t, file_drop_test_callbacks, 1)
		testing.expect_value(t, file_drop_test_status, .Failed)
		testing.expect_value(t, file_drop_test_error, .Rejected)
		_, leftover := o.Take_File_Drop()
		testing.expect(t, !leftover)
		widget_test_end_frame()
	})
}

@(test)
file_drop_target_disabled_or_without_callback_leaves_files_for_window_consumer :: proc(t: ^testing.T) {
	with_widget_env(t, proc(t: ^testing.T) {
		for disabled in ([2]bool{true, false}) {
			file_drop_test_callbacks = 0
			file_drop_widget_test_enqueue()
			widget_test_begin_layout()
			props := file_drop_widget_test_props()
			props.config.disabled = set.Disabled(disabled)
			if !disabled { props.on_drop = nil }
			File_Drop_Target(props)
			widget_test_finish_layout()
			widget_test_begin_draw()
			File_Drop_Target(props)
			testing.expect_value(t, file_drop_test_callbacks, 0)
			result, leftover := o.Take_File_Drop()
			testing.expect(t, leftover)
			o.Destroy_File_Drop_Result(&result)
			widget_test_end_frame()
		}
	})
}
