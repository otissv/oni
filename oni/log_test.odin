package oni

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"

@(private)
log_test_guard: sync.Mutex

@(private)
log_capture_counter: int

@(private)
log_test_explicit_loc: runtime.Source_Code_Location

@(private)
log_test_stderr_before: ^os.File

@(private)
with_captured_stderr :: proc(t: ^testing.T, body: proc(t: ^testing.T)) -> string {
	sync.mutex_lock(&log_test_guard)
	defer sync.mutex_unlock(&log_test_guard)

	_ = os.make_directory_all("build")
	log_capture_counter += 1
	path := fmt.tprintf("build/test_log_capture_%d.txt", log_capture_counter)
	_ = os.remove(path)

	file, err := os.open(path, {.Write, .Create, .Trunc})
	testing.expectf(t, err == nil, "open capture file: %v", err)
	if err != nil do return ""

	old := os.stderr
	os.stderr = file
	body(t)
	os.flush(file)
	os.stderr = old
	os.close(file)

	data, read_err := os.read_entire_file(path, context.allocator)
	testing.expectf(t, read_err == nil, "read capture file: %v", read_err)
	if read_err != nil do return ""
	defer delete(data)
	return strings.clone(string(data))
}

@(test)
log_write_log_includes_level_location_and_message :: proc(t: ^testing.T) {
	out := with_captured_stderr(
		t,
		proc(t: ^testing.T) {
			loc := runtime.Source_Code_Location {
				file_path = "/tmp/example.odin",
				line      = 42,
				procedure = "demo_proc",
			}
			write_log("DEBUG", "hello world", loc)
		},
	)
	defer delete(out)

	testing.expect(t, strings.contains(out, "[DEBUG]"))
	testing.expect(t, strings.contains(out, "example.odin"))
	testing.expect(t, strings.contains(out, "42"))
	testing.expect(t, strings.contains(out, "demo_proc"))
	testing.expect(t, strings.contains(out, "hello world"))
}

@(test)
log_debug_and_formatted_variants :: proc(t: ^testing.T) {
	out := with_captured_stderr(
		t,
		proc(t: ^testing.T) {
			log("plain debug")
			logf("value=%d", 7)
		},
	)
	defer delete(out)

	testing.expect(t, strings.contains(out, "[DEBUG]"))
	testing.expect(t, strings.contains(out, "plain debug"))
	testing.expect(t, strings.contains(out, "value=7"))
	testing.expect(t, strings.contains(out, "log_test.odin"))
}

@(test)
log_error_and_warn_levels :: proc(t: ^testing.T) {
	out := with_captured_stderr(
		t,
		proc(t: ^testing.T) {
			log_error("boom")
			log_errorf("code=%s", "E1")
			log_warn("careful")
			log_warnf("n=%d", 3)
		},
	)
	defer delete(out)

	testing.expect(t, strings.contains(out, "[ERROR]"))
	testing.expect(t, strings.contains(out, "boom"))
	testing.expect(t, strings.contains(out, "code=E1"))
	testing.expect(t, strings.contains(out, "[WARN]"))
	testing.expect(t, strings.contains(out, "careful"))
	testing.expect(t, strings.contains(out, "n=3"))
}

@(test)
log_messages_include_source_file :: proc(t: ^testing.T) {
	out := with_captured_stderr(
		t,
		proc(t: ^testing.T) {
			log("trace-me")
		},
	)
	defer delete(out)

	testing.expect(t, strings.contains(out, "log_test.odin"))
	testing.expect(t, strings.contains(out, "trace-me"))
}

@(test)
log_empty_message_still_emits_record :: proc(t: ^testing.T) {
	out := with_captured_stderr(
		t,
		proc(t: ^testing.T) {
			log("")
			log_warn("")
			log_error("")
		},
	)
	defer delete(out)

	testing.expect(t, strings.contains(out, "[DEBUG]"))
	testing.expect(t, strings.contains(out, "[WARN]"))
	testing.expect(t, strings.contains(out, "[ERROR]"))
	testing.expect(t, strings.count(out, "\n") >= 3)
}

@(test)
log_formatted_multiple_args :: proc(t: ^testing.T) {
	out := with_captured_stderr(
		t,
		proc(t: ^testing.T) {
			logf("%s-%s-%d", "a", "b", 9)
			log_errorf("%v", true)
			log_warnf("%.2f", 1.5)
		},
	)
	defer delete(out)

	testing.expect(t, strings.contains(out, "a-b-9"))
	testing.expect(t, strings.contains(out, "true"))
	testing.expect(t, strings.contains(out, "1.50") || strings.contains(out, "1.5"))
}

@(test)
log_write_log_exact_format_and_basename :: proc(t: ^testing.T) {
	out := with_captured_stderr(
		t,
		proc(t: ^testing.T) {
			loc := runtime.Source_Code_Location {
				file_path = "/home/dev/src/nested/deep/widget.odin",
				line      = 99,
				procedure = "paint_cell",
			}
			write_log("INFO", "ready", loc)
		},
	)
	defer delete(out)

	testing.expect_value(t, out, "[INFO] [widget.odin:99:paint_cell] ready\n")
	testing.expect(t, !strings.contains(out, "nested"))
	testing.expect(t, !strings.contains(out, "/home"))
}

@(test)
log_write_log_empty_fields_and_custom_level :: proc(t: ^testing.T) {
	out := with_captured_stderr(
		t,
		proc(t: ^testing.T) {
			loc := runtime.Source_Code_Location {
				file_path = "solo.odin",
				line      = 0,
				procedure = "",
			}
			write_log("CUSTOM", "", loc)
			write_log("", "no-level", loc)
		},
	)
	defer delete(out)

	testing.expect(t, strings.contains(out, "[CUSTOM] [solo.odin:0:] \n"))
	testing.expect(t, strings.contains(out, "[] [solo.odin:0:] no-level\n"))
	testing.expect_value(t, strings.count(out, "\n"), 2)
}

@(test)
log_wrappers_honor_explicit_location :: proc(t: ^testing.T) {
	log_test_explicit_loc = runtime.Source_Code_Location {
		file_path = "injected.odin",
		line      = 7,
		procedure = "caller_override",
	}
	out := with_captured_stderr(
		t,
		proc(t: ^testing.T) {
			loc := log_test_explicit_loc
			log("dbg", loc)
			logf("n=%d", 1, loc = loc)
			log_error("err", loc)
			log_errorf("e=%s", "x", loc = loc)
			log_warn("wrn", loc)
			log_warnf("w=%d", 2, loc = loc)
		},
	)
	defer delete(out)

	testing.expect_value(t, strings.count(out, "injected.odin"), 6)
	testing.expect_value(t, strings.count(out, "caller_override"), 6)
	testing.expect_value(t, strings.count(out, ":7:"), 6)
	testing.expect(t, !strings.contains(out, "log_test.odin"))
	testing.expect(t, strings.contains(out, "[DEBUG]"))
	testing.expect(t, strings.contains(out, "[ERROR]"))
	testing.expect(t, strings.contains(out, "[WARN]"))
	testing.expect(t, strings.contains(out, "dbg"))
	testing.expect(t, strings.contains(out, "n=1"))
	testing.expect(t, strings.contains(out, "err"))
	testing.expect(t, strings.contains(out, "e=x"))
	testing.expect(t, strings.contains(out, "wrn"))
	testing.expect(t, strings.contains(out, "w=2"))
}

@(test)
log_caller_location_includes_procedure_and_line :: proc(t: ^testing.T) {
	out := with_captured_stderr(
		t,
		proc(t: ^testing.T) {
			log_test_emit_named_debug()
		},
	)
	defer delete(out)

	testing.expect(t, strings.contains(out, "log_test_emit_named_debug"))
	testing.expect(t, strings.contains(out, "log_test.odin"))
	testing.expect(t, strings.contains(out, "[DEBUG] [log_test.odin:"))
	testing.expect(t, strings.contains(out, "] proc-check\n"))
}

@(private)
log_test_emit_named_debug :: proc() {
	log("proc-check")
}

@(test)
log_message_special_characters_preserved :: proc(t: ^testing.T) {
	out := with_captured_stderr(
		t,
		proc(t: ^testing.T) {
			loc := runtime.Source_Code_Location {
				file_path = "s.odin",
				line      = 1,
				procedure = "p",
			}
			write_log("DEBUG", "tabs\there and 日本語", loc)
			write_log("DEBUG", "line1\nline2", loc)
			logf("pct=%% quoted=%q", "ok")
		},
	)
	defer delete(out)

	testing.expect(t, strings.contains(out, "tabs\there and 日本語"))
	testing.expect(t, strings.contains(out, "line1\nline2"))
	testing.expect(t, strings.contains(out, "pct=%"))
	testing.expect(t, strings.contains(out, "quoted="))
	testing.expect(t, strings.contains(out, "ok"))
}

@(test)
log_output_line_order_matches_call_order :: proc(t: ^testing.T) {
	out := with_captured_stderr(
		t,
		proc(t: ^testing.T) {
			log("first")
			log_warn("second")
			log_error("third")
		},
	)
	defer delete(out)

	first := strings.index(out, "first")
	second := strings.index(out, "second")
	third := strings.index(out, "third")
	testing.expect(t, first >= 0 && second > first && third > second)
	testing.expect(t, strings.index(out, "[DEBUG]") < strings.index(out, "[WARN]"))
	testing.expect(t, strings.index(out, "[WARN]") < strings.index(out, "[ERROR]"))
}

@(test)
log_format_with_zero_args_is_literal :: proc(t: ^testing.T) {
	out := with_captured_stderr(
		t,
		proc(t: ^testing.T) {
			logf("literal-only")
			log_errorf("err-literal")
			log_warnf("warn-literal")
		},
	)
	defer delete(out)

	testing.expect(t, strings.contains(out, "[DEBUG]"))
	testing.expect(t, strings.contains(out, "literal-only"))
	testing.expect(t, strings.contains(out, "[ERROR]"))
	testing.expect(t, strings.contains(out, "err-literal"))
	testing.expect(t, strings.contains(out, "[WARN]"))
	testing.expect(t, strings.contains(out, "warn-literal"))
}

@(test)
log_capture_restores_stderr :: proc(t: ^testing.T) {
	log_test_stderr_before = os.stderr
	out := with_captured_stderr(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, os.stderr != log_test_stderr_before)
			log("temp")
		},
	)
	defer delete(out)
	testing.expect(t, os.stderr == log_test_stderr_before)
	testing.expect(t, strings.contains(out, "temp"))
}

