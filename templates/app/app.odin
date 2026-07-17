package app

import o "../oni"
import set "../oni/set"
import w "../oni/widgets"
import c "./components"
import docs "./docs"
import g "./globlas"


@(init)
register_init :: proc "contextless" () {
	init = run_init
}

@(private)
run_init :: proc() {
	docs.routes_init()
}


main_ui :: proc() {
	o.Begin_Screen()

	c.Nav()

	w.Rectangle({
		config = {id = "main", y = set.F32(60), padding = set.Padding(o.Pd_struct{x = 10})},
		child = proc(state: w.Rectangle_State) {
			#partial switch g.app.Route {
			case .Artboard:
				docs.artboard_route()
			case .About:
				docs.about_route()
			case .Layout:
				docs.layout_route()
			case .Home:
				docs.home_route()
			case .Widgets:
				docs.widgets_route()
			case .Shortcuts:
				docs.shortcuts_route()
			}
		},
	})

	o.End_Screen()
}

app_draw :: proc() {
	o.Render(main_ui)
}
