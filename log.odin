package oni

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"


write_log :: proc(level: string, msg: string, loc: runtime.Source_Code_Location) {
	file := filepath.base(loc.file_path)
	fmt.fprintf(os.stderr, "[%s] [%s:%d:%s] %s\n", level, file, loc.line, loc.procedure, msg)
}

log :: proc(msg: string, loc := #caller_location) {
	write_log("DEBUG", msg, loc)
}

logf :: proc(format: string, args: ..any, loc := #caller_location) {
	write_log("DEBUG", fmt.tprintf(format, ..args), loc)
}

/*
Logs an error message with the caller's source location.

Use for non-recoverable failures; output writes directly to stderr.
*/
log_error :: proc(msg: string, loc := #caller_location) {
	write_log("ERROR", msg, loc)
}

/*
Logs a formatted error message with the caller's source location.

Use when the message needs printf-style interpolation.
*/
log_errorf :: proc(format: string, args: ..any, loc := #caller_location) {
	msg := fmt.tprintf(format, ..args)
	write_log("ERROR", msg, loc)
}

/*
Logs a warning message with the caller's source location.

Use for recoverable or degraded conditions that should still be visible.
*/
log_warn :: proc(msg: string, loc := #caller_location) {
	write_log("WARN", msg, loc)
}

/*
Logs a formatted warning message with the caller's source location.

Use when the warning needs printf-style interpolation.
*/
log_warnf :: proc(format: string, args: ..any, loc := #caller_location) {
	msg := fmt.tprintf(format, ..args)
	write_log("WARN", msg, loc)
}
