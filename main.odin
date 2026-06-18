/*
Oni hot-reload host. Loads build/hot_reload/app.so and reloads it when the file
changes. App state lives in heap-allocated memory inside the app library.
*/

package main

import "core:mem"
import host "oni:host"

main :: proc() {
	default_allocator := context.allocator
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, default_allocator)
	context.allocator = mem.tracking_allocator(&tracking)
	defer mem.tracking_allocator_destroy(&tracking)

	api_version, app_api, old_apis, ok := host.init_app(default_allocator, host.DEFAULT_CONFIG)

	if !ok {
		return
	}

	reload_cooldown: int

	for app_api.should_run() {
		host.reload_loop(&app_api, &api_version, &reload_cooldown, &old_apis, &tracking)
		free_all(context.temp_allocator)
	}

	free_all(context.temp_allocator)

	host.shutdown_app(&app_api, &tracking, &old_apis)
}
