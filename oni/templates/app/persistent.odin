package app

import "oni:engine"

Persistent :: struct {
	engine: engine.State,
	app:    App_State,
}

persistent: ^Persistent

bind :: proc() {
	engine.Bind(&persistent.engine, &persistent.app.theme)
}

ensure_persistent :: proc() {
	if persistent == nil {
		persistent = new(Persistent)
	}
	bind()
}
