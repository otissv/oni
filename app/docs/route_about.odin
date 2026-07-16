package oni_docs

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"
import a "../animations"


about_fade: a.Route_Fade

@(private)
about_background :: proc(
	_: o.Widget_Frame_State,
	_: o.Widget_Event(o.Widget_Frame_State),
) -> o.Colors {
	return a.route_fade_color(o.theme.palette[.BLUE_500], about_fade.opacity)
}


about_route :: proc() {
	w.Rectangle({
		config = {id = "about_rect", background = set.Colors(about_background)},
		on_mount = proc(frame_state: w.Rectangle_State) -> o.Mount {
			return a.route_fade_step(&about_fade, frame_state.mounting)
		},
	})
}
