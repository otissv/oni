package oni

import "core:log"

/*
Logs an error message with the caller's source location.

Use for non-recoverable failures; output goes through core:log.
*/
log_error :: proc(msg: string, loc := #caller_location) {
	log.error(msg, location = loc)
}

/*
Logs a formatted error message with the caller's source location.

Use when the message needs printf-style interpolation.
*/
log_errorf :: proc(fmt: string, args: ..any, loc := #caller_location) {
	log.errorf(fmt, ..args, location = loc)
}

/*
Logs a warning message with the caller's source location.

Use for recoverable or degraded conditions that should still be visible.
*/
log_warn :: proc(msg: string, loc := #caller_location) {
	log.warn(msg, location = loc)
}

/*
Logs a formatted warning message with the caller's source location.

Use when the warning needs printf-style interpolation.
*/
log_warnf :: proc(fmt: string, args: ..any, loc := #caller_location) {
	log.warnf(fmt, ..args, location = loc)
}
