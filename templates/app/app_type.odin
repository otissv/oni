package app

import o "../../oni"

/*
User-defined app classification. Values are stored in engine state via o.Set_App_Type_From.
*/
App_Type :: enum {
	Application,
	Game,
}

install_app_type_defaults :: proc(type: o.App_Type_Id) {
	switch App_Type(int(type)) {
	case .Application:
		o.Shortcut_Install_Tool_Defaults()
	case .Game:
		o.Shortcut_Install_Game_Defaults()
	}
}
