package oni

import "base:runtime"
import "core:strings"
import "core:sync"
import "core:testing"

@(private)
with_error_test_state :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	test_state: State
	saved_state := state
	defer state = saved_state
	state = &test_state

	defer error_shutdown()

	body(t)
}

@(test)
error_push_deduplicates_same_message :: proc(t: ^testing.T) {
	with_error_test_state(t, proc(t: ^testing.T) {
		loc := runtime.Source_Code_Location {
			file_path = "error_test.odin",
			line      = 1,
			procedure = "test_proc",
		}
		error_push(.ERROR, "same message", loc)
		error_push(.ERROR, "same message", loc)

		testing.expect_value(t, len(state.errors.entries), 1)
		testing.expect_value(t, error_active_count(), 1)
	})
}

@(test)
error_dismiss_removes_entry :: proc(t: ^testing.T) {
	with_error_test_state(t, proc(t: ^testing.T) {
		loc := runtime.Source_Code_Location {
			file_path = "error_test.odin",
			line      = 2,
			procedure = "test_proc",
		}
		error_push(.ERROR, "dismiss me", loc)
		key := state.errors.entries[0].key
		error_dismiss(key)

		testing.expect_value(t, error_active_count(), 0)
		testing.expect_value(t, len(state.errors.entries), 0)
	})
}

@(test)
error_format_log_line_matches_stderr_shape :: proc(t: ^testing.T) {
	with_error_test_state(t, proc(t: ^testing.T) {
		loc := runtime.Source_Code_Location {
			file_path = "error_test.odin",
			line      = 9,
			procedure = "test_proc",
		}
		error_push(.ERROR, "boom", loc)
		line := error_format_log_line(state.errors.entries[0])

		testing.expect(t, strings.contains(line, "[ERROR]"))
		testing.expect(t, strings.contains(line, "error_test.odin:9:test_proc"))
		testing.expect(t, strings.contains(line, "boom"))
	})
}

@(test)
error_report_queues_banner_entry :: proc(t: ^testing.T) {
	with_error_test_state(t, proc(t: ^testing.T) {
		error_report("queued")

		testing.expect_value(t, error_active_count(), 1)
		testing.expect_value(t, state.errors.entries[0].message, "queued")
	})
}

@(test)
log_error_does_not_queue_banner_entry :: proc(t: ^testing.T) {
	with_error_test_state(t, proc(t: ^testing.T) {
		log_error("stderr only")

		testing.expect_value(t, error_active_count(), 0)
	})
}

@(test)
error_dismiss_all_clears_entries :: proc(t: ^testing.T) {
	with_error_test_state(t, proc(t: ^testing.T) {
		loc := runtime.Source_Code_Location {
			file_path = "error_test.odin",
			line      = 3,
			procedure = "test_proc",
		}
		error_push(.ERROR, "one", loc)
		error_push(.WARN, "two", loc)
		error_dismiss_all()

		testing.expect_value(t, error_active_count(), 0)
		testing.expect_value(t, len(state.errors.entries), 0)
	})
}
