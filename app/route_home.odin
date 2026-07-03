package app

import oni "../oni"
import set "../oni/set"
import wg "../oni/widgets"

home_fade: Route_Fade

@(private)
home_background :: proc(
	_: oni.Widget_Frame_State,
	_: oni.Widget_Event(oni.Widget_Frame_State),
) -> oni.Colors {
	return route_fade_color(oni.theme.palette[.RED_500], home_fade.opacity)
}

home_route :: proc() {
	wg.Rectangle({
		config = {
			id = "home_rect",
			x = set.F32(0),
			y = set.F32(60),
			background = set.Colors(home_background),
		},
		on_mount = proc(frame_state: wg.Rectangle_State) -> oni.Mount {
			return route_fade_step(&home_fade, frame_state.mounting)
		},
	})
}
