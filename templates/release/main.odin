/*
Oni production host. Statically links the consumer `app` package into one
executable — no hot-reload DLL, no F5/F6, no tracking allocator.

Copy this file to your project as `release/main.odin` (next to `app/` and `oni/`),
or let `./oni/scripts/build_production.sh` create it from this template.
*/

package main

import app "../app"
import oni "../oni"

main :: proc() {
	_ = oni.run_static_app({
		init_window     = app.app_init_window,
		init            = app.app_init,
		update          = app.app_update,
		should_run      = app.app_should_run,
		shutdown        = app.app_shutdown,
		shutdown_window = app.app_shutdown_window,
	})
}
