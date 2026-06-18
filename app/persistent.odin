package app

import oni "../oni"

Persistent :: struct {
	engine: oni.State,
	app:    App_State,
}

persistent: ^Persistent

bind :: proc() {
	oni.Bind(&persistent.engine, &persistent.app.theme)
}

ensure_persistent :: proc() {
	if persistent == nil {
		persistent = new(Persistent)
	}
	bind()
}
