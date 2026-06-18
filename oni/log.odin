package oni

import "core:log"

log_error :: proc(msg: string, loc := #caller_location) {
	log.error(msg, location = loc)
}

log_errorf :: proc(fmt: string, args: ..any, loc := #caller_location) {
	log.errorf(fmt, ..args, location = loc)
}

log_warn :: proc(msg: string, loc := #caller_location) {
	log.warn(msg, location = loc)
}

log_warnf :: proc(fmt: string, args: ..any, loc := #caller_location) {
	log.warnf(fmt, ..args, location = loc)
}
