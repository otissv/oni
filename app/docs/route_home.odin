package oni_docs

import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"
import a "../animations"

home_fade: a.Route_Fade

@(private)
home_background :: proc(
	_: o.Widget_Frame_State,
	_: o.Widget_Event(o.Widget_Frame_State),
) -> o.Colors {
	return a.route_fade_color(o.theme.palette[.RED_500], home_fade.opacity)
}

home_route :: proc() {
	w.Rectangle({
		config = {id = "home_rect", background = set.Colors(home_background)},
		on_mount = proc(frame_state: w.Rectangle_State) -> o.Mount {
			return a.route_fade_step(&home_fade, frame_state.mounting)
		},
	})
}
