package app

import "oni:engine"
import ui "oni:ui"

Persistent :: struct {
	engine: engine.State,
	app:    App_State,
}

persistent: ^Persistent

register_ui :: proc() {
	engine.Register_UI({
		init        = ui.ui_init,
		shutdown    = ui.ui_shutdown,
		begin_frame = ui.ui_begin_frame,
		end_frame   = ui.ui_end_frame,
	})
}

bind :: proc() {
	engine.Bind(&persistent.engine, &persistent.app.theme)
}

ensure_persistent :: proc() {
	if persistent == nil {
		persistent = new(Persistent)
	}
	register_ui()
	bind()
}
