package app

import o "../oni"
import set "../oni/set"
import w "../oni/widgets"
import c "./components"
import g "./globlas"
import r "./routes"


@(init)
register_init :: proc "contextless" () {
	init = run_init
}

@(private)
run_init :: proc() {
	r.routes_init()
}


main_ui :: proc() {
	o.Begin_Screen()

	c.Nav()

	w.Rectangle({
		config = {id = "main", y = set.F32(60), padding = set.Padding(o.Pd_struct{x = 10})},
		child = proc(state: w.Rectangle_State) {
			#partial switch g.app.Route {
			case .Artboard:
				r.artboard_route()
			case .About:
				r.about_route()
			case .Layout:
				r.layout_route()
			case .Home:
				r.home_route()
			case .Widgets:
				r.widgets_route()
			}
		},
	})

	o.End_Screen()
}

app_draw :: proc() {
	o.Render(main_ui)
}
