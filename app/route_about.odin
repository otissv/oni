package app

import oni "../oni"
import set "../oni/set"
import wg "../oni/widgets"

about_fade: Route_Fade

@(private)
about_background :: proc(
	_: oni.Widget_Frame_State,
	_: oni.Widget_Event(oni.Widget_Frame_State),
) -> oni.Colors {
	return route_fade_color(oni.theme.palette[.BLUE_500], about_fade.opacity)
}


about_route :: proc() {
	wg.Rectangle({
		config = {
			id = "about_rect",
			x = set.F32(0),
			y = set.F32(60),
			background = set.Colors(about_background),
		},
		on_mount = proc(frame_state: wg.Rectangle_State) -> oni.Mount {
			return route_fade_step(&about_fade, frame_state.mounting)
		},
	})
}
