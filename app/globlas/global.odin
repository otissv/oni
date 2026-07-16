package globals

import o "../../oni"
import w "../../oni/widgets"

Routes :: enum {
	Home,
	About,
	Layout,
	Artboard,
	Widgets,
	Components,
	Shortcuts,
}

/*
App-local state kept in Persistent and rebound for leaf packages.

Storage lives in package app (`Persistent.app`); `app` is a pointer rebound
in `bind()` so components/routes can read it without importing `app`.
*/
Global_State :: struct {
	theme:           o.Theme,
	image_texture:   o.Texture_Handle,
	frame_dt:        f32,
	Route:           Routes,
	shortcuts_path:  string,
	shortcuts_table: w.Shortcuts_Table_Session,
}

app: ^Global_State
