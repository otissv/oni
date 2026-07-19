package oni

import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:time"
import sdl "vendor:sdl3"


default_context: runtime.Context

/*
Restores the host thread context before calling into the app shared library.

App code uses core:log via oni.log; without this, context.logger is nil in the
loaded .so and log calls are silently dropped.
*/
use_host_context :: proc() {
	context = default_context
}

when ODIN_OS == .Windows {
	APP_LIB_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
	APP_LIB_EXT :: ".dylib"
} else {
	APP_LIB_EXT :: ".so"
}

/*
Host-side configuration for locating and naming the hot-reload app library.
*/
Host_Config :: struct {
	lib_dir:  string,
	lib_name: string,
	prefix:   string,
}

DEFAULT_CONFIG :: Host_Config {
	lib_dir  = "build/hot_reload/",
	lib_name = "app",
	prefix   = "app_",
}

config: Host_Config

host_logger: log.Logger

/*
Returns the path to the hot-reload app shared library on this platform.
*/
app_lib_path :: proc() -> string {
	return fmt.tprintf("{0}{1}{2}", config.lib_dir, config.lib_name, APP_LIB_EXT)
}

/*
Function pointers loaded from the app shared library for the host lifecycle.
*/
App_API :: struct {
	lib:                   dynlib.Library,
	init_window:           proc(),
	init:                  proc(),
	update:                proc(),
	should_run:            proc() -> bool,
	shutdown:              proc(),
	shutdown_window:       proc(),
	memory:                proc() -> rawptr,
	memory_size:           proc() -> int,
	hot_reloaded:          proc(mem: rawptr),
	reset:                 proc(),
	realloc:               proc(new_size: int),
	force_reload:          proc() -> bool,
	force_restart:         proc() -> bool,
	peek_force_reload:     proc() -> bool,
	peek_force_restart:    proc() -> bool,
	consume_force_reload:  proc(),
	consume_force_restart: proc(),
	loaded_mod_nsec:       i64,
	api_version:           int,
}

/*
Per-frame hot reload driver: updates app, watches F5/F6 and .so mtime.

Panics on tracking-allocator bad frees after shutting down loaded libraries.
*/
reloader :: proc(
	app_api: ^App_API,
	api_version: ^int,
	reload_cooldown: ^int,
	old_apis: ^[dynamic]App_API,
	tracking: ^mem.Tracking_Allocator,
) {
	use_host_context()
	app_api.update()

	if reload_cooldown^ > 0 {
		reload_cooldown^ -= 1
	}

	use_host_context()
	want_reload := app_api.peek_force_reload()
	want_restart := app_api.peek_force_restart()
	reload := want_reload || want_restart
	reason := "manual"

	if want_restart {
		reason = "F6"
	} else if want_reload {
		reason = "F5"
	}

	if reload_cooldown^ == 0 {
		mod_nsec, mod_ok := load_app_lib_mtime()
		if mod_ok && app_api.loaded_mod_nsec != mod_nsec {
			reload = true
			reason = "app.so changed"
		}
	}

	if reload {
		new_api, new_loaded := load_app_api(api_version^)
		if new_loaded {
			use_host_context()
			app_api.consume_force_reload()
			app_api.consume_force_restart()
			perform_reload(app_api, new_api, want_restart, reason, old_apis)
			api_version^ += 1
			reload_cooldown^ = 2
		} else {
			fmt.println("Reload failed, will retry next frame")
		}
	}

	if len(tracking.bad_free_array) > 0 {
		for bad in tracking.bad_free_array {
			log.errorf("Bad free at: %v", bad.location)
		}
		wait_for_enter()

		use_host_context()
		app_api.shutdown()

		for &old in old_apis {
			unload_app_api(&old)
		}
		delete(old_apis^)
		unload_app_api(app_api)

		free_all(context.temp_allocator)

		panic("Bad free detected")
	}
}

/*
Copies the built app library to a versioned filename for dynlib loading.
*/
copy_app_lib :: proc(to: string) -> bool {
	path := app_lib_path()
	if err := os.copy_file(to, path); err != nil {
		fmt.printfln("Failed to copy {0} to {1}: {2}", path, to, err)
		return false
	}
	return true
}

/*
Reads the app library file modification time in unix nanoseconds.
*/
load_app_lib_mtime :: proc() -> (nsec: i64, ok: bool) {
	mod_time, err := os.last_write_time_by_name(app_lib_path())
	if err != os.ERROR_NONE {
		fmt.printfln("Failed to read modification time of {0}: {1}", app_lib_path(), err)
		return 0, false
	}
	return time.time_to_unix_nano(mod_time), true
}

/*
Loads a versioned app .so/.dll/.dylib copy and binds exported App_API symbols.
*/
load_app_api :: proc(api_version: int) -> (api: App_API, ok: bool) {
	mod_nsec, mod_ok := load_app_lib_mtime()
	if !mod_ok {
		return
	}

	lib_name := fmt.tprintf(
		"{0}{1}_{2}{3}",
		config.lib_dir,
		config.lib_name,
		api_version,
		APP_LIB_EXT,
	)
	copy_app_lib(lib_name) or_return

	_, ok = dynlib.initialize_symbols(&api, lib_name, config.prefix, "lib")
	if !ok {
		fmt.printfln("Failed to initialize app API from {0}: {1}", lib_name, dynlib.last_error())

		api.api_version = api_version
		unload_app_api(&api)

		return
	}

	api.api_version = api_version
	api.loaded_mod_nsec = mod_nsec
	ok = true
	return
}

/*
Unloads a loaded app library and deletes its versioned copy file.
*/
unload_app_api :: proc(api: ^App_API) {
	if api.lib != nil {
		if !dynlib.unload_library(api.lib) {
			fmt.printfln("Failed to unload app library: {0}", dynlib.last_error())
		}
		api.lib = nil
	}

	copy_path := fmt.tprintf(
		"{0}{1}_{2}{3}",
		config.lib_dir,
		config.lib_name,
		api.api_version,
		APP_LIB_EXT,
	)
	if os.remove(copy_path) != nil {
		fmt.printfln("Failed to remove {0}", copy_path)
	}
}

/*
Blocks until the user presses Enter on stdin.

Used before panic when allocation tracking detects errors.
*/
wait_for_enter :: proc() {
	buf: [1]u8
	os.read(os.stdin, buf[:])
}

/*
Logs leaks, clears tracking allocator state, and returns whether leaks were found.
*/
reset_tracking_allocator :: proc(tracking: ^mem.Tracking_Allocator) -> bool {
	leaked := false

	for _, entry in tracking.allocation_map {
		log.errorf("%v: leaked %v bytes", entry.location, entry.size)
		leaked = true
	}

	mem.tracking_allocator_clear(tracking)
	return leaked
}

/*
Host bootstrap: sets cwd, logging, SDL log hook, loads app lib, runs init_window/init.
*/
init_app :: proc(
	default_allocator: mem.Allocator,
	host_config: Host_Config = DEFAULT_CONFIG,
) -> (
	api_version: int,
	app_api: App_API,
	old_apis: [dynamic]App_API,
	ok: bool,
) {
	config = host_config

	exe_path := os.args[0]
	exe_dir := filepath.dir(string(exe_path))
	os.set_working_directory(exe_dir)

	host_logger = log.create_console_logger()
	context.logger = host_logger
	default_context = context

	sdl.SetLogPriorities(.VERBOSE)
	sdl.SetLogOutputFunction(
		proc "c" (
			userdata: rawptr,
			category: sdl.LogCategory,
			priority: sdl.LogPriority,
			message: cstring,
		) {
			context = default_context
			log.debugf("SDL {} [{}]: {}", category, priority, message)
		},
		nil,
	)

	api_version = 0
	loaded: bool
	app_api, loaded = load_app_api(api_version)
	if !loaded {
		fmt.println("Failed to load app library. Run ./oni/scripts/build_hot_reload.sh first.")
		log.destroy_console_logger(host_logger)
		host_logger = {}
		return
	}

	api_version += 1
	use_host_context()
	app_api.init_window()
	use_host_context()
	app_api.init()

	use_host_context()
	if !app_api.should_run() {
		fmt.println("App exited during init. Check build/hot_reload/app.log for details.")
		use_host_context()
		app_api.shutdown()
		unload_app_api(&app_api)
		if host_logger.procedure != nil {
			log.destroy_console_logger(host_logger)
			host_logger = {}
		}
		return
	}

	old_apis = make([dynamic]App_API, default_allocator)
	ok = true
	return
}

/*
Host teardown: app shutdown, leak check, unload old libs, shutdown_window.
*/
shutdown_app :: proc(
	app_api: ^App_API,
	tracking: ^mem.Tracking_Allocator,
	old_apis: ^[dynamic]App_API,
) {
	use_host_context()
	app_api.shutdown()

	if reset_tracking_allocator(tracking) {
		wait_for_enter()
	}

	for &old in old_apis {
		unload_app_api(&old)
	}
	delete(old_apis^)

	use_host_context()
	app_api.shutdown_window()
	unload_app_api(app_api)

	if host_logger.procedure != nil {
		log.destroy_console_logger(host_logger)
		host_logger = {}
	}
}

/*
Swaps in a new App_API after hot reload; resets or reallocates state as needed.

Full restart runs when F6 is pressed or persistent memory layout changes.
*/
perform_reload :: proc(
	app_api: ^App_API,
	new_api: App_API,
	want_restart: bool,
	reason: string,
	old_apis: ^[dynamic]App_API,
) {
	use_host_context()
	layout_changed := app_api.memory_size() != new_api.memory_size()
	full_restart := want_restart || layout_changed

	append(old_apis, app_api^)
	use_host_context()
	app_memory := app_api.memory()
	app_api^ = new_api
	use_host_context()
	app_api.hot_reloaded(app_memory)

	if full_restart && layout_changed {
		use_host_context()
		app_api.realloc(new_api.memory_size())
		fmt.printfln("Reload ({0}): memory layout changed, state reset", reason)
	} else if full_restart {
		use_host_context()
		app_api.reset()
		fmt.printfln("Reload ({0}): full restart", reason)
	} else {
		fmt.printfln("Reload ({0}): hot reload complete", reason)
	}
}
