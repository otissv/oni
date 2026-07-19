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
	error_init()

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
error_dismiss_hides_entry_from_active_count :: proc(t: ^testing.T) {
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
	})
}

@(test)
error_format_log_line_matches_stderr_shape :: proc(t: ^testing.T) {
	with_error_test_state(t, proc(t: ^testing.T) {
		entry := Error_Entry {
			level     = .ERROR,
			message   = "boom",
			file      = "error_test.odin",
			line      = 9,
			procedure = "test_proc",
		}
		line := error_format_log_line(entry)

		testing.expect(t, strings.contains(line, "[ERROR]"))
		testing.expect(t, strings.contains(line, "error_test.odin:9:test_proc"))
		testing.expect(t, strings.contains(line, "boom"))
	})
}

@(test)
log_error_also_queues_banner_entry :: proc(t: ^testing.T) {
	with_error_test_state(t, proc(t: ^testing.T) {
		log_error("queued")

		testing.expect_value(t, error_active_count(), 1)
		testing.expect_value(t, state.errors.entries[0].message, "queued")
	})
}
