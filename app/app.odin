package app

import o "../oni"
import set "../oni/set"
import wg "../oni/widgets"


ONI_IMAGE_PATH :: "assets/oni-2.avif"
LIFECYCLE_PANEL_ID :: "lifecycle-demo-panel"

@(private)
panel_state: Panel_State
Panel_State :: struct {
	background: o.Cfg(o.Colors),
	x:          o.Cfg(f32),
}

@(private)
image_texture: o.Texture_Handle


@(init)
register_init :: proc "contextless" () {
	init = run_init
}

@(private)
run_init :: proc() {
	panel := Panel_State {
		background = set.Colors(o.theme.palette[.SECONDARY]),
		x          = set.F32(60),
	}
	panel_state = panel


	tex, ok := o.Load_Texture(ONI_IMAGE_PATH)
	if ok do image_texture = tex
}

Routes :: enum {
	Home,
	About,
	Layout,
	Artboard,
	Widgets,
	Components,
}

Route: Routes = .Widgets

main_ui :: proc() {
	o.Begin_Screen()

	Nav()


	wg.Rectangle({
		config = {id = "main", y = set.F32(60), padding = set.Padding(o.Pd_pos{x = 10, y = 20})},
		child = proc(state: wg.Rectangle_State) {
			#partial switch Route {
			case .Artboard:
				artboard_route()
			case .About:
				about_route()
			case .Layout:
				layout_route()
			case .Home:
				home_route()
			case .Widgets:
				widgets_route()
			}
		},
	})

	o.End_Screen()
}

app_draw :: proc() {
	o.Render(main_ui)
}
