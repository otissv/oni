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
Product classification and frame pacing.

Edit `APP_TYPE` / `FRAME_MODE` below — not `exports.odin`, not `settings.kdl`.
Both are required; omitting `FRAME_MODE` is a compile error.
*/
App_Type :: enum {
	Application,
	Game,
}

// Application → tool shortcuts; Game → game shortcuts.
APP_TYPE :: App_Type.Application

// Engine-wide pacing (required). Continuous | On_Demand | Focused
FRAME_MODE :: o.Frame_Mode.Focused

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
	settings_path:   string,
	shortcuts_table: w.Shortcuts_Table_Session,
}

app: ^Global_State
