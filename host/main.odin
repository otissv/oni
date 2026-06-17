/*
Hot-reload host. Loads build/hot_reload/game.so and reloads it when the file
changes. Game state lives in heap-allocated Game_Memory inside the game library.
*/

package main

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

when ODIN_OS == .Windows {
	GAME_LIB_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
	GAME_LIB_EXT :: ".dylib"
} else {
	GAME_LIB_EXT :: ".so"
}

GAME_LIB_DIR :: "build/hot_reload/"
GAME_LIB_PATH :: GAME_LIB_DIR + "game" + GAME_LIB_EXT

Game_API :: struct {
	lib:             dynlib.Library,
	init_window:     proc(),
	init:            proc(),
	update:          proc(),
	should_run:      proc() -> bool,
	shutdown:        proc(),
	shutdown_window: proc(),
	memory:          proc() -> rawptr,
	memory_size:     proc() -> int,
	hot_reloaded:    proc(mem: rawptr),
	reset:           proc(),
	realloc:         proc(new_size: int),
	force_reload:    proc() -> bool,
	force_restart:   proc() -> bool,
	loaded_mod_nsec: i64,
	api_version:     int,
}

copy_game_lib :: proc(to: string) -> bool {
	if err := os.copy_file(to, GAME_LIB_PATH); err != nil {
		fmt.printfln("Failed to copy {0} to {1}: {2}", GAME_LIB_PATH, to, err)
		return false
	}
	return true
}

load_game_lib_mtime :: proc() -> (nsec: i64, ok: bool) {
	mod_time, err := os.last_write_time_by_name(GAME_LIB_PATH)
	if err != os.ERROR_NONE {
		fmt.printfln("Failed to read modification time of {0}: {1}", GAME_LIB_PATH, err)
		return 0, false
	}
	return time.time_to_unix_nano(mod_time), true
}

load_game_api :: proc(api_version: int) -> (api: Game_API, ok: bool) {
	mod_nsec, mod_ok := load_game_lib_mtime()
	if !mod_ok {
		return
	}

	lib_name := fmt.tprintf(GAME_LIB_DIR + "game_{0}" + GAME_LIB_EXT, api_version)
	copy_game_lib(lib_name) or_return

	_, ok = dynlib.initialize_symbols(&api, lib_name, "game_", "lib")
	if !ok {
		fmt.printfln("Failed to initialize game API from {0}: {1}", lib_name, dynlib.last_error())

		api.api_version = api_version
		unload_game_api(&api)

		return
	}

	api.api_version = api_version
	api.loaded_mod_nsec = mod_nsec
	ok = true
	return
}

unload_game_api :: proc(api: ^Game_API) {
	if api.lib != nil {
		if !dynlib.unload_library(api.lib) {
			fmt.printfln("Failed to unload game library: {0}", dynlib.last_error())
		}
		api.lib = nil
	}

	copy_path := fmt.tprintf(GAME_LIB_DIR + "game_{0}" + GAME_LIB_EXT, api.api_version)
	if os.remove(copy_path) != nil {
		fmt.printfln("Failed to remove {0}", copy_path)
	}
}

wait_for_enter :: proc() {
	buf: [1]u8
	os.read(os.stdin, buf[:])
}

reset_tracking_allocator :: proc(tracking: ^mem.Tracking_Allocator) -> bool {
	leaked := false

	for _, entry in tracking.allocation_map {
		log.errorf("%v: leaked %v bytes", entry.location, entry.size)
		leaked = true
	}

	mem.tracking_allocator_clear(tracking)
	return leaked
}

perform_reload :: proc(
	game_api: ^Game_API,
	new_api: Game_API,
	want_restart: bool,
	reason: string,
	old_apis: ^[dynamic]Game_API,
) {
	layout_changed := game_api.memory_size() != new_api.memory_size()
	full_restart := want_restart || layout_changed

	append(old_apis, game_api^)
	game_memory := game_api.memory()
	game_api^ = new_api
	game_api.hot_reloaded(game_memory)

	if full_restart && layout_changed {
		game_api.realloc(new_api.memory_size())
		fmt.printfln("Reload ({0}): memory layout changed, state reset", reason)
	} else if full_restart {
		game_api.reset()
		fmt.printfln("Reload ({0}): full restart", reason)
	} else {
		fmt.printfln("Reload ({0}): hot reload complete", reason)
	}
}

main :: proc() {
	exe_path := os.args[0]
	exe_dir := filepath.dir(string(exe_path))
	os.set_working_directory(exe_dir)

	context.logger = log.create_console_logger()
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

	default_allocator := context.allocator
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, default_allocator)
	context.allocator = mem.tracking_allocator(&tracking)
	defer mem.tracking_allocator_destroy(&tracking)

	api_version := 0
	game_api, loaded := load_game_api(api_version)
	if !loaded {
		fmt.println("Failed to load game library. Run ./build_hot_reload.sh first.")
		return
	}

	api_version += 1
	game_api.init_window()
	game_api.init()

	old_apis := make([dynamic]Game_API, default_allocator)
	reload_cooldown: int

	for game_api.should_run() {
		game_api.update()

		if reload_cooldown > 0 {
			reload_cooldown -= 1
		}

		want_reload := game_api.force_reload()
		want_restart := game_api.force_restart()
		reload := want_reload || want_restart
		reason := "manual"

		if want_restart {
			reason = "F6"
		} else if want_reload {
			reason = "F5"
		}

		if reload_cooldown == 0 {
			mod_nsec, mod_ok := load_game_lib_mtime()
			if mod_ok && game_api.loaded_mod_nsec != mod_nsec {
				reload = true
				reason = "game.so changed"
			}
		}

		if reload {
			new_api, new_loaded := load_game_api(api_version)
			if new_loaded {
				perform_reload(&game_api, new_api, want_restart, reason, &old_apis)
				api_version += 1
				reload_cooldown = 2
			} else {
				fmt.println("Reload failed, will retry next frame")
			}
		}

		if len(tracking.bad_free_array) > 0 {
			for bad in tracking.bad_free_array {
				log.errorf("Bad free at: %v", bad.location)
			}
			wait_for_enter()

			game_api.shutdown()

			for &old in old_apis {
				unload_game_api(&old)
			}
			delete(old_apis)
			unload_game_api(&game_api)

			free_all(context.temp_allocator)

			panic("Bad free detected")
		}
		free_all(context.temp_allocator)

	}

	free_all(context.temp_allocator)

	game_api.shutdown()

	if reset_tracking_allocator(&tracking) {
		wait_for_enter()
	}

	for &old in old_apis {
		unload_game_api(&old)
	}
	delete(old_apis)

	game_api.shutdown_window()
	unload_game_api(&game_api)
}
